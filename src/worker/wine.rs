use crate::{atomic, atomic_bytes, cli, digest, source};
use anyhow::{Context, Result, bail, ensure};
use serde_json::json;
use std::collections::BTreeSet;
use std::fs;
use std::io::Read;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::Path;
use std::process::{Command, Stdio};

fn dependencies(archive: &Path, destination: &Path, spare: &Path) -> Result<()> {
    ensure!(
        digest(archive)? == "5c9f0984961ee6289f4f2c4fe751c27f02b6c28855154e3f99b7e2bd8108b620",
        "Wine dependency archive failed verification"
    );
    let mut child = Command::new("xz")
        .arg("-dc")
        .arg(archive)
        .stdout(Stdio::piped())
        .spawn()?;
    let result = (|| -> Result<()> {
        let mut archive = tar::Archive::new(child.stdout.take().context("Missing xz output")?);
        for entry in archive.entries()? {
            let mut entry = entry?;
            let name = entry.path()?.to_string_lossy().into_owned();
            if !name.starts_with("Wine Devel.app/Contents/Resources/wine/lib/")
                || name.matches('/').count() != 5
                || !name.ends_with(".dylib")
            {
                continue;
            }
            let output = destination.join(
                Path::new(&name)
                    .file_name()
                    .context("Missing dependency filename")?,
            );
            if entry.header().entry_type().is_symlink() {
                let link = entry.link_name()?.context("Missing dependency link")?;
                ensure!(
                    link.file_name().is_some_and(|name| Path::new(name) == link),
                    "Unsafe portable dependency link"
                );
                if !output.exists() && !output.is_symlink() {
                    symlink(link, &output)?;
                }
            } else {
                ensure!(
                    entry.header().entry_type().is_file() && entry.size() <= 128 * 1024 * 1024,
                    "Invalid portable dependency"
                );
                let mode = entry.header().mode()?;
                let mut bytes = Vec::new();
                entry.read_to_end(&mut bytes)?;
                crate::atomic_bytes(&output, &bytes)?;
                fs::set_permissions(&output, fs::Permissions::from_mode(mode))?;
            }
        }
        ensure!(
            child.wait()?.success(),
            "Wine dependency decompression failed"
        );
        Ok(())
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    result?;
    let mut needed = BTreeSet::new();
    let mut pending: Vec<String> = [
        "libgnutls.30.dylib",
        "libfreetype.6.dylib",
        "libgnutls.dylib",
        "libfreetype.dylib",
    ]
    .map(str::to_owned)
    .into();
    while let Some(name) = pending.pop() {
        if !needed.insert(name.clone()) {
            continue;
        }
        let library = destination.join(name);
        if library.is_symlink() {
            pending.push(
                fs::read_link(&library)?
                    .file_name()
                    .context("Missing dependency link name")?
                    .to_string_lossy()
                    .into_owned(),
            );
        }
        let output = Command::new("/usr/bin/otool")
            .arg("-L")
            .arg(library)
            .output()?;
        ensure!(
            output.status.success(),
            "Couldn’t inspect portable dependency"
        );
        for line in String::from_utf8_lossy(&output.stdout).lines().skip(2) {
            let dependency = line
                .trim()
                .split(" (")
                .next()
                .context("Missing dependency")?;
            if dependency.starts_with("@loader_path/") || dependency.starts_with("@rpath/") {
                pending.push(
                    Path::new(dependency)
                        .file_name()
                        .context("Missing dependency name")?
                        .to_string_lossy()
                        .into_owned(),
                );
            } else {
                ensure!(
                    dependency.starts_with("/System/") || dependency.starts_with("/usr/lib/"),
                    "Unexpected portable dependency: {dependency}"
                );
            }
        }
    }
    fs::create_dir_all(spare)?;
    for entry in fs::read_dir(destination)? {
        let entry = entry?;
        let path = entry.path();
        if path
            .extension()
            .is_some_and(|extension| extension == "dylib")
            && !needed.contains(entry.file_name().to_string_lossy().as_ref())
        {
            let to = spare.join(entry.file_name());
            if to.exists() || to.is_symlink() {
                fs::remove_file(&to)?;
            }
            fs::rename(path, to)?;
        }
    }
    Ok(())
}

fn manifest(root: &Path, prefix: &Path, tree: &Path) -> Result<()> {
    let mut patches = serde_json::Map::new();
    for entry in fs::read_dir(root.join("vendor/patches"))? {
        let path = entry?.path();
        let name = path
            .file_name()
            .context("Missing patch name")?
            .to_string_lossy();
        if name.starts_with("standalone-wine") && name.ends_with(".patch") {
            patches.insert(name.into_owned(), digest(&path)?.into());
        }
    }
    let libraries: Vec<_> = fs::read_dir(prefix.join("lib"))?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.ends_with(".dylib"))
        .collect();
    let version = Command::new(prefix.join("bin/wine"))
        .arg("--version")
        .output()?;
    ensure!(version.status.success(), "Couldn’t read built Wine version");
    atomic(
        &prefix.join("build-manifest.json"),
        &json!({"wine_source_repository":"https://github.com/Sightem/WineGDK","wine_source_revision":String::from_utf8(source::git(tree,&["rev-parse","HEAD"])?)?.trim(),"wine_version":String::from_utf8_lossy(&version.stdout).trim(),"architecture":"x86_64","dependency_archive":{"url":"https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.8/wine-devel-11.8-osx64.tar.xz","sha256":"5c9f0984961ee6289f4f2c4fe751c27f02b6c28855154e3f99b7e2bd8108b620","extracted":"GnuTLS/FreeType dylibs and transitive dependencies; Wine compiled locally"},"patches":patches,"required_portable_libraries":libraries,"capabilities":{"win64":true,"win32":false,"macdriver":true,"coreaudio":true,"gnutls":true,"freetype":true,"gstreamer":false,"vulkan":false},"graphics":"Run ./minecraft graphics acquire --wine-runtime with this prefix after rebuilding Wine; validate graphics before gameplay"}),
    )
}

pub fn run(root: &Path, mut args: Vec<String>) -> Result<()> {
    let command = cli::command(
        &mut args,
        "wine dependencies ARCHIVE DESTINATION SPARE | wine manifest PREFIX SOURCE",
    )?;
    match command.as_str() {
        "layout" => {
            ensure!(
                args.len() == 2,
                "Choose the Wine build and probe directories"
            );
            let text = fs::read_to_string(
                Path::new(&args[0]).join("source/dlls/xgameruntime/GDKComponent/System/XUser.c"),
            )?;
            let start = text
                .find("struct XUser\n{")
                .context("Missing XUser layout")?;
            let tail = &text[start..];
            let marker = "    HRESULT xboxPolicyRefreshError;";
            let end = tail.find(marker).context("Missing XUser refresh field")? + marker.len();
            let layout = tail[..end]
                .replacen("struct XUser\n", "struct XUserTestState\n", 1)
                .replace("    IUser IUser_iface;", "    void *IUser_iface;");
            atomic_bytes(
                &Path::new(&args[1]).join("XUserTestState.h"),
                format!("{layout}\n}};\n").as_bytes(),
            )
        }
        "dependencies" => {
            ensure!(
                args.len() == 3,
                "Choose archive, destination and spare directories"
            );
            dependencies(
                Path::new(&args[0]),
                Path::new(&args[1]),
                Path::new(&args[2]),
            )
        }
        "manifest" => {
            ensure!(args.len() == 2, "Choose prefix and source tree");
            manifest(root, Path::new(&args[0]), Path::new(&args[1]))
        }
        "--help" | "-h" => {
            println!("wine dependencies ARCHIVE DESTINATION SPARE\nwine manifest PREFIX SOURCE");
            Ok(())
        }
        _ => bail!("Unknown Wine build command"),
    }
}
