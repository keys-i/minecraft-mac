use crate::{atomic, cli, digest, session, source};
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use sha2::Digest;
use std::fs;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::Command;

const NAME: &str = "Minecraft Launcher";

pub fn execute(command: &mut Command) -> Result<()> {
    let status = command.status()?;
    ensure!(
        status.success(),
        "Command failed with {status}: {}",
        command.get_program().to_string_lossy()
    );
    Ok(())
}

pub fn copy(from: &Path, to: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(from)?;
    if metadata.is_symlink() {
        if let Some(parent) = to.parent() {
            fs::create_dir_all(parent)?;
        }
        symlink(fs::read_link(from)?, to)?;
    } else if metadata.is_dir() {
        fs::create_dir_all(to)?;
        for entry in fs::read_dir(from)? {
            let entry = entry?;
            let path = entry.path();
            if ["a", "o", "def", "debug"]
                .iter()
                .any(|extension| path.extension().is_some_and(|value| value == *extension))
            {
                continue;
            }
            copy(&path, &to.join(entry.file_name()))?;
        }
        fs::set_permissions(to, metadata.permissions())?;
    } else {
        ensure!(
            metadata.is_file(),
            "Unsupported build input: {}",
            from.display()
        );
        fs::create_dir_all(to.parent().context("Missing build parent")?)?;
        fs::copy(from, to)?;
    }
    Ok(())
}

pub fn files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut result = Vec::new();
    for item in fs::read_dir(root)? {
        let item = item?;
        let path = item.path();
        let kind = item.file_type()?;
        if kind.is_dir() {
            result.extend(files(&path)?);
        } else if kind.is_file() {
            result.push(path);
        }
    }
    result.sort();
    Ok(result)
}

fn sign(path: &Path, deep: bool) -> Result<()> {
    let mut command = Command::new("codesign");
    command.args(["--force", "--sign", "-"]);
    if deep {
        command.arg("--deep");
    }
    execute(command.arg(path))
}

pub fn verify(path: &Path) -> Result<()> {
    execute(
        Command::new("codesign")
            .args(["--verify", "--deep", "--strict"])
            .arg(path),
    )
}

pub fn payload(app: &Path) -> Result<()> {
    verify(app)?;
    let root = app.canonicalize()?;
    let resources = root.join("Contents/Resources");
    let inventory: std::collections::BTreeMap<String, String> =
        crate::read_json(&resources.join("payload-sha256.json"), 8 * 1024 * 1024)?;
    for (name, expected) in &inventory {
        ensure!(
            !name.is_empty()
                && Path::new(name)
                    .components()
                    .all(|part| matches!(part, std::path::Component::Normal(_)))
                && !name.contains(['\\', '\n', '\r']),
            "Unsafe payload entry"
        );
        let file = resources.join(name);
        ensure!(
            !file.is_symlink()
                && file.canonicalize()?.starts_with(&resources)
                && digest(&file)? == *expected,
            "Packaged resource differs: {name}"
        );
    }
    let actual: std::collections::BTreeSet<_> = files(&resources)?
        .iter()
        .map(|path| {
            path.strip_prefix(&resources)
                .map(|path| path.to_string_lossy().into_owned())
        })
        .collect::<std::result::Result<_, _>>()?;
    let expected: std::collections::BTreeSet<_> = inventory
        .keys()
        .cloned()
        .chain(["payload-sha256.json".into()])
        .collect();
    ensure!(
        actual == expected,
        "The package contains unrecorded or missing resources"
    );
    fn links(directory: &Path, root: &Path) -> Result<()> {
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let path = entry.path();
            let kind = entry.file_type()?;
            if kind.is_symlink() {
                ensure!(
                    path.canonicalize()?.starts_with(root),
                    "Packaged link escapes the app: {}",
                    path.display()
                );
            } else if kind.is_dir() {
                links(&path, root)?;
            }
        }
        Ok(())
    }
    links(&resources, &root)?;
    let info = plist::Value::from_file(root.join("Contents/Info.plist"))?;
    let minimum = info
        .as_dictionary()
        .and_then(|info| info.get("LSMinimumSystemVersion"))
        .and_then(plist::Value::as_string)
        .context("Missing packaged minimum OS")?;
    println!(
        "Verified {} resources; minimum macOS {minimum}",
        inventory.len()
    );
    Ok(())
}

fn licences(root: &Path, resources: &Path) -> Result<()> {
    let output = Command::new("cargo")
        .current_dir(root)
        .args(["metadata", "--locked", "--format-version", "1"])
        .output()?;
    ensure!(
        output.status.success(),
        "Couldn’t collect Rust dependency notices"
    );
    let metadata: Value = serde_json::from_slice(&output.stdout)?;
    let packages = metadata["packages"]
        .as_array()
        .context("Missing Rust package metadata")?;
    for package in packages
        .iter()
        .filter(|package| !package["source"].is_null())
    {
        let directory = Path::new(
            package["manifest_path"]
                .as_str()
                .context("Missing dependency manifest")?,
        )
        .parent()
        .context("Missing dependency directory")?;
        let name = package["name"]
            .as_str()
            .context("Missing dependency name")?;
        let version = package["version"]
            .as_str()
            .context("Missing dependency version")?;
        let destination = resources
            .join("vendor/licenses/rust")
            .join(format!("{name}-{version}"));
        fs::create_dir_all(&destination)?;
        atomic(
            &destination.join("package.json"),
            &json!({"name":name,"version":version,"licence":package["license"],"repository":package["repository"]}),
        )?;
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            let filename = entry.file_name();
            let upper = filename.to_string_lossy().to_uppercase();
            if entry.file_type()?.is_file()
                && ["LICENSE", "LICENCE", "COPYING", "COPYRIGHT", "NOTICE"]
                    .iter()
                    .any(|prefix| upper.starts_with(prefix))
            {
                ensure!(
                    entry.metadata()?.len() <= 2 * 1024 * 1024,
                    "Oversized dependency notice"
                );
                copy(&entry.path(), &destination.join(filename))?;
            }
        }
    }
    Ok(())
}

pub fn native(root: &Path, tests: bool, output: &Path) -> Result<()> {
    let leveldb = root.join("build/leveldb/libleveldb.a");
    let configured = fs::read_to_string(root.join("build/leveldb/CMakeCache.txt"))
        .is_ok_and(|text| text.contains("CMAKE_OSX_DEPLOYMENT_TARGET:STRING=15.0"));
    if !leveldb.is_file() || !configured {
        if !root.join("sources/leveldb").exists() {
            source::project(root, &root.join("sources"), "leveldb", true)?;
        }
        execute(
            Command::new("cmake")
                .arg("-S")
                .arg(root.join("sources/leveldb"))
                .arg("-B")
                .arg(leveldb.parent().context("Missing LevelDB directory")?)
                .args([
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DCMAKE_OSX_DEPLOYMENT_TARGET:STRING=15.0",
                    "-DLEVELDB_BUILD_TESTS=OFF",
                    "-DLEVELDB_BUILD_BENCHMARKS=OFF",
                    "-DLEVELDB_INSTALL=OFF",
                    "-DHAVE_SNAPPY=OFF",
                    "-DHAVE_ZSTD=OFF",
                ]),
        )?;
        execute(
            Command::new("cmake")
                .arg("--build")
                .arg(leveldb.parent().context("Missing LevelDB directory")?)
                .args(["--parallel", "2"]),
        )?;
    }
    let cache = root.join("build/swift-module-cache");
    fs::create_dir_all(&cache)?;
    let mut command = Command::new("xcrun");
    command
        .args([
            "swiftc",
            "-parse-as-library",
            "-whole-module-optimization",
            "-O",
            "-disable-sandbox",
            "-target",
            "arm64-apple-macos15.0",
            "-module-cache-path",
        ])
        .arg(cache)
        .arg("-I")
        .arg(root.join("sources/leveldb/include"))
        .arg("-import-objc-header")
        .arg(root.join("src/launcher/Chunks.h"));
    if tests {
        command.args(["-g", "-assert-config", "Debug", "-D", "LAUNCHER_TEST"]);
    }
    for path in files(&root.join("src/launcher"))? {
        if path
            .extension()
            .is_some_and(|extension| extension == "swift")
            && path.file_name().is_none_or(|name| name != "Icon.swift")
        {
            command.arg(path);
        }
    }
    if tests {
        command.arg(root.join("tests/launcher.swift"));
        command.arg(root.join("tests/light.swift"));
        command.arg(root.join("tests/render.swift"));
        command.arg(root.join("tests/rig.swift"));
    }
    execute(
        command
            .arg(leveldb)
            .args(["-Xlinker", "-lc++", "-lz", "-o"])
            .arg(output),
    )
}

pub fn launcher(root: &Path, icon: Option<&Path>) -> Result<PathBuf> {
    let app = root.join(format!("build/{NAME}.app"));
    let resources = app.join("Contents/Resources");
    fs::create_dir_all(&resources)?;
    let executable = app.join("Contents/MacOS/BedrockLauncher");
    fs::create_dir_all(
        executable
            .parent()
            .context("Missing executable directory")?,
    )?;
    native(root, false, &executable)?;
    for name in ["overworld.jpg", "nether.jpg", "end.jpg", "sift.jpg"] {
        match fs::remove_file(resources.join(name)) {
            Ok(()) => (),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
            Err(error) => return Err(error.into()),
        }
    }
    for (from, to) in [
        ("assets/poster.webp", "poster.webp"),
        ("assets/Monocraft.ttf", "Monocraft.ttf"),
        (
            "vendor/licenses/Monocraft-OFL.txt",
            "vendor/licenses/Monocraft-OFL.txt",
        ),
    ] {
        copy(&root.join(from), &resources.join(to))?;
    }
    execute(
        Command::new("xcrun")
            .args([
                "clang",
                "-arch",
                "x86_64",
                "-dynamiclib",
                "-Os",
                "-mmacosx-version-min=15.0",
            ])
            .arg(root.join("src/launcher/Network.c"))
            .arg("-o")
            .arg(resources.join("Network.dylib")),
    )?;
    sign(&resources.join("Network.dylib"), false)?;
    if let Some(icon) = icon {
        copy(icon, &resources.join("AppIcon.icns"))?;
    } else {
        let icon = root.join("build/make-icon");
        let iconset = root.join("build/AppIcon.iconset");
        execute(
            Command::new("xcrun")
                .args(["swiftc", "-O", "-module-cache-path"])
                .arg(root.join("build/swift-module-cache"))
                .arg(root.join("src/launcher/Icon.swift"))
                .arg("-o")
                .arg(&icon),
        )?;
        execute(Command::new(icon).arg(&iconset))?;
        execute(
            Command::new("iconutil")
                .args(["-c", "icns"])
                .arg(iconset)
                .arg("-o")
                .arg(resources.join("AppIcon.icns")),
        )?;
    }
    let mut info = plist::Dictionary::new();
    for (key, value) in [
        ("CFBundleExecutable", "BedrockLauncher"),
        ("CFBundleIdentifier", "local.bedrock.mac.launcher"),
        ("CFBundleName", NAME),
        ("CFBundleDisplayName", NAME),
        ("CFBundlePackageType", "APPL"),
        ("CFBundleIconFile", "AppIcon"),
        ("CFBundleVersion", "40"),
        ("CFBundleShortVersionString", "0.17.0"),
        ("LSMinimumSystemVersion", "15.0"),
        (
            "BedrockProjectPath",
            root.to_str().context("Non-UTF-8 project path")?,
        ),
    ] {
        info.insert(key.into(), value.into());
    }
    info.insert("NSHighResolutionCapable".into(), true.into());
    plist::Value::Dictionary(info).to_file_xml(app.join("Contents/Info.plist"))?;
    sign(&app, false)?;
    println!("Built {}", app.display());
    Ok(app)
}

fn minimum(root: &Path) -> Result<String> {
    use std::io::Read;
    let mut minimum = vec![15, 0];
    let mut text = "15.0".to_owned();
    let pattern = regex::Regex::new(
        r"(?:\bminos\s+|LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version )([0-9.]+)",
    )?;
    for path in files(root)? {
        let mut magic = [0; 4];
        if fs::File::open(&path)?.read(&mut magic)? != 4 {
            continue;
        }
        if ![
            [0xcf, 0xfa, 0xed, 0xfe],
            [0xce, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe],
            [0xca, 0xfe, 0xba, 0xbf],
        ]
        .contains(&magic)
        {
            continue;
        }
        let output = Command::new("otool").arg("-l").arg(&path).output()?;
        ensure!(output.status.success(), "Couldn’t read native minimum OS");
        for capture in pattern.captures_iter(&String::from_utf8_lossy(&output.stdout)) {
            let version = capture[1]
                .split('.')
                .map(str::parse::<u32>)
                .collect::<std::result::Result<Vec<_>, _>>()?;
            if version > minimum {
                minimum = version;
                text = capture[1].to_owned();
            }
        }
    }
    Ok(text)
}

fn graphics(resources: &Path, bridge: Option<&Value>) -> Result<()> {
    let wine = resources.join("runtime/wine/lib/wine");
    let dxmt = resources.join("runtime/dxmt");
    for name in [
        "x86_64-windows/d3d11.dll",
        "x86_64-windows/dxgi.dll",
        "x86_64-windows/d3d10core.dll",
        "x86_64-windows/winemetal.dll",
        "x86_64-unix/winemetal.so",
    ] {
        let from = dxmt.join(name);
        let mut to = wine.join(name);
        if name == "x86_64-unix/winemetal.so" && bridge.is_some() {
            to.set_file_name("winemetal-upstream.so");
        }
        ensure!(
            digest(&from)? == digest(&to)?,
            "Graphics overlay differs: {name}"
        );
        let relative = if name.starts_with("x86_64-unix/") && bridge.is_some() {
            "../../wine/lib/wine/x86_64-unix/winemetal-upstream.so".to_owned()
        } else {
            format!("../../wine/lib/wine/{name}")
        };
        fs::remove_file(&from)?;
        symlink(relative, from)?;
    }
    Ok(())
}

pub fn assemble(root: &Path, app: &Path, preview: bool, bundle: Option<&Path>) -> Result<()> {
    ensure!(
        !app.exists() && !app.is_symlink(),
        "Output already exists; choose a new path"
    );
    fs::create_dir_all(app.parent().context("Missing package parent")?)?;
    let context = session::Context {
        root: root.into(),
        bundle: None,
    };
    if let Some(bundle) = bundle {
        verify(
            bundle
                .parent()
                .and_then(Path::parent)
                .context("Choose an app's Contents/Resources directory")?,
        )?;
    }
    let wine = bundle
        .map(|path| path.join("runtime/wine"))
        .unwrap_or(context.wine());
    let dxmt = bundle
        .map(|path| path.join("runtime/dxmt"))
        .unwrap_or(context.dxmt());
    let helper = bundle
        .map(|path| path.join("standalone_helper"))
        .unwrap_or(context.helper());
    let bridge = if !preview && wine.join("dxmt-unix-bridge.json").is_file() {
        session::bridge(
            &wine,
            &dxmt,
            &bundle
                .map(|path| path.join("scripts"))
                .unwrap_or(root.into()),
        )?;
        Some(crate::read_json::<Value>(
            &wine.join("dxmt-unix-bridge.json"),
            64 * 1024,
        )?)
    } else {
        None
    };
    if !preview {
        for path in [
            wine.join("build-manifest.json"),
            dxmt.join("manifest.json"),
            helper.clone(),
        ] {
            ensure!(
                path.is_file(),
                "Complete the developer build first: {}",
                path.display()
            );
        }
    }
    let icon = bundle.map(|resources| resources.join("AppIcon.icns"));
    let launcher = launcher(root, icon.as_deref())?;
    execute(Command::new("cargo").current_dir(root).args([
        "build",
        "--locked",
        "--release",
        "--bin",
        "MinecraftWorker",
    ]))?;
    let stage = tempfile::Builder::new()
        .prefix(".package-")
        .tempdir_in(app.parent().context("Missing package parent")?)?;
    let candidate = stage.path().join(format!("{NAME}.app"));
    copy(&launcher, &candidate)?;
    let resources = candidate.join("Contents/Resources");
    copy(
        &root.join("target/release/MinecraftWorker"),
        &resources.join("worker/BedrockWorker"),
    )?;
    licences(root, &resources)?;
    if preview {
        fs::write(resources.join("preview.json"), b"{\"version\":1}")?;
    } else {
        let packaged = resources.join("runtime/wine");
        fs::create_dir_all(packaged.join("bin"))?;
        for name in [
            "wine",
            "wine64",
            "wineserver",
            "wine-preloader",
            "wine64-preloader",
        ] {
            let from = wine.join("bin").join(name);
            if from.exists() || from.is_symlink() {
                copy(&from, &packaged.join("bin").join(name))?;
            }
        }
        for name in ["lib", "share/wine", "build-manifest.json"] {
            copy(&wine.join(name), &packaged.join(name))?;
        }
        for name in ["manifest.json", "x86_64-windows", "x86_64-unix", "licenses"] {
            copy(&dxmt.join(name), &resources.join("runtime/dxmt").join(name))?;
        }
        copy(&helper, &resources.join("standalone_helper"))?;
        copy(
            &root.join("src/winrt.reg"),
            &resources.join("scripts/winrt.reg"),
        )?;
        if bridge.is_some() {
            for name in [
                "vendor/patches/standalone-dxmt-memory-lifetime.patch",
                "vendor/patches/standalone-dxmt-handoff.patch",
                "tools/probes/standalone-dxmt-display-trace.c",
            ] {
                copy(&root.join(name), &resources.join("scripts").join(name))?;
            }
        }
        copy(
            &root.join("vendor/licenses"),
            &resources.join("vendor/licenses"),
        )?;
        copy(
            &root.join("vendor/README.md"),
            &resources.join("vendor/README.md"),
        )?;
        copy(&root.join("LICENSE"), &resources.join("LICENSE"))?;
        graphics(&resources, bridge.as_ref())?;
        for path in files(&packaged.join("bin"))? {
            sign(&path, false)?;
            verify(&path)?;
        }
    }
    sign(&candidate, true)?;
    if !preview {
        // Preserve the already authorised helper's exact signed bytes
        fs::copy(&helper, resources.join("standalone_helper"))?;
        verify(&resources.join("standalone_helper"))?;
        ensure!(
            digest(&helper)? == digest(&resources.join("standalone_helper"))?,
            "The authorised helper changed during packaging"
        );
    }
    if let Some(mut bridge) = bridge {
        bridge["source_files"] = bridge["files"].clone();
        for name in ["winemetal.so", "winemetal-upstream.so"] {
            bridge["files"][name] = digest(
                &resources
                    .join("runtime/wine/lib/wine/x86_64-unix")
                    .join(name),
            )?
            .into();
        }
        bridge["packaged_upstream_sha256"] =
            digest(&resources.join("runtime/dxmt/x86_64-unix/winemetal.so"))?.into();
        atomic(
            &resources.join("runtime/wine/dxmt-unix-bridge.json"),
            &bridge,
        )?;
    }
    let inventory: serde_json::Map<String, Value> = files(&resources)?
        .into_iter()
        .map(|path| {
            Ok((
                path.strip_prefix(&resources)?
                    .to_string_lossy()
                    .into_owned(),
                json!(digest(&path)?),
            ))
        })
        .collect::<Result<_>>()?;
    atomic(&resources.join("payload-sha256.json"), &inventory)?;
    let path = candidate.join("Contents/Info.plist");
    let mut info = plist::Value::from_file(&path)?;
    let dictionary = info
        .as_dictionary_mut()
        .context("Missing bundle information")?;
    dictionary.remove("BedrockProjectPath");
    if preview {
        let identity = crate::hex(&sha2::Sha256::digest(
            std::path::absolute(app)?.as_os_str().as_encoded_bytes(),
        ));
        dictionary.insert(
            "CFBundleIdentifier".into(),
            format!("local.bedrock.mac.preview.{}", &identity[..12]).into(),
        );
        dictionary.insert(
            "CFBundleDisplayName".into(),
            format!("{NAME} Preview").into(),
        );
    }
    dictionary.insert(
        "LSMinimumSystemVersion".into(),
        minimum(&candidate.join("Contents"))?.into(),
    );
    info.to_file_xml(path)?;
    sign(&candidate, false)?;
    verify(&candidate)?;
    payload(&candidate)?;
    source::exclusive(&candidate, app)?;
    println!("{}", app.display());
    Ok(())
}

pub fn run(root: &Path, mut args: Vec<String>) -> Result<()> {
    let command = cli::command(&mut args, "build launcher|app|preview|dmg|test")?;
    let output = cli::option(&mut args, "--output")?
        .map(cli::path)
        .transpose()?;
    let input = cli::option(&mut args, "--app")?
        .map(cli::path)
        .transpose()?;
    let bundle = cli::option(&mut args, "--runtime-bundle")?
        .map(cli::path)
        .transpose()?;
    ensure!(args.is_empty(), "Unexpected build arguments");
    match command.as_str() {
        "verify" => {
            payload(&input.unwrap_or(root.join(format!("build/packaged/{NAME}.app"))))?;
        }
        "launcher" => {
            launcher(root, None)?;
        }
        "app" | "preview" => assemble(
            root,
            &output.unwrap_or(root.join(if command == "app" {
                format!("build/packaged/{NAME}.app")
            } else {
                format!("build/preview/{NAME} Preview.app")
            })),
            command == "preview",
            bundle.as_deref(),
        )?,
        "test" => {
            fs::create_dir_all(root.join("build"))?;
            let target = root.join("build/launcher-checks");
            native(root, true, &target)?;
            execute(&mut Command::new(target))?;
        }
        "dmg" => {
            let app = input
                .unwrap_or(root.join(format!("build/packaged/{NAME}.app")))
                .canonicalize()?;
            verify(&app)?;
            let output = output.unwrap_or(root.join("build/Minecraft-Launcher-preview.dmg"));
            ensure!(
                !output.exists() && !output.is_symlink(),
                "Disk image already exists"
            );
            fs::create_dir_all(output.parent().context("Missing disk image parent")?)?;
            let stage =
                tempfile::tempdir_in(output.parent().context("Missing disk image parent")?)?;
            let folder = stage.path().join("Install");
            fs::create_dir(&folder)?;
            copy(
                &app,
                &folder.join(app.file_name().context("Missing app name")?),
            )?;
            symlink("/Applications", folder.join("Applications"))?;
            execute(
                Command::new("hdiutil")
                    .arg("create")
                    .arg("-srcfolder")
                    .arg(folder)
                    .args(["-volname", NAME, "-format", "ULFO"])
                    .arg(&output),
            )?;
            execute(Command::new("hdiutil").arg("verify").arg(output))?;
        }
        "--help" | "-h" => println!(
            "build launcher|test\nbuild app|preview [--output PATH] [--runtime-bundle APP/Contents/Resources]\nbuild verify [--app PATH]\nbuild dmg [--app PATH] [--output PATH]"
        ),
        _ => bail!("Unknown build command"),
    }
    Ok(())
}
