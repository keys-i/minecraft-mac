use std::process::Command;

#[test]
fn help_is_read_only_from_another_directory() {
    let directory = tempfile::tempdir().expect("fixture");
    for command in [
        "source", "build", "play", "runtime", "monitor", "legacy", "setup", "graphics", "wine",
    ] {
        let result = Command::new(env!("CARGO_BIN_EXE_MinecraftWorker"))
            .args([command, "--help"])
            .env_remove("BEDROCK_BUNDLE")
            .env("BEDROCK_HOME", directory.path())
            .current_dir(directory.path())
            .output()
            .expect("help command");
        assert!(
            result.status.success(),
            "{command}: {}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(!result.stdout.is_empty());
    }
    assert_eq!(
        std::fs::read_dir(directory.path())
            .expect("fixture directory")
            .count(),
        0
    );
}

#[test]
fn invalid_commands_and_sources_do_not_touch_data() {
    let directory = tempfile::tempdir().expect("fixture");
    let result = Command::new(env!("CARGO_BIN_EXE_MinecraftWorker"))
        .args(["../private"])
        .env_remove("BEDROCK_BUNDLE")
        .env("BEDROCK_HOME", directory.path())
        .current_dir(directory.path())
        .output()
        .expect("command");
    assert!(!result.status.success());
    let result = Command::new(env!("CARGO_BIN_EXE_MinecraftWorker"))
        .args([
            "source",
            "export",
            directory
                .path()
                .join("output")
                .to_str()
                .expect("fixture path"),
        ])
        .env_remove("BEDROCK_BUNDLE")
        .env("BEDROCK_HOME", directory.path())
        .output()
        .expect("export");
    assert!(!result.status.success());
    assert_eq!(
        std::fs::read_dir(directory.path())
            .expect("fixture directory")
            .count(),
        0
    );
}

#[test]
fn reviewed_export_checks_and_refreshes_its_own_inventory() {
    let directory = tempfile::tempdir().expect("fixture");
    let export = directory.path().join("source");
    let command = |root: &std::path::Path, args: &[&str]| {
        Command::new(env!("CARGO_BIN_EXE_MinecraftWorker"))
            .args(args)
            .env_remove("BEDROCK_BUNDLE")
            .env("BEDROCK_HOME", root)
            .current_dir(directory.path())
            .output()
            .expect("source command")
    };
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let result = command(
        root,
        &["source", "export", export.to_str().expect("fixture path")],
    );
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert!(command(&export, &["source", "check"]).status.success());
    let readme = export.join("README.md");
    let mut text = std::fs::read_to_string(&readme).expect("exported README");
    text.push_str("\nA fixture edit\n");
    std::fs::write(&readme, text).expect("fixture edit");
    assert!(!command(&export, &["source", "check"]).status.success());
    assert!(command(&export, &["source", "inventory"]).status.success());
    assert!(command(&export, &["source", "check"]).status.success());
    let before = std::fs::read(&readme).expect("fixture README");
    assert!(
        !command(
            root,
            &["source", "export", export.to_str().expect("fixture path")]
        )
        .status
        .success()
    );
    assert_eq!(std::fs::read(readme).expect("preserved README"), before);
    assert!(
        std::fs::metadata(export.join("minecraft"))
            .expect("exported command")
            .is_file()
    );
}

#[test]
fn simulated_worker_cannot_run_scenery_or_setup() {
    let directory = tempfile::tempdir().expect("fixture");
    let bundle = directory.path().join("bundle");
    std::fs::create_dir(&bundle).expect("fixture bundle");
    std::fs::write(bundle.join("preview.json"), b"{\"version\":1}").expect("preview marker");
    for flag in ["--status", "--warmup", "--sign-out"] {
        let result = Command::new(env!("CARGO_BIN_EXE_MinecraftWorker"))
            .arg(flag)
            .env("BEDROCK_BUNDLE", &bundle)
            .env("BEDROCK_HOME", directory.path())
            .output()
            .expect("preview status");
        assert!(result.status.success());
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&result.stdout).expect("preview JSON")["state"],
            "new"
        );
    }
    let result = Command::new(env!("CARGO_BIN_EXE_MinecraftWorker"))
        .arg("--scenery")
        .env("BEDROCK_BUNDLE", &bundle)
        .output()
        .expect("preview scenery rejection");
    assert!(!result.status.success());
    assert_eq!(
        std::fs::read_dir(directory.path())
            .expect("fixture directory")
            .count(),
        1
    );
}
