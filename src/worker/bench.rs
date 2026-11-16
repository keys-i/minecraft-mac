use anyhow::{Result, ensure};
use serde_json::json;
use std::process::{Command, Stdio};
use std::time::Instant;

pub fn run() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let mut samples = Vec::new();
    for _ in 0..7 {
        let start = Instant::now();
        let output = Command::new(std::env::current_exe()?)
            .arg("--status")
            .env_remove("BEDROCK_BUNDLE")
            .env("BEDROCK_HOME", directory.path())
            .stdin(Stdio::null())
            .output()?;
        ensure!(output.status.success(), "Read-only status benchmark failed");
        let status: serde_json::Value = serde_json::from_slice(&output.stdout)?;
        ensure!(
            status["state"] == "new",
            "The benchmark unexpectedly found an installation"
        );
        samples.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    ensure!(
        std::fs::read_dir(directory.path())?.next().is_none(),
        "Status benchmark wrote to its fixture"
    );
    let mut ordered = samples.clone();
    ordered.sort_by(f64::total_cmp);
    println!(
        "{}",
        json!({"method":"Seven isolated read-only worker status processes; no account or Keychain access","median_ms":ordered[3],"samples_ms":samples})
    );
    Ok(())
}
