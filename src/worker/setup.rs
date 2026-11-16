use crate::{
    atomic, atomic_bytes, build, cli, digest, launcher, read_json,
    session::{self, Account, Context},
    source, threading,
};
use anyhow::{Context as _, Result, bail, ensure};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::process::Command;
use std::sync::atomic::AtomicBool;
use std::time::Duration;

const STAGES: &[&str] = &["wine", "graphics", "helper", "probes", "bridge"];

pub fn lock(root: &Path, name: &str) -> Result<File> {
    let path = root.join("runtime/standalone");
    fs::create_dir_all(&path)?;
    let lock = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(path.join(name))?;
    lock.try_lock()
        .context("Minecraft or another setup is already running; let it finish first")?;
    Ok(lock)
}

pub fn market(value: &str) -> Result<()> {
    ensure!(
        value.len() == 2 && value.bytes().all(|byte| byte.is_ascii_uppercase()),
        "Market must be a two-letter uppercase country code"
    );
    Ok(())
}

fn installed(context: &Context) -> bool {
    context.helper().is_file()
        && context.prerequisites(&context.game()).is_ok()
        && context.bridge().is_ok()
        && launcher::game_valid(&context.game()).unwrap_or(false)
}

struct Steps<'a> {
    root: &'a Path,
    state: serde_json::Map<String, Value>,
    previous: String,
}

impl<'a> Steps<'a> {
    fn new(root: &'a Path) -> Self {
        let state = read_json::<Value>(
            &root.join("runtime/standalone/start-state.json"),
            1024 * 1024,
        )
        .ok()
        .and_then(|value| value.as_object().cloned())
        .unwrap_or_default();
        Self {
            root,
            state,
            previous: String::new(),
        }
    }
    fn save(&self) -> Result<()> {
        atomic(
            &self.root.join("runtime/standalone/start-state.json"),
            &self.state,
        )
    }
    fn step(
        &mut self,
        name: &str,
        commands: &[Vec<String>],
        inputs: &[String],
        outputs: &[String],
        mut run: impl FnMut(&[String], usize) -> Result<()>,
    ) -> Result<()> {
        let input: serde_json::Map<_, _> = inputs
            .iter()
            .map(|path| Ok((path.clone(), json!(digest(&self.root.join(path))?))))
            .collect::<Result<_>>()?;
        let signature = crate::hex(&Sha256::digest(serde_json::to_vec(
            &json!({"previous":self.previous,"commands":commands,"inputs":input}),
        )?));
        let hashes = || -> Result<Value> {
            Ok(Value::Object(
                outputs
                    .iter()
                    .map(|path| Ok((path.clone(), json!(digest(&self.root.join(path))?))))
                    .collect::<Result<_>>()?,
            ))
        };
        if self.state.get(name).is_some_and(|receipt| {
            receipt["signature"] == signature && hashes().ok() == Some(receipt["outputs"].clone())
        }) {
            self.previous = signature;
            println!("{name} already prepared");
            return Ok(());
        }
        let index = STAGES
            .iter()
            .position(|stage| *stage == name)
            .context("Unknown setup stage")?;
        for stage in &STAGES[index..] {
            self.state.remove(*stage);
        }
        self.save()?;
        for (index, command) in commands.iter().enumerate() {
            run(command, index)?;
        }
        self.state.insert(
            name.into(),
            json!({"signature":signature,"outputs":hashes()?}),
        );
        self.save()?;
        self.previous = signature;
        Ok(())
    }
}

pub fn helper(context: &Context, jobs: usize, cancelled: &AtomicBool) -> Result<()> {
    let output = session::clean("/bin/ps").args(["-axo", "comm="]).output()?;
    ensure!(
        output.status.success()
            && !String::from_utf8_lossy(&output.stdout)
                .lines()
                .any(|line| line.trim().ends_with("/standalone_helper")),
        "Quit Minecraft and its account helper normally before rebuilding the helper"
    );
    let source_path = context.root.join("sources/xodus");
    source::project(
        &context.root,
        &context.root.join("sources"),
        "xodus",
        !source_path.exists(),
    )?;
    let example = source_path.join("crates/xodus-cli/examples/standalone_helper.rs");
    fs::create_dir_all(
        example
            .parent()
            .context("Missing helper source directory")?,
    )?;
    atomic_bytes(
        &example,
        &fs::read(context.root.join("src/standalone-helper.rs"))?,
    )?;
    session::run(
        Command::new("cargo")
            .args(["+1.98.0", "build", "--manifest-path"])
            .arg(source_path.join("Cargo.toml"))
            .args([
                "--release",
                "--locked",
                "-j",
                &jobs.to_string(),
                "-p",
                "xodus-cli",
                "--example",
                "standalone_helper",
            ])
            .current_dir(&context.root)
            .env("XODUS_LOG", "off")
            .env("RUST_LOG", "off"),
        cancelled,
        None,
        None,
    )
}

pub fn download(
    context: &Context,
    game: &Path,
    market: &str,
    cancelled: &AtomicBool,
) -> Result<()> {
    if launcher::game_valid(game)? {
        return Ok(());
    }
    ensure!(
        !game.exists() && !game.is_symlink(),
        "The incomplete game directory was preserved; choose a new --game-dir"
    );
    ensure!(
        !launcher::game_running()? && fs::symlink_metadata("/tmp/xodus.sock").is_err(),
        "Close Minecraft and its account helper before downloading a new installation"
    );
    let _account = Account::start(context, game, true, market, cancelled)?;
    ensure!(
        launcher::game_valid(game)?,
        "The downloaded game did not pass verification"
    );
    Ok(())
}

fn prepare(context: &Context, jobs: usize, market: &str, cancelled: &AtomicBool) -> Result<()> {
    let root = &context.root;
    session::run(
        Command::new("/bin/bash").arg(root.join("tools/build/install.sh")),
        cancelled,
        None,
        None,
    )?;
    for &(name, _, _, _) in source::PROJECTS {
        source::project(
            root,
            &root.join("sources"),
            name,
            !root.join("sources").join(name).exists(),
        )?;
    }
    let mut steps = Steps::new(root);
    let worker = std::env::current_exe()?.to_string_lossy().into_owned();
    let mut wine_inputs = vec![
        "tools/build/wine.sh".to_owned(),
        "src/worker/source.rs".to_owned(),
        "src/worker/wine.rs".to_owned(),
    ];
    for entry in fs::read_dir(root.join("vendor/patches"))? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.contains("wine") && name.ends_with(".patch")
            || name == "minecraft-store-callback.patch"
        {
            wine_inputs.push(format!("vendor/patches/{name}"));
        }
    }
    let specs = [
        (
            "wine",
            vec![vec![
                "/bin/sh".into(),
                root.join("tools/build/wine.sh")
                    .to_string_lossy()
                    .into_owned(),
            ]],
            wine_inputs,
            vec![
                "runtime/standalone/wine/bin/wine",
                "runtime/standalone/wine/build-manifest.json",
                "runtime/standalone/wine/lib/wine/x86_64-unix/ntdll.so",
                "runtime/standalone/wine/lib/wine/x86_64-windows/xgameruntime.dll",
            ],
        ),
        (
            "graphics",
            vec![vec![
                worker.clone(),
                "graphics".into(),
                "acquire".into(),
                "--wine-runtime".into(),
                context.wine().to_string_lossy().into_owned(),
            ]],
            vec!["src/worker/graphics.rs".into()],
            vec![
                "runtime/standalone/dxmt/manifest.json",
                "runtime/standalone/dxmt/x86_64-unix/winemetal.so",
                "runtime/standalone/wine/lib/wine/x86_64-unix/winemetal.so",
            ],
        ),
        (
            "helper",
            vec![vec![
                worker.clone(),
                "setup".into(),
                "helper".into(),
                "--jobs".into(),
                jobs.to_string(),
            ]],
            vec![
                "src/worker/setup.rs".into(),
                "src/standalone-helper.rs".into(),
                "vendor/patches/Cargo.lock".into(),
            ],
            vec!["sources/xodus/target/release/examples/standalone_helper"],
        ),
        (
            "probes",
            vec![vec![
                "/bin/sh".into(),
                root.join("tools/build/probes.sh")
                    .to_string_lossy()
                    .into_owned(),
            ]],
            vec![
                "tools/build/probes.sh".into(),
                "tests/xuser-claims.c".into(),
            ],
            vec![
                "runtime/standalone/probes/standalone-graphics-probe.exe",
                "runtime/standalone/probes/standalone-graphics-shader-probe.exe",
                "runtime/standalone/probes/runtime-auth-probe.exe",
                "runtime/standalone/probes/store-callback-probe.exe",
                "runtime/standalone/probes/runtime-privilege-probe.exe",
                "runtime/standalone/probes/xuser-claims-test.exe",
            ],
        ),
        (
            "bridge",
            vec![
                vec![
                    "/bin/sh".into(),
                    root.join("tools/build/bridge.sh")
                        .to_string_lossy()
                        .into_owned(),
                ],
                vec![
                    worker.clone(),
                    "graphics".into(),
                    "validate-clone".into(),
                    context.wine().to_string_lossy().into_owned(),
                ],
                vec![
                    worker,
                    "graphics".into(),
                    "stage".into(),
                    context.wine().to_string_lossy().into_owned(),
                ],
            ],
            vec![
                "tools/build/bridge.sh".into(),
                "src/worker/graphics.rs".into(),
                "tools/probes/standalone-dxmt-display-trace.c".into(),
                "tools/probes/standalone-dxmt-display-probe.m".into(),
                "vendor/patches/standalone-dxmt-memory-lifetime.patch".into(),
                "vendor/patches/standalone-dxmt-handoff.patch".into(),
            ],
            vec![
                "runtime/standalone/wine/dxmt-unix-bridge.json",
                "runtime/standalone/wine/lib/wine/x86_64-unix/winemetal.so",
                "runtime/standalone/wine/lib/wine/x86_64-unix/winemetal-upstream.so",
            ],
        ),
    ];
    for (name, commands, mut inputs, outputs) in specs {
        if name == "probes" {
            for path in build::files(&root.join("tools/probes"))? {
                inputs.push(path.strip_prefix(root)?.to_string_lossy().into_owned());
            }
        }
        let outputs: Vec<_> = outputs.into_iter().map(str::to_owned).collect();
        steps.step(name, &commands, &inputs, &outputs, |command, index| {
            let path = root.join(format!("logs/standalone/setup/{name}-{}.log", index + 1));
            let log = session::private_log(&path)?;
            log.set_len(0)?;
            println!("Preparing {name}; details at {}", path.display());
            session::run(
                Command::new(&command[0])
                    .args(&command[1..])
                    .env("STANDALONE_JOBS", jobs.to_string())
                    .current_dir(root)
                    .stdout(log.try_clone()?)
                    .stderr(log),
                cancelled,
                None,
                None,
            )
        })?;
    }
    threading::acquire(context, cancelled)?;
    download(context, &context.game(), market, cancelled)
}

pub fn runtime(context: &Context, mut args: Vec<String>, cancelled: &AtomicBool) -> Result<()> {
    let command = cli::command(&mut args, "runtime check|prepare|probe|launch")?;
    if matches!(command.as_str(), "--help" | "-h") {
        println!(
            "runtime check|prepare|launch [--game-dir PATH] [--market CA]\nruntime probe graphics|account|store|privileges|claims [--network-diagnostics]"
        );
        return Ok(());
    }
    let game = cli::option(&mut args, "--game-dir")?
        .map(cli::path)
        .transpose()?
        .unwrap_or(context.game());
    let market = cli::option(&mut args, "--market")?.unwrap_or("CA".into());
    self::market(&market)?;
    let diagnostics = cli::flag(&mut args, "--network-diagnostics");
    let report = cli::flag(&mut args, "--report-game-pid");
    ensure!(
        command == "probe" && args.len() == 1 || args.is_empty(),
        "Unexpected runtime arguments"
    );
    if command == "check" {
        println!(
            "Game prepared: {}\nRuntime prepared: {}\nAccount service running: {}\nMinecraft running: {}",
            launcher::game_valid(&game)?,
            context.prerequisites(&game).is_ok(),
            context.account_pid().is_some(),
            launcher::game_running()?
        );
        return Ok(());
    }
    if command == "launch" && launcher::game_running()? {
        println!("Minecraft is already running");
        return Ok(());
    }
    let _lock = lock(&context.root, "launcher.lock")?;
    context.prepare(&game, cancelled)?;
    if command == "prepare" {
        println!("Standalone prefix prepared");
        return Ok(());
    }
    let executable = if command == "probe" {
        let name = match args[0].as_str() {
            "graphics" => "standalone-graphics-probe.exe",
            "account" => "runtime-auth-probe.exe",
            "store" => "store-callback-probe.exe",
            "privileges" => "runtime-privilege-probe.exe",
            "claims" => "xuser-claims-test.exe",
            _ => bail!("Unknown probe"),
        };
        let account = if ["graphics", "claims"].contains(&args[0].as_str()) {
            None
        } else {
            Some(Account::start(context, &game, false, &market, cancelled)?)
        };
        let result = session::run(
            context
                .environment(context.wine().join("bin/wine"))
                .arg(context.root.join("runtime/standalone/probes").join(name))
                .current_dir(&game),
            cancelled,
            Some(Duration::from_secs(90)),
            None,
        );
        drop(account);
        return result;
    } else {
        ensure!(command == "launch", "Unknown runtime command");
        r"G:\Minecraft.Windows.exe"
    };
    let _account = Account::start(context, &game, false, &market, cancelled)?;
    if !diagnostics && !report {
        return context.launch(&game, cancelled);
    }
    let mut wine = context.environment(context.wine().join("bin/wine"));
    wine.arg(executable).current_dir(&game);
    if diagnostics {
        wine.env(
            "WINEDEBUG",
            "-all,+timestamp,+xuser,+wsdiag,fixme+gdkc,err+seh",
        )
        .env("WINEGDK_HTTP_STATUS_TRACE", "1");
    }
    let log = session::private_log(
        &context
            .root
            .join("logs/standalone/minecraft-diagnostics.log"),
    )?;
    wine.stdout(log.try_clone()?).stderr(log);
    session::run(
        &mut wine,
        cancelled,
        None,
        Some(&|pid| {
            if report {
                println!("BEDROCK_GAME_PID:{pid}");
            }
        }),
    )
}

pub fn run(
    context: &Context,
    mut args: Vec<String>,
    cancelled: &AtomicBool,
    play: bool,
) -> Result<()> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!(
            "{}",
            if play {
                "play [--check] [--setup-only] [--market CA] [--jobs 2]"
            } else {
                "setup helper|threading|download [--game-dir PATH] [--jobs 2] [--market CA]"
            }
        );
        return Ok(());
    }
    let jobs = cli::option(&mut args, "--jobs")?
        .unwrap_or("2".into())
        .parse::<usize>()?;
    ensure!((1..=12).contains(&jobs), "Jobs must be between 1 and 12");
    let market = cli::option(&mut args, "--market")?.unwrap_or("CA".into());
    self::market(&market)?;
    if !play {
        let command = cli::command(&mut args, "setup helper|threading|download")?;
        let game = cli::option(&mut args, "--game-dir")?
            .map(cli::path)
            .transpose()?
            .unwrap_or(context.game());
        ensure!(args.is_empty(), "Unexpected setup arguments");
        return match command.as_str() {
            "helper" => helper(context, jobs, cancelled),
            "threading" => threading::acquire(context, cancelled),
            "download" => download(context, &game, &market, cancelled),
            _ => bail!("Unknown setup command"),
        };
    }
    let check = cli::flag(&mut args, "--check");
    let setup_only = cli::flag(&mut args, "--setup-only");
    ensure!(args.is_empty(), "Unexpected play arguments");
    let ready = installed(context);
    if check {
        println!(
            "{}",
            if ready {
                "Ready to launch"
            } else {
                "Setup needed; run ./minecraft play"
            }
        );
        ensure!(ready, "Setup needed");
        return Ok(());
    }
    ensure!(
        cfg!(target_os = "macos") && cfg!(target_arch = "aarch64"),
        "Use an Apple Silicon Mac running macOS 15 or later"
    );
    let _lock = lock(&context.root, "start.lock")?;
    if launcher::game_running()? {
        println!("Minecraft is already running");
        return Ok(());
    }
    if !ready {
        let _setup = lock(&context.root, "launcher.lock")?;
        prepare(context, jobs, &market, cancelled)?;
        ensure!(
            installed(context),
            "Installation verification failed; rerun ./minecraft play"
        );
    }
    if setup_only {
        context.prepare(&context.game(), cancelled)?;
        return Ok(());
    }
    crate::monitor::run(
        context,
        vec!["play".into(), "--market".into(), market],
        cancelled,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn receipts_retry_and_invalidate_downstream() -> Result<()> {
        let root = tempfile::tempdir()?;
        fs::create_dir_all(root.path().join("runtime/standalone"))?;
        for name in ["wine", "graphics", "helper"] {
            fs::write(root.path().join(format!("{name}.in")), name)?;
        }
        let mut calls = Vec::new();
        for pass in 0..3 {
            if pass == 2 {
                fs::write(root.path().join("graphics.in"), "changed")?;
            }
            let mut steps = Steps::new(root.path());
            for name in ["wine", "graphics", "helper"] {
                steps
                    .step(
                        name,
                        &[vec![name.into()]],
                        &[format!("{name}.in")],
                        &[format!("{name}.out")],
                        |_, _| {
                            calls.push((pass, name));
                            if pass == 0 && name == "helper" {
                                bail!("interrupted");
                            }
                            fs::write(root.path().join(format!("{name}.out")), name)?;
                            Ok(())
                        },
                    )
                    .unwrap_or_else(|error| {
                        assert!(pass == 0 && name == "helper", "{error}");
                    });
            }
        }
        assert_eq!(
            calls,
            vec![
                (0, "wine"),
                (0, "graphics"),
                (0, "helper"),
                (1, "helper"),
                (2, "graphics"),
                (2, "helper")
            ]
        );
        Ok(())
    }
    #[test]
    fn setup_lock_and_market() -> Result<()> {
        let root = tempfile::tempdir()?;
        let first = lock(root.path(), "setup.lock")?;
        assert!(lock(root.path(), "setup.lock").is_err());
        drop(first);
        lock(root.path(), "setup.lock")?;
        assert!(market("AU").is_ok());
        for value in ["us", "USA", "/x", "ÜS"] {
            assert!(market(value).is_err());
        }
        Ok(())
    }
}
