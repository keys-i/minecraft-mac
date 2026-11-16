use crate::session::status;
use anyhow::{Result, ensure};
use std::ffi::OsString;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

fn wait(seconds: f64, cancelled: &AtomicBool) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs_f64(seconds);
    while Instant::now() < deadline {
        ensure!(!cancelled.load(Ordering::Relaxed), "Preview paused");
        std::thread::sleep(Duration::from_millis(25));
    }
    Ok(())
}

pub fn run(args: &[OsString], cancelled: &AtomicBool) -> Result<()> {
    ensure!(
        args.len() <= 1
            && args
                .first()
                .is_none_or(|arg| ["--status", "--warmup", "--sign-out"]
                    .iter()
                    .any(|flag| arg == flag)),
        "Unknown preview argument"
    );
    if !args.is_empty() {
        status("new", "Minecraft on your Mac", "", None);
        return Ok(());
    }
    let detail = "Interface preview only; no sign-in, download or game launch";
    status("busy", "Sign in to Microsoft", detail, Some(0.2));
    wait(2.0, cancelled)?;
    for step in 0..41 {
        status(
            "busy",
            "Downloading Minecraft",
            detail,
            Some(0.35 + f64::from(step) / 80.0),
        );
        wait(0.2, cancelled)?;
    }
    status("busy", "Preparing Minecraft", detail, Some(0.9));
    wait(1.0, cancelled)?;
    status("busy", "Finishing setup", detail, Some(0.95));
    wait(1.0, cancelled)?;
    status("playing", "Minecraft is running", detail, None);
    wait(3.0, cancelled)?;
    status(
        "ready",
        "Ready to play",
        "Preview complete; no accounts or game files were accessed",
        None,
    );
    Ok(())
}
