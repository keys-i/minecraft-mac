use crate::{
    atomic, atomic_bytes, cli, digest, graphics, launcher, read_json,
    session::{self, Context},
};
use anyhow::{Context as _, Result, ensure};
use serde_json::{Value, json};
use std::fs;
use std::os::unix::fs::symlink;
use std::path::Path;
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

struct Helper<'a> {
    context: &'a Context,
    child: Option<Child>,
}
impl Drop for Helper<'_> {
    fn drop(&mut self) {
        if let Some(child) = &mut self.child {
            if child.try_wait().ok().flatten().is_none() {
                // Only this unreaped helper belongs to the historical session
                unsafe {
                    libc::kill(child.id() as i32, libc::SIGINT);
                }
                if !session::wait(child, Duration::from_secs(8)).unwrap_or(false) {
                    let _ = child.kill();
                    let _ = child.wait();
                }
            }
            let _ = self.context.recover();
            let state = self.context.root.join("runtime/helper-session.json");
            if fs::symlink_metadata("/tmp/xodus.sock").is_err()
                && read_json::<Value>(&state, 65536)
                    .ok()
                    .is_some_and(|value| value["pid"] == child.id())
            {
                let _ = fs::remove_file(state);
            }
        }
    }
}

fn stage(root: &Path) -> Result<()> {
    let bottle = root.join("bottles/Bedrock-Mac");
    let stage = root.join("runtime/winegdk");
    let build = root.join("build/winegdk");
    let cx = root.join("runtime/CrossOver.app/Contents/SharedSupport/CrossOver");
    let system = bottle.join("drive_c/windows/system32");
    let artifacts = [
        (
            build.join("dlls/xgameruntime/x86_64-windows/xgameruntime.dll"),
            stage.join("x86_64-windows/xgameruntime.dll"),
            false,
        ),
        (
            build.join("dlls/xgameruntime/x86_64-windows/xgameruntime.dll"),
            system.join("xgameruntime.dll"),
            false,
        ),
        (
            build.join("dlls/xgameruntime/xgameruntime.so"),
            stage.join("x86_64-unix/xgameruntime.so"),
            false,
        ),
        (
            build.join("dlls/windows.web/x86_64-windows/windows.web.dll"),
            system.join("windows.web.dll"),
            true,
        ),
        (
            build.join("dlls/twinapi.appcore/x86_64-windows/twinapi.appcore.dll"),
            system.join("twinapi.appcore.dll"),
            true,
        ),
        (
            build.join(
                "dlls/windows.ui.core.textinput/x86_64-windows/windows.ui.core.textinput.dll",
            ),
            system.join("windows.ui.core.textinput.dll"),
            true,
        ),
        (
            build.join("dlls/wintypes/x86_64-windows/wintypes.dll"),
            system.join("wintypes.dll"),
            true,
        ),
        (
            root.join("runtime/xgameruntime.dll.threading"),
            system.join("xgameruntime.dll.threading"),
            false,
        ),
    ];
    let targets: Vec<_> = artifacts.iter().map(|item| item.1.clone()).collect();
    graphics::unmapped(&targets)?;
    for (from, _, strip) in &artifacts {
        let bytes = fs::read(from)?;
        ensure!(
            !strip || bytes.get(64..80) == Some(b"Wine builtin DLL"),
            "Unexpected Wine builtin header"
        );
    }
    let mut hashes = serde_json::Map::new();
    for (from, to, strip) in artifacts {
        fs::create_dir_all(to.parent().context("Missing legacy runtime directory")?)?;
        let mut bytes = fs::read(&from)?;
        if strip {
            bytes[64..80].fill(0);
        }
        atomic_bytes(&to, &bytes)?;
        fs::set_permissions(&to, fs::metadata(from)?.permissions())?;
        hashes.insert(
            to.strip_prefix(root)?.to_string_lossy().into_owned(),
            digest(&to)?.into(),
        );
    }
    let link = stage.join("x86_64-unix/ntdll.so");
    if !link.exists() && !link.is_symlink() {
        symlink(cx.join("lib/wine/x86_64-unix/ntdll.so"), link)?;
    }
    let config = bottle.join("cxbottle.conf");
    let backup = bottle.join("cxbottle.conf.before-winegdk");
    if !backup.exists() {
        fs::copy(&config, &backup)?;
    }
    let text = fs::read_to_string(&config)?;
    let marker = "\n;; Minecraft local runtime\n";
    let base = text
        .split(marker)
        .next()
        .context("Missing bottle configuration")?;
    let paths = [
        stage.clone(),
        stage.join("x86_64-windows"),
        cx.join("lib/wine/x86_64-windows"),
        cx.join("lib/wine/i386-windows"),
        cx.join("lib/wine"),
    ];
    atomic_bytes(
        &config,
        format!(
            "{base}{marker}[Wine]\n\"DllPath\" = \"{}\"\n",
            paths
                .iter()
                .map(|path| path.to_string_lossy())
                .collect::<Vec<_>>()
                .join(":")
        )
        .as_bytes(),
    )?;
    atomic(&root.join("runtime/staged-hashes.json"), &hashes)
}

pub fn run(context: &Context, mut args: Vec<String>, cancelled: &AtomicBool) -> Result<()> {
    if args
        .iter()
        .any(|arg| matches!(arg.as_str(), "--help" | "-h"))
    {
        println!("legacy [--check]\nlegacy stage");
        return Ok(());
    }
    if args == ["stage"] {
        return stage(&context.root);
    }
    let check = cli::flag(&mut args, "--check");
    ensure!(args.is_empty(), "Unexpected legacy arguments");
    let helper = context
        .root
        .join("sources/xodus/target/release/examples/bedrock_helper");
    let game = context.game();
    for path in [
        &helper,
        &game.join("Minecraft.Windows.exe"),
        &context.root.join("tools/legacy/run-windows.sh"),
    ] {
        ensure!(
            path.is_file(),
            "Missing legacy component: {}",
            path.display()
        );
    }
    if check {
        println!(
            "Game prepared: {}\nAccount helper running: {}\nAccount socket ready: {}",
            launcher::game_valid(&game)?,
            context.account_pid().is_some(),
            context.ready(None)?
        );
        return Ok(());
    }
    if launcher::game_running()? {
        println!("Minecraft is already running");
        return Ok(());
    }
    let _lock = crate::setup::lock(&context.root, "legacy.lock")?;
    let mut owner = Helper {
        context,
        child: None,
    };
    if !context.ready(None)? && context.account_pid().is_none() {
        let log = session::private_log(&context.root.join("logs/bedrock-helper.log"))?;
        let child = session::clean(helper.canonicalize()?)
            .arg(&game)
            .current_dir(&context.root)
            .env("XODUS_LOG", "off")
            .env("RUST_LOG", "off")
            .stdout(log.try_clone()?)
            .stderr(log)
            .spawn()?;
        let pid = child.id();
        owner.child = Some(child);
        atomic(
            &context.root.join("runtime/helper-session.json"),
            &json!({"pid":pid,"executable":helper}),
        )?;
    }
    let deadline = Instant::now() + Duration::from_secs(900);
    while !context.ready(owner.child.as_mut())? {
        ensure!(
            !cancelled.load(Ordering::Relaxed) && Instant::now() < deadline,
            "Legacy sign-in was cancelled or timed out"
        );
        ensure!(
            owner
                .child
                .as_mut()
                .is_none_or(|child| child.try_wait().ok().flatten().is_none()),
            "Legacy helper stopped; inspect logs/bedrock-helper.log"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
    let log = session::private_log(&context.root.join("logs/minecraft-legacy.log"))?;
    session::run(
        Command::new(context.root.join("tools/legacy/run-windows.sh"))
            .arg(game.join("Minecraft.Windows.exe"))
            .current_dir(&context.root)
            .stdout(log.try_clone()?)
            .stderr(log),
        cancelled,
        None,
        None,
    )
}
