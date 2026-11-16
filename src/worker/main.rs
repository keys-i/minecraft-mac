mod bench;
mod build;
mod cli;
mod graphics;
mod input;
mod launcher;
mod legacy;
mod monitor;
mod preview;
mod session;
mod setup;
mod source;
mod threading;
mod wine;
mod world;

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;
use std::sync::{Arc, atomic::AtomicBool};

fn event(value: Value) {
    let mut output = std::io::stdout().lock();
    let _ = writeln!(output, "{value}");
}

fn digest(path: &Path) -> Result<String> {
    let mut source =
        File::open(path).with_context(|| format!("Couldn’t read {}", path.display()))?;
    let mut checksum = Sha256::new();
    let mut buffer = [0; 1024 * 64];
    loop {
        let count = source.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        checksum.update(&buffer[..count]);
    }
    Ok(hex(&checksum.finalize()))
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8] = b"0123456789abcdef";
    let mut text = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        text.push(DIGITS[usize::from(byte >> 4)] as char);
        text.push(DIGITS[usize::from(byte & 15)] as char);
    }
    text
}

fn atomic(path: &Path, value: &impl serde::Serialize) -> Result<()> {
    let mut stage =
        tempfile::NamedTempFile::new_in(path.parent().context("Missing cache directory")?)?;
    serde_json::to_writer(stage.as_file_mut(), value)?;
    stage.as_file().sync_all()?;
    stage.persist(path).map_err(|error| error.error)?;
    Ok(())
}

fn atomic_bytes(path: &Path, bytes: &[u8]) -> Result<()> {
    if path.is_symlink() {
        bail!("Refusing to replace a symbolic link: {}", path.display());
    }
    let mut stage =
        tempfile::NamedTempFile::new_in(path.parent().context("Missing destination directory")?)?;
    stage.write_all(bytes)?;
    stage.as_file().sync_all()?;
    stage.persist(path).map_err(|error| error.error)?;
    Ok(())
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path, limit: u64) -> Result<T> {
    let mut bytes = Vec::new();
    File::open(path)?.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        bail!("This file is larger than expected");
    }
    Ok(serde_json::from_slice(&bytes)?)
}

fn main() {
    // All worker-created account, world and diagnostic files stay private
    unsafe {
        libc::umask(0o077);
    }
    let cancelled = Arc::new(AtomicBool::new(false));
    let scenery = std::env::args_os()
        .nth(1)
        .is_some_and(|arg| arg == "--scenery" || arg == "scenery");
    let result = (|| -> Result<()> {
        signal_hook::flag::register(signal_hook::consts::SIGTERM, cancelled.clone())?;
        signal_hook::flag::register(signal_hook::consts::SIGINT, cancelled.clone())?;
        if std::env::var_os("BEDROCK_BUNDLE")
            .is_some_and(|path| Path::new(&path).join("preview.json").is_file())
        {
            return preview::run(&std::env::args_os().skip(1).collect::<Vec<_>>(), &cancelled);
        }
        let mut args = std::env::args_os().skip(1);
        match args.next().as_deref().and_then(|value| value.to_str()) {
            Some("--scenery" | "scenery") => world::run(args.collect(), cancelled.clone()),
            Some("input") => input::run(args.collect()),
            Some("benchmark") => {
                if args.next().is_some() {
                    bail!("This command takes no arguments");
                }
                bench::run()
            }
            Some("source") => source::run(
                &session::Context::load()?.root,
                args.map(|arg| {
                    arg.into_string()
                        .map_err(|_| anyhow::anyhow!("Arguments must be UTF-8"))
                })
                .collect::<Result<_>>()?,
            ),
            Some("build") => build::run(
                &session::Context::load()?.root,
                args.map(|arg| {
                    arg.into_string()
                        .map_err(|_| anyhow::anyhow!("Arguments must be UTF-8"))
                })
                .collect::<Result<_>>()?,
            ),
            Some(
                command @ ("graphics" | "monitor" | "runtime" | "setup" | "play" | "wine"
                | "legacy"),
            ) => {
                let context = session::Context::load()?;
                let args = args
                    .map(|arg| {
                        arg.into_string()
                            .map_err(|_| anyhow::anyhow!("Arguments must be UTF-8"))
                    })
                    .collect::<Result<_>>()?;
                match command {
                    "graphics" => graphics::run(&context.root, args, &cancelled),
                    "monitor" => monitor::run(&context, args, &cancelled),
                    "runtime" => setup::runtime(&context, args, &cancelled),
                    "setup" | "play" => setup::run(&context, args, &cancelled, command == "play"),
                    "wine" => wine::run(&context.root, args),
                    "legacy" => legacy::run(&context, args, &cancelled),
                    _ => unreachable!(),
                }
            }
            Some("--status" | "--warmup" | "--sign-out") => {
                launcher::run(std::env::args_os().skip(1).collect(), &cancelled)
            }
            Some("--help" | "-h") => {
                println!(
                    "Usage: minecraft build|source|play|runtime|monitor|legacy|setup|graphics|wine|stream\nUse COMMAND --help for arguments"
                );
                Ok(())
            }
            None => launcher::run(Vec::new(), &cancelled),
            _ => bail!("Choose a supported worker command"),
        }
    })();
    if cancelled.load(std::sync::atomic::Ordering::Relaxed) {
        event(if scenery {
            json!({"state":"world_cancelled"})
        } else {
            json!({"state":"cancelled","title":"Setup paused","detail":"Continue when you’re ready"})
        });
        std::process::exit(130);
    }
    if let Err(error) = result {
        let cli = std::env::args()
            .nth(1)
            .is_some_and(|arg| !arg.starts_with('-') && arg != "scenery");
        if cli {
            eprintln!("Minecraft: {error:#}");
            std::process::exit(1);
        }
        event(if scenery {
            json!({"state":"world_error", "detail":format!("{error:#}")})
        } else {
            json!({"state":"error","title":"Setup needs attention","detail":format!("{error:#}")})
        });
        std::process::exit(1);
    }
}
