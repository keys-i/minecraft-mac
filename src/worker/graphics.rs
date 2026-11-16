use crate::{atomic, atomic_bytes, build, cli, digest, read_json, session, source};
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use std::fs::{self, File};
use std::io::Read;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;
use std::time::Duration;

pub const COMMIT: &str = "589adb780354b461645b29999cefaf533594ee99";
const UPSTREAM: &str = "3d50d7f39c64778c71d0af2fce1cde818d09ffbce7c4f7b8ae24ae1df567c0ca";
const FILES: &[&str] = &["winemetal.so", "winemetal-upstream.so"];
const HEADERS: &[&str] = &[
    "src/winemetal/winemetal_thunks.h",
    "src/winemetal/winemetal.h",
    "src/winemetal/airconv_thunks.h",
    "src/airconv/airconv_public.h",
];
const FIELDS: &[&str] = &[
    "source_commit",
    "patch_sha256",
    "handoff_patch_sha256",
    "trace_source_sha256",
    "input_header_sha256",
    "upstream_source_sha256",
    "patched_source_sha256",
];
const PROBES: &[(&str, &[&str])] = &[
    (
        "standalone-graphics-probe",
        &[
            "HardwareDeviceAndSwapChain=0x00000000",
            "GPUReadback=0x00000000",
            "RedPixel=0xFF0000FF",
            "HiddenPresent=0x00000000",
        ],
    ),
    (
        "standalone-graphics-shader-probe",
        &[
            "HardwareDevice=0x00000000",
            "ShaderTextureReadback=0x00000000",
            "ShaderDiscardReadback=0x00000000",
        ],
    ),
];
const ASSETS: &[(&str, &str, &str)] = &[
    (
        "dxmt-v0.80-builtin.tar.gz",
        "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz",
        "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d",
    ),
    (
        "dxmt-LICENSE.txt",
        "https://raw.githubusercontent.com/3Shain/dxmt/589adb780354b461645b29999cefaf533594ee99/LICENSE",
        "6b928413c6308c106f3e0080bd94b6427b56d587d400fd40e6cbfbab7d9c4ae1",
    ),
    (
        "dxmt-DXVK-LICENSE.txt",
        "https://raw.githubusercontent.com/3Shain/dxmt/589adb780354b461645b29999cefaf533594ee99/src/util/dxvk.LICENSE",
        "03ca4af84f5cd28cef3ed3f1ef4d17996992d35ccdbe82b29cc020ca02c16f3d",
    ),
    (
        "dxmt-LLVM-LICENSE.txt",
        "https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-15.0.7/llvm/LICENSE.TXT",
        "8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee",
    ),
    (
        "dxmt-MinGW-LICENSE.txt",
        "https://raw.githubusercontent.com/misyltoad/mingw-directx-headers/9df86f2341616ef1888ae59919feaa6d4fad693d/COPYING.MinGW-w64.txt",
        "f38e6194bd3bfa1b654f118e5acefe0aead437bbe669eee43957ccc65a7127f1",
    ),
];

pub fn unmapped(paths: &[PathBuf]) -> Result<()> {
    let existing: Vec<_> = paths.iter().filter(|path| path.exists()).collect();
    if existing.is_empty() {
        return Ok(());
    }
    let output = Command::new("/usr/sbin/lsof")
        .args(["-Fpn", "--"])
        .args(existing)
        .output()?;
    ensure!(
        matches!(output.status.code(), Some(0 | 1)) && output.stderr.is_empty(),
        "Couldn’t establish whether runtime files are mapped"
    );
    ensure!(
        !String::from_utf8_lossy(&output.stdout)
            .lines()
            .any(|line| line.starts_with('p')),
        "Runtime libraries are in use; quit Minecraft normally before replacing them"
    );
    Ok(())
}

pub fn acquire(root: &Path, wine: Option<&Path>) -> Result<()> {
    let downloads = root.join("downloads");
    let stage = root.join("runtime/standalone/dxmt");
    fs::create_dir_all(&downloads)?;
    fs::create_dir_all(&stage)?;
    for &(name, url, expected) in ASSETS {
        let path = downloads.join(name);
        ensure!(
            !path.is_symlink(),
            "A symbolic link blocks graphics acquisition"
        );
        if !path.exists() {
            let temporary = tempfile::NamedTempFile::new_in(&downloads)?;
            build::execute(
                Command::new("curl")
                    .args([
                        "--fail",
                        "--location",
                        "--proto",
                        "=https",
                        "--proto-redir",
                        "=https",
                        "--retry",
                        "3",
                        "--silent",
                        "--show-error",
                        "--output",
                    ])
                    .arg(temporary.path())
                    .arg(url),
            )?;
            ensure!(
                digest(temporary.path())? == expected,
                "Graphics download failed checksum verification: {name}"
            );
            temporary
                .persist_noclobber(&path)
                .map_err(|error| error.error)?;
        }
        ensure!(
            digest(&path)? == expected,
            "Changed graphics download was preserved: {name}"
        );
    }
    let names = [
        "x86_64-windows/d3d11.dll",
        "x86_64-windows/dxgi.dll",
        "x86_64-windows/d3d10core.dll",
        "x86_64-windows/winemetal.dll",
        "x86_64-unix/winemetal.so",
    ];
    let mut hashes = serde_json::Map::new();
    let mut archive = tar::Archive::new(flate2::read::GzDecoder::new(File::open(
        downloads.join(ASSETS[0].0),
    )?));
    for entry in archive.entries()? {
        let mut entry = entry?;
        let name = entry.path()?.to_string_lossy().into_owned();
        let Some(name) = name
            .strip_prefix("v0.80/")
            .filter(|name| names.contains(name))
        else {
            continue;
        };
        ensure!(
            !hashes.contains_key(name)
                && entry.header().entry_type().is_file()
                && entry.size() <= 256 * 1024 * 1024,
            "Invalid graphics archive entry"
        );
        let mut bytes = Vec::new();
        entry.read_to_end(&mut bytes)?;
        ensure!(
            !name.ends_with(".dll")
                || bytes
                    .iter()
                    .take(128)
                    .copied()
                    .collect::<Vec<_>>()
                    .windows(16)
                    .any(|part| part == b"Wine builtin DLL"),
            "Expected Wine builtin graphics marker"
        );
        let destination = stage.join(name);
        fs::create_dir_all(destination.parent().context("Missing graphics directory")?)?;
        atomic_bytes(&destination, &bytes)?;
        hashes.insert(name.into(), digest(&destination)?.into());
    }
    ensure!(
        hashes.len() == names.len(),
        "The graphics release is incomplete"
    );
    fs::create_dir_all(stage.join("licenses"))?;
    for &(name, _, _) in ASSETS.iter().skip(1) {
        atomic_bytes(
            &stage.join("licenses").join(name),
            &fs::read(downloads.join(name))?,
        )?;
    }
    let mut links = serde_json::Map::new();
    let mut overlays = serde_json::Map::new();
    if let Some(wine) = wine {
        let wine = wine.canonicalize()?;
        ensure!(
            !wine
                .components()
                .any(|part| part.as_os_str() == "CrossOver.app"),
            "Use the standalone Wine runtime"
        );
        let directory = wine.join("lib/wine");
        let mut targets: Vec<_> = names.iter().map(|name| directory.join(name)).collect();
        targets.push(directory.join("x86_64-unix/winemetal-upstream.so"));
        unmapped(&targets)?;
        for name in ["ntdll.so", "winemac.so"] {
            let target = directory.join("x86_64-unix").join(name);
            ensure!(target.is_file(), "Wine graphics dependency is missing");
            let link = stage.join("x86_64-unix").join(name);
            if link.is_symlink() {
                ensure!(
                    link.canonicalize()? == target.canonicalize()?,
                    "Unexpected runtime graphics link"
                );
            } else {
                ensure!(
                    !link.exists(),
                    "Refusing to replace an existing graphics link"
                );
                symlink(&target, &link)?;
            }
            links.insert(
                name.into(),
                fs::read_link(link)?.to_string_lossy().into_owned().into(),
            );
        }
        for name in names {
            let target = directory.join(name);
            ensure!(
                !target.is_symlink(),
                "A symbolic link blocks graphics staging"
            );
            let mut overlay = json!({"sha256":hashes[name]});
            if target.exists()
                && digest(&target)? != hashes[name].as_str().context("Missing graphics hash")?
            {
                let original = digest(&target)?;
                let backup = stage
                    .join("wine-originals")
                    .join(format!("{name}.{original}"));
                fs::create_dir_all(
                    backup
                        .parent()
                        .context("Missing graphics backup directory")?,
                )?;
                if backup.exists() {
                    ensure!(digest(&backup)? == original, "Graphics backup is corrupt");
                } else {
                    atomic_bytes(&backup, &fs::read(&target)?)?;
                }
                overlay["backup"] = backup
                    .strip_prefix(&stage)?
                    .to_string_lossy()
                    .into_owned()
                    .into();
            }
            fs::create_dir_all(
                target
                    .parent()
                    .context("Missing runtime graphics directory")?,
            )?;
            atomic_bytes(&target, &fs::read(stage.join(name))?)?;
            ensure!(
                digest(&target)? == hashes[name].as_str().context("Missing graphics hash")?,
                "Graphics overlay failed verification"
            );
            overlays.insert(name.into(), overlay);
        }
        for optional in ["dxmt-unix-bridge.json", "dxmt-pool-adapter.json"] {
            let path = wine.join(optional);
            if path.exists() {
                fs::remove_file(path)?;
            }
        }
    }
    let assets: serde_json::Map<_, _> = ASSETS
        .iter()
        .map(|&(name, url, sha)| (name.into(), json!({"url":url,"sha256":sha})))
        .collect();
    atomic(
        &stage.join("manifest.json"),
        &json!({"component":"DXMT","version":"v0.80","source_commit":COMMIT,"source_url":format!("https://github.com/3Shain/dxmt/tree/{COMMIT}"),"license":"MIT; bundled notices in licenses/","minimum_macos":"15.0","architecture":"x86_64 (Rosetta on Apple Silicon)","apis":["Direct3D 10","Direct3D 11"],"supports_d3d12":false,"wine_dll_path":".","dll_overrides":"d3d11,dxgi,d3d10core,winemetal=b","assets":assets,"files":hashes,"runtime_links":links,"runtime_overlay":overlays,"verification":"Release bytes and builtin markers verified; gameplay requires a separate test"}),
    )?;
    println!("Staged pinned DXMT at {}", stage.display());
    Ok(())
}

fn metadata(root: &Path) -> Result<Value> {
    let tree = root.join("sources/dxmt");
    let output = root.join("build/dxmt-memory-unix");
    let source_path = "src/winemetal/unix/winemetal_unix.c";
    for name in std::iter::once(source_path).chain(HEADERS.iter().copied()) {
        ensure!(
            fs::read(tree.join(name))?
                == source::git(&tree, &["show", &format!("{COMMIT}:{name}")])?,
            "DXMT input differs from pinned source: {name}"
        );
    }
    let patched = output.join("source").join(source_path);
    let text = fs::read_to_string(&patched)?;
    ensure!(
        text.matches("CFRelease(tag_data);").count() == 3
            && text.contains("bool got_gamut")
            && text.matches("@autoreleasepool").count() == 2,
        "Expected memory lifetime fixes are absent"
    );
    ensure!(
        text.matches("launcher_present(").count() == 3
            && text.contains("[buffer addCompletedHandler:"),
        "Expected rendered-frame handoff is absent"
    );
    let headers: serde_json::Map<_, _> = HEADERS
        .iter()
        .map(|name| Ok(((*name).into(), json!(digest(&tree.join(name))?))))
        .collect::<Result<_>>()?;
    Ok(
        json!({"source_commit":COMMIT,"patch_sha256":digest(&root.join("vendor/patches/standalone-dxmt-memory-lifetime.patch"))?,"handoff_patch_sha256":digest(&root.join("vendor/patches/standalone-dxmt-handoff.patch"))?,"trace_source_sha256":digest(&root.join("tools/probes/standalone-dxmt-display-trace.c"))?,"input_header_sha256":headers,"upstream_source_sha256":digest(&tree.join(source_path))?,"patched_source_sha256":digest(&patched)?}),
    )
}

fn manifest(root: &Path) -> Result<Value> {
    let output = root.join("build/dxmt-memory-unix");
    let mut data = metadata(root)?;
    data["version"] = "v0.80".into();
    data["status"] = "Experimental Unix-only rebuild; not installed".into();
    data["fixes"] = json!([
        "display query autorelease pool",
        "output description autorelease pool",
        "ColorSync profile/tag releases",
        "rendered-frame launcher handoff"
    ]);
    data["excluded_fixes"] = json!(["C++ finish-thread autorelease pool"]);
    data["files"] = json!({"winemetal.so":digest(&output.join(FILES[0]))?,"winemetal-upstream.so":digest(&output.join(FILES[1]))?});
    ensure!(
        data["files"][FILES[1]] == UPSTREAM,
        "Upstream shader library changed"
    );
    atomic(&output.join("unix-bridge-manifest.json"), &data)?;
    Ok(data)
}

fn verified(root: &Path, tested: bool) -> Result<Value> {
    let output = root.join("build/dxmt-memory-unix");
    let mut data: Value = read_json(&output.join("unix-bridge-manifest.json"), 128 * 1024)?;
    let current = metadata(root)?;
    ensure!(
        data["version"] == "v0.80" && FIELDS.iter().all(|key| data[key] == current[key]),
        "Bridge inputs changed; rebuild and validate again"
    );
    ensure!(
        data["files"]
            .as_object()
            .is_some_and(|files| files.len() == 2)
            && data["files"][FILES[1]] == UPSTREAM,
        "Unexpected bridge outputs"
    );
    for name in FILES {
        ensure!(
            data["files"][name].as_str() == Some(digest(&output.join(name))?.as_str()),
            "Bridge output changed: {name}"
        );
    }
    if tested {
        let validation: Value = read_json(&output.join("render-validation.json"), 128 * 1024)?;
        ensure!(
            validation["files"] == data["files"]
                && FIELDS.iter().all(|key| validation[key] == data[key]),
            "Render validation does not match this exact build"
        );
        let mut expected: Vec<_> = PROBES.iter().map(|item| item.0.to_owned()).collect();
        expected.sort();
        let mut passed: Vec<String> = serde_json::from_value(validation["passed_probes"].clone())?;
        passed.sort();
        ensure!(
            passed == expected,
            "Both graphics probes must pass before staging"
        );
        data["render_validation"] = validation;
    }
    Ok(data)
}

fn prepare(root: &Path, wine: &Path) -> Result<()> {
    let source_path = "src/winemetal/unix/winemetal_unix.c";
    let tree = root.join("sources/dxmt");
    let output = root.join("build/dxmt-memory-unix");
    ensure!(
        String::from_utf8(source::git(&tree, &["rev-parse", "HEAD"])?)?.trim() == COMMIT,
        "Expected pinned DXMT source"
    );
    let upstream = root.join("runtime/standalone/dxmt/x86_64-unix/winemetal.so");
    ensure!(
        digest(&upstream)? == UPSTREAM,
        "Upstream shader library changed"
    );
    let original = fs::read(tree.join(source_path))?;
    ensure!(
        original == source::git(&tree, &["show", &format!("{COMMIT}:{source_path}")])?,
        "Upstream bridge source was modified"
    );
    let text = std::str::from_utf8(&original)?;
    for name in ["__wine_unix_call_funcs", "__wine_unix_call_wow64_funcs"] {
        let body = text
            .split_once(&format!("const void *{name}[] = {{"))
            .and_then(|(_, tail)| tail.split_once("};"))
            .context("Missing DXMT Unix-call table")?
            .0;
        let entries: Vec<_> = body
            .lines()
            .map(|line| line.trim().trim_end_matches(','))
            .filter(|line| !line.is_empty())
            .collect();
        ensure!(
            entries.len() == 132
                && entries[96] == "&_WMTGetDisplayDescription"
                && entries[101] == "&_WMTQueryDisplaySettingForLayer",
            "Unexpected DXMT Unix-call ABI"
        );
    }
    let target = output.join("source").join(source_path);
    fs::create_dir_all(target.parent().context("Missing bridge source directory")?)?;
    fs::write(&target, &original)?;
    let patch =
        fs::read_to_string(root.join("vendor/patches/standalone-dxmt-memory-lifetime.patch"))?;
    let unix = patch
        .split("--- a/src/dxmt/dxmt_command_queue.cpp\n")
        .next()
        .context("Missing bridge patch")?;
    fs::create_dir_all(root.join("work"))?;
    let temporary = tempfile::NamedTempFile::new_in(root.join("work"))?;
    fs::write(temporary.path(), unix)?;
    for patch in [
        temporary.path().to_path_buf(),
        root.join("vendor/patches/standalone-dxmt-handoff.patch"),
    ] {
        build::execute(
            Command::new("git")
                .args(["apply", "--unsafe-paths"])
                .arg(format!("--directory={}", output.join("source").display()))
                .arg(patch),
        )?;
    }
    build::copy(&upstream, &output.join("winemetal-upstream.so"))?;
    for name in ["ntdll.so", "winemac.so"] {
        let link = output.join(name);
        if link.is_symlink() {
            fs::remove_file(&link)?;
        }
        ensure!(!link.exists(), "Unexpected bridge dependency");
        symlink(
            wine.join("lib/wine/x86_64-unix")
                .join(name)
                .canonicalize()?,
            link,
        )?;
    }
    Ok(())
}

fn validate(root: &Path, wine: &Path, prefix: &Path, cancelled: &AtomicBool) -> Result<()> {
    let data = verified(root, false)?;
    let output = root.join("build/dxmt-memory-unix");
    for name in FILES {
        ensure!(
            digest(&wine.join("lib/wine/x86_64-unix").join(name))?
                == data["files"][name]
                    .as_str()
                    .context("Missing bridge hash")?,
            "Test runtime differs from output"
        );
    }
    for &(probe, expected) in PROBES {
        let path = output.join(format!("validated-{probe}.log"));
        let log = session::private_log(&path)?;
        log.set_len(0)?;
        let mut command = session::clean(wine.join("bin/wine"));
        for (key, _) in std::env::vars_os().filter(|(key, _)| {
            ["BEDROCK_GRAPHICS_", "BEDROCK_DXMT_"]
                .iter()
                .any(|prefix| key.to_string_lossy().starts_with(prefix))
        }) {
            command.env_remove(key);
        }
        command
            .arg(root.join(format!("runtime/standalone/probes/{probe}.exe")))
            .env("WINEPREFIX", prefix)
            .env("WINEARCH", "win64")
            .env(
                "WINEDLLOVERRIDES",
                "mscoree,mshtml=;winemenubuilder.exe=d;d3d11,dxgi,d3d10core,winemetal=b",
            )
            .env("WINEDEBUG", "-all")
            .env("LC_ALL", "en_US.UTF-8")
            .env("DXMT_LOG_LEVEL", "error")
            .env("DXMT_LOG_PATH", &output)
            .stdout(log.try_clone()?)
            .stderr(log);
        session::run(&mut command, cancelled, Some(Duration::from_secs(55)), None)?;
        let text = fs::read_to_string(path)?;
        ensure!(
            expected.iter().all(|line| text.contains(line)),
            "Render validation failed: {probe}"
        );
    }
    for name in FILES {
        ensure!(
            digest(&wine.join("lib/wine/x86_64-unix").join(name))?
                == data["files"][name]
                    .as_str()
                    .context("Missing bridge hash")?
                && digest(&output.join(name))?
                    == data["files"][name]
                        .as_str()
                        .context("Missing bridge hash")?,
            "Bridge changed during validation"
        );
    }
    let mut record = serde_json::Map::new();
    for key in FIELDS {
        record.insert((*key).into(), data[key].clone());
    }
    record.insert("files".into(), data["files"].clone());
    record.insert(
        "passed_probes".into(),
        json!(PROBES.iter().map(|probe| probe.0).collect::<Vec<_>>()),
    );
    atomic(&output.join("render-validation.json"), &record)?;
    Ok(())
}

fn stage(root: &Path, runtime: &Path) -> Result<()> {
    let mut data = verified(root, true)?;
    let runtime = runtime.canonicalize()?;
    let output = root.join("build/dxmt-memory-unix");
    let directory = runtime.join("lib/wine/x86_64-unix");
    let metadata = runtime.join("dxmt-unix-bridge.json");
    let targets = [
        directory.join(FILES[0]),
        directory.join(FILES[1]),
        metadata.clone(),
    ];
    ensure!(
        runtime.join("bin/wine").is_file() && targets[0].is_file(),
        "Expected existing Wine runtime with DXMT"
    );
    for target in &targets {
        ensure!(
            !target.is_symlink()
                && target
                    .parent()
                    .context("Missing runtime parent")?
                    .canonicalize()?
                    .starts_with(&runtime),
            "Escaping bridge destination"
        );
    }
    unmapped(&targets)?;
    let current = digest(&targets[0])?;
    if current != UPSTREAM {
        let previous: Value = read_json(&metadata, 128 * 1024)?;
        ensure!(
            previous["files"][FILES[0]] == current,
            "Refusing to replace an unrecognised bridge"
        );
    }
    let backup = runtime
        .join("dxmt-unix-bridge-backups")
        .join(UPSTREAM)
        .join("winemetal.so");
    fs::create_dir_all(backup.parent().context("Missing bridge backup directory")?)?;
    if backup.exists() {
        ensure!(
            digest(&backup)? == UPSTREAM,
            "Original bridge backup is corrupt"
        );
    } else {
        atomic_bytes(&backup, &fs::read(output.join(FILES[1]))?)?;
    }
    let transaction = tempfile::Builder::new()
        .prefix(".dxmt-stage-")
        .tempdir_in(&runtime)?;
    for (index, target) in targets.iter().enumerate() {
        if target.exists() {
            fs::copy(target, transaction.path().join(format!("saved-{index}")))?;
        }
    }
    for name in FILES {
        fs::copy(output.join(name), transaction.path().join(name))?;
        ensure!(
            digest(&transaction.path().join(name))?
                == data["files"][name]
                    .as_str()
                    .context("Missing bridge hash")?,
            "Prepared bridge changed"
        );
    }
    data["status"] = "Experimental Unix bridge explicitly staged".into();
    data["original_backup"] = backup
        .strip_prefix(&runtime)?
        .to_string_lossy()
        .into_owned()
        .into();
    atomic(&transaction.path().join("dxmt-unix-bridge.json"), &data)?;
    unmapped(&targets)?;
    let mut committed = Vec::new();
    let result = (|| -> Result<()> {
        for index in [1, 0, 2] {
            fs::rename(
                transaction.path().join(
                    targets[index]
                        .file_name()
                        .context("Missing bridge filename")?,
                ),
                &targets[index],
            )?;
            committed.push(index);
        }
        for name in FILES {
            ensure!(
                digest(&directory.join(name))?
                    == data["files"][name]
                        .as_str()
                        .context("Missing bridge hash")?,
                "Installed bridge changed"
            );
        }
        Ok(())
    })();
    if let Err(error) = result {
        let mut failed = false;
        for index in committed.into_iter().rev() {
            let saved = transaction.path().join(format!("saved-{index}"));
            if (if saved.exists() {
                fs::rename(saved, &targets[index])
            } else {
                fs::remove_file(&targets[index])
            })
            .is_err()
            {
                failed = true;
            }
        }
        if failed {
            let retained = transaction.keep();
            bail!(
                "{error}; rollback incomplete, backups retained at {}",
                retained.display()
            );
        }
        return Err(error);
    }
    println!("Staged verified bridge into {}", runtime.display());
    Ok(())
}

pub fn run(root: &Path, mut args: Vec<String>, cancelled: &AtomicBool) -> Result<()> {
    let command = cli::command(
        &mut args,
        "graphics acquire|prepare|manifest|stage|validate|validate-clone",
    )?;
    if command.starts_with("pool-") {
        return pool(root, &command, &args);
    }
    if matches!(command.as_str(), "--help" | "-h") {
        println!(
            "graphics acquire [--wine-runtime PATH]\ngraphics prepare|stage|validate|validate-clone RUNTIME\ngraphics manifest"
        );
        return Ok(());
    }
    if command == "acquire" {
        let wine = cli::option(&mut args, "--wine-runtime")?.map(PathBuf::from);
        ensure!(args.is_empty(), "Unexpected graphics arguments");
        return acquire(root, wine.as_deref());
    }
    if command == "manifest" {
        ensure!(args.is_empty(), "Unexpected manifest argument");
        manifest(root)?;
        return Ok(());
    }
    ensure!(args.len() == 1, "Choose one runtime path");
    let runtime = PathBuf::from(&args[0]);
    match command.as_str() {
        "prepare" => prepare(root, &runtime),
        "stage" => stage(root, &runtime),
        "validate" => validate(
            root,
            &runtime,
            &root.join("runtime/standalone-graphics-validation-prefix"),
            cancelled,
        ),
        "validate-clone" => {
            let data = verified(root, false)?;
            fs::create_dir_all(root.join("runtime"))?;
            let directory = tempfile::Builder::new()
                .prefix(".dxmt-validation-")
                .tempdir_in(root.join("runtime"))?;
            let wine = directory.path().join("wine");
            build::execute(
                Command::new("/bin/cp")
                    .arg("-cR")
                    .arg(runtime.canonicalize()?)
                    .arg(&wine),
            )?;
            for name in FILES {
                fs::copy(
                    root.join("build/dxmt-memory-unix").join(name),
                    wine.join("lib/wine/x86_64-unix").join(name),
                )?;
            }
            let _ = data;
            let prefix = directory.path().join("prefix");
            let result = validate(root, &wine, &prefix, cancelled);
            let cleanup = session::run(
                Command::new(wine.join("bin/wineserver"))
                    .arg("-k")
                    .env("WINEPREFIX", &prefix)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null()),
                &AtomicBool::new(false),
                Some(Duration::from_secs(10)),
                None,
            )
            .and_then(|_| {
                session::run(
                    Command::new(wine.join("bin/wineserver"))
                        .arg("-w")
                        .env("WINEPREFIX", &prefix)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null()),
                    &AtomicBool::new(false),
                    Some(Duration::from_secs(15)),
                    None,
                )
            });
            if let Err(error) = cleanup {
                let retained = directory.keep();
                bail!(
                    "Test runtime did not stop: {error}; preserved at {}",
                    retained.display()
                );
            }
            result
        }
        _ => bail!("Unknown graphics command"),
    }
}

fn pool(root: &Path, command: &str, args: &[String]) -> Result<()> {
    let output = root.join("build/dxmt-autorelease-shim");
    fs::create_dir_all(&output)?;
    let source_path = root.join("tools/probes/standalone-dxmt-autorelease-shim.m");
    if command == "pool-prepare" {
        ensure!(args.is_empty(), "Unexpected adapter arguments");
        let upstream = root.join("runtime/standalone/dxmt/x86_64-unix/winemetal.so");
        let manifest: Value = read_json(
            &root.join("runtime/standalone/dxmt/manifest.json"),
            1024 * 1024,
        )?;
        ensure!(
            manifest["version"] == "v0.80"
                && manifest["source_commit"] == COMMIT
                && manifest["files"]["x86_64-unix/winemetal.so"] == UPSTREAM
                && digest(&upstream)? == UPSTREAM,
            "Adapter requires pinned DXMT v0.80"
        );
        let source =
            fs::read_to_string(root.join("sources/dxmt/src/winemetal/unix/winemetal_unix.c"))?;
        for name in ["__wine_unix_call_funcs", "__wine_unix_call_wow64_funcs"] {
            let body = source
                .split_once(&format!("const void *{name}[] = {{"))
                .and_then(|(_, tail)| tail.split_once("};"))
                .context("Missing adapter ABI table")?
                .0;
            let entries: Vec<_> = body
                .lines()
                .map(|line| line.trim().trim_end_matches(','))
                .filter(|line| !line.is_empty())
                .collect();
            ensure!(
                entries.len() == 132 && entries[101] == "&_WMTQueryDisplaySettingForLayer",
                "Unexpected adapter ABI table"
            );
        }
        fs::copy(upstream, output.join(FILES[1]))?;
        atomic(
            &output.join("upstream-provenance.json"),
            &json!({"version":"v0.80","source_commit":COMMIT,"upstream_sha256":UPSTREAM,"abi_entries":132,"wrapped_entry":101,"wrapped_function":"WMTQueryDisplaySettingForLayer","status":"Experimental diagnostic adapter; not installed into gameplay runtime"}),
        )?;
    } else if command == "pool-manifest" {
        ensure!(args.is_empty(), "Unexpected adapter arguments");
        let mut metadata: Value = read_json(&output.join("upstream-provenance.json"), 65536)?;
        metadata["source_sha256"] = digest(&source_path)?.into();
        metadata["files"] = json!({FILES[0]:digest(&output.join(FILES[0]))?,FILES[1]:digest(&output.join(FILES[1]))?});
        atomic(&output.join("adapter-manifest.json"), &metadata)?;
    } else if command == "pool-stage" {
        ensure!(args.len() == 1, "Choose one adapter runtime");
        let runtime = Path::new(&args[0]).canonicalize()?;
        let metadata: Value = read_json(&output.join("adapter-manifest.json"), 65536)?;
        ensure!(
            metadata["source_sha256"] == digest(&source_path)?,
            "Adapter source changed; rebuild and validate"
        );
        let directory = runtime.join("lib/wine/x86_64-unix");
        ensure!(
            runtime.join("bin/wine").is_file() && directory.join(FILES[0]).is_file(),
            "Expected existing Wine runtime with DXMT"
        );
        let targets: Vec<_> = FILES.iter().map(|name| directory.join(name)).collect();
        unmapped(&targets)?;
        let current = digest(&targets[0])?;
        ensure!(
            FILES.iter().any(|name| metadata["files"][name] == current),
            "Refusing to replace an unknown graphics library"
        );
        for name in FILES {
            ensure!(
                metadata["files"][name] == digest(&output.join(name))?,
                "Adapter artifact changed"
            );
        }
        for name in [FILES[1], FILES[0]] {
            atomic_bytes(&directory.join(name), &fs::read(output.join(name))?)?;
        }
        atomic(&runtime.join("dxmt-pool-adapter.json"), &metadata)?;
    } else {
        bail!("Unknown adapter command");
    }
    Ok(())
}
