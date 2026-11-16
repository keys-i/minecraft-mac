use crate::{atomic_bytes, hex};
use anyhow::{Context, Result, bail, ensure};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::ffi::{CString, OsStr};
use std::fs::{self, File};
use std::io::Read;
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path};
use std::process::Command;

const INVENTORY: &str = "tools/SOURCE-SHA256.txt";
pub const PROJECTS: &[(&str, &str, &str, &[&str])] = &[
    (
        "leveldb",
        "https://github.com/Mojang/leveldb.git",
        "3791effb6692e0c83da782210aa336a3dd436f30",
        &["leveldb-zlib.patch"],
    ),
    (
        "xodus",
        "https://github.com/xodus-gaming/xodus.git",
        "0670e25aeb0e0e9f800f8f2f4968ae3b681842a7",
        &[
            "xodus-real-store-license.patch",
            "keychain-cache.patch",
            "unified-helper.patch",
            "standalone-signin-window.patch",
            "standalone-keychain-write.patch",
        ],
    ),
    (
        "winegdk",
        "https://github.com/Sightem/WineGDK.git",
        "b5d23b074cfd5e28e79acceaaefaf41a26ce6272",
        &[
            "winegdk-macos-local.patch",
            "minecraft-store-callback.patch",
        ],
    ),
    (
        "dxmt",
        "https://github.com/3Shain/dxmt.git",
        "589adb780354b461645b29999cefaf533594ee99",
        &[],
    ),
];

pub fn relative(name: &str) -> Result<&Path> {
    let path = Path::new(name);
    let forbidden = [
        "sources",
        "downloads",
        "runtime",
        "logs",
        "bottles",
        "build",
        "game",
        ".git",
        "__pycache__",
        "exports",
        "work",
        "outputs",
        "target",
    ];
    ensure!(
        !name.is_empty()
            && !name.contains(['\\', '\n', '\r', '\0'])
            && path
                .components()
                .all(|part| matches!(part, Component::Normal(_)))
            && path
                .components()
                .map(|part| part.as_os_str())
                .collect::<Vec<_>>()
                .join(OsStr::new("/"))
                == name
            && !forbidden.iter().any(|root| path.starts_with(root)),
        "Unsafe source path: {name}"
    );
    Ok(path)
}

pub fn read(root: &Path, name: &str) -> Result<(Vec<u8>, u32)> {
    let path = relative(name)?;
    let mut directory = fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_DIRECTORY)
        .open(root)?;
    let parts: Vec<_> = path.components().collect();
    for (index, part) in parts.iter().enumerate() {
        use std::os::unix::ffi::OsStrExt;
        let part = CString::new(part.as_os_str().as_bytes())?;
        let flags = libc::O_RDONLY
            | libc::O_NONBLOCK
            | libc::O_NOFOLLOW
            | libc::O_CLOEXEC
            | if index + 1 == parts.len() {
                0
            } else {
                libc::O_DIRECTORY
            };
        // Each opened parent stays owned until openat has resolved its child
        let fd = unsafe { libc::openat(directory.as_raw_fd(), part.as_ptr(), flags) };
        ensure!(
            fd >= 0,
            "Couldn’t safely open {name}: {}",
            std::io::Error::last_os_error()
        );
        // openat returned a fresh descriptor owned by this File
        directory = unsafe { File::from_raw_fd(fd) };
    }
    let info = directory.metadata()?;
    ensure!(
        info.is_file() && info.len() <= 16 * 1024 * 1024,
        "Missing or oversized regular source: {name}"
    );
    let mut bytes = Vec::new();
    directory
        .take(16 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    ensure!(
        bytes.len() <= 16 * 1024 * 1024,
        "Source grew while reading: {name}"
    );
    validate(name, &bytes)?;
    Ok((
        bytes,
        if info.permissions().mode() & 0o111 != 0 {
            0o755
        } else {
            0o644
        },
    ))
}

fn validate(name: &str, bytes: &[u8]) -> Result<()> {
    if name.ends_with(".ttf") {
        ensure!(
            bytes.len() <= 2 * 1024 * 1024 && bytes.len() >= 12 && bytes[..4] == [0, 1, 0, 0],
            "Invalid TrueType source"
        );
        let count = u16::from_be_bytes(bytes[4..6].try_into()?) as usize;
        ensure!(
            (1..=128).contains(&count) && 12 + count * 16 <= bytes.len(),
            "Invalid font directory"
        );
        for entry in bytes[12..12 + count * 16].chunks_exact(16) {
            let offset = u32::from_be_bytes(entry[8..12].try_into()?) as usize;
            let length = u32::from_be_bytes(entry[12..16].try_into()?) as usize;
            ensure!(
                offset >= 12 + count * 16
                    && offset
                        .checked_add(length)
                        .is_some_and(|end| end <= bytes.len()),
                "Invalid font table"
            );
        }
    } else if name.ends_with(".jpg") || name.ends_with(".webp") {
        let jpeg = name.ends_with(".jpg")
            && bytes.starts_with(&[255, 216, 255])
            && bytes.ends_with(&[255, 217]);
        let webp = name.ends_with(".webp")
            && bytes.len() >= 16
            && &bytes[..4] == b"RIFF"
            && &bytes[8..12] == b"WEBP"
            && [b"VP8 ", b"VP8L", b"VP8X"]
                .iter()
                .any(|magic| bytes[12..16] == **magic)
            && u32::from_le_bytes(bytes[4..8].try_into()?) as usize == bytes.len() - 8;
        ensure!(
            bytes.len() <= 2 * 1024 * 1024 && (jpeg || webp),
            "Invalid source image: {name}"
        );
    } else {
        std::str::from_utf8(bytes).context("Source is not UTF-8")?;
        ensure!(!bytes.contains(&0), "Source contains binary data: {name}");
    }
    Ok(())
}

pub fn inventory(root: &Path) -> Result<String> {
    let mut seen = BTreeSet::new();
    let mut lines = String::new();
    for name in include_str!("../../tools/sources.txt").lines() {
        ensure!(seen.insert(name), "Duplicate source entry: {name}");
        let (bytes, _) = read(root, name)?;
        lines.push_str(&format!("{}  {name}\n", hex(&Sha256::digest(&bytes))));
    }
    Ok(lines)
}

pub fn exclusive(source: &Path, destination: &Path) -> Result<()> {
    use std::os::unix::ffi::OsStrExt;
    let from = CString::new(source.as_os_str().as_bytes())?;
    let to = CString::new(destination.as_os_str().as_bytes())?;
    // Both names are NUL-free and remain alive during the atomic no-replace rename
    #[cfg(target_os = "macos")]
    let result = unsafe {
        libc::renameatx_np(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_EXCL,
        )
    };
    #[cfg(target_os = "linux")]
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    ensure!(
        result == 0,
        "Couldn’t publish destination: {}",
        std::io::Error::last_os_error()
    );
    Ok(())
}

pub fn git(directory: &Path, args: &[&str]) -> Result<Vec<u8>> {
    let output = Command::new("git")
        .args(args)
        .current_dir(directory)
        .output()?;
    ensure!(
        output.status.success(),
        "Git {} failed: {}",
        args.first().unwrap_or(&""),
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(output.stdout)
}

fn apply(root: &Path, directory: &Path, name: &str, patches: &[&str]) -> Result<()> {
    for patch in patches {
        let file = root.join("vendor/patches").join(patch);
        let file = file.to_str().context("Non-UTF-8 patch path")?;
        git(directory, &["apply", "--check", file])?;
        git(directory, &["apply", file])?;
    }
    if name == "xodus" {
        fs::copy(
            root.join("vendor/patches/Cargo.lock"),
            directory.join("Cargo.lock"),
        )?;
    }
    Ok(())
}

pub fn project(root: &Path, destination: &Path, name: &str, fetch: bool) -> Result<()> {
    let (_, url, commit, patches) = PROJECTS
        .iter()
        .find(|item| item.0 == name)
        .context("Unknown source project")?;
    ensure!(
        !destination.is_symlink(),
        "Source destination is a symbolic link"
    );
    let target = destination.join(name);
    ensure!(!target.is_symlink(), "Source checkout is a symbolic link");
    if fetch {
        ensure!(
            !target.exists(),
            "{} already exists; verify it instead",
            target.display()
        );
        fs::create_dir_all(destination)?;
        let stage = tempfile::Builder::new()
            .prefix(".source-")
            .tempdir_in(destination)?;
        git(stage.path(), &["init", "--quiet"])?;
        git(stage.path(), &["remote", "add", "origin", url])?;
        git(stage.path(), &["fetch", "--depth", "1", "origin", commit])?;
        git(
            stage.path(),
            &["checkout", "--quiet", "--detach", "FETCH_HEAD"],
        )?;
        ensure!(
            String::from_utf8(git(stage.path(), &["rev-parse", "HEAD"])?)?.trim() == *commit,
            "Unexpected upstream revision"
        );
        apply(root, stage.path(), name, patches)?;
        exclusive(stage.path(), &target)?;
    } else {
        ensure!(
            String::from_utf8(git(&target, &["rev-parse", "HEAD"])?)?.trim() == *commit,
            "{name} is not at the pinned revision"
        );
        let mut paths = BTreeSet::new();
        for patch in *patches {
            for line in fs::read_to_string(root.join("vendor/patches").join(patch))?.lines() {
                if let Some(path) = line
                    .strip_prefix("--- a/")
                    .or_else(|| line.strip_prefix("+++ b/"))
                {
                    let path = path.split('\t').next().context("Missing patch path")?;
                    relative(path)?;
                    paths.insert(path.to_owned());
                }
            }
        }
        let stage = tempfile::tempdir()?;
        for path in &paths {
            let spec = format!("{commit}:{path}");
            if git(&target, &["cat-file", "-e", &spec]).is_ok() {
                let output = stage.path().join(path);
                fs::create_dir_all(output.parent().context("Missing patch directory")?)?;
                fs::write(output, git(&target, &["show", &spec])?)?;
            }
        }
        apply(root, stage.path(), name, patches)?;
        if name == "xodus" {
            paths.insert("Cargo.lock".into());
        }
        for path in &paths {
            let (bytes, _) = read(&target, path)?;
            ensure!(
                bytes == fs::read(stage.path().join(path))?,
                "Patched source differs: {name}/{path}"
            );
        }
    }
    println!(
        "{} {name} at {commit}",
        if fetch { "Prepared" } else { "Verified" }
    );
    Ok(())
}

pub fn run(root: &Path, mut args: Vec<String>) -> Result<()> {
    let command =
        crate::cli::command(&mut args, "source fetch|verify|export|inventory|check|list")?;
    match command.as_str() {
        "list" => {
            ensure!(args.is_empty(), "Unexpected source arguments");
            print!("{}", include_str!("../../tools/sources.txt"));
        }
        "fetch" | "verify" => {
            let project_name = crate::cli::option(&mut args, "--project")?.unwrap_or("all".into());
            let destination = crate::cli::option(&mut args, "--destination")?
                .map(std::path::PathBuf::from)
                .unwrap_or(root.join("sources"));
            ensure!(args.is_empty(), "Unexpected source arguments");
            for &(name, _, _, _) in PROJECTS {
                if project_name == "all" || project_name == name {
                    project(root, &destination, name, command == "fetch")?;
                }
            }
            ensure!(
                project_name == "all" || PROJECTS.iter().any(|item| item.0 == project_name),
                "Unknown project"
            );
        }
        "inventory" | "check" => {
            ensure!(args.is_empty(), "Unexpected source arguments");
            let expected = inventory(root)?;
            if command == "inventory" {
                atomic_bytes(&root.join(INVENTORY), expected.as_bytes())?;
            } else {
                ensure!(
                    fs::read_to_string(root.join(INVENTORY))? == expected,
                    "Source inventory is stale; run ./minecraft source inventory"
                );
            }
            println!("Verified {} reviewed files", expected.lines().count());
        }
        "export" => {
            ensure!(args.len() == 1, "Choose one new export directory");
            let destination = std::path::absolute(&args[0])?;
            let parent = destination
                .parent()
                .context("Missing export parent")?
                .canonicalize()?;
            ensure!(
                !destination.exists() && !destination.is_symlink(),
                "Export destination already exists"
            );
            let expected = inventory(root)?;
            let stage = tempfile::Builder::new()
                .prefix(".source-")
                .tempdir_in(parent)?;
            for name in include_str!("../../tools/sources.txt").lines() {
                let (bytes, mode) = read(root, name)?;
                let target = stage.path().join(name);
                fs::create_dir_all(target.parent().context("Missing source parent")?)?;
                fs::write(&target, bytes)?;
                fs::set_permissions(target, fs::Permissions::from_mode(mode))?;
            }
            fs::write(stage.path().join(INVENTORY), expected)?;
            exclusive(stage.path(), &destination)?;
            println!("Exported reviewed source to {}", destination.display());
        }
        "--help" | "-h" => println!(
            "source fetch|verify [--project all|xodus|winegdk|dxmt|leveldb] [--destination PATH]\nsource export PATH\nsource inventory|check|list"
        ),
        _ => bail!("Unknown source command"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn source_boundaries() -> Result<()> {
        for path in [
            "../secret",
            "game/data",
            "/tmp/file",
            "a//b",
            "a/./b",
            "a\\b",
            "",
        ] {
            assert!(relative(path).is_err(), "{path}");
        }
        let root = tempfile::tempdir()?;
        fs::create_dir(root.path().join("docs"))?;
        fs::write(root.path().join("docs/test.md"), b"safe")?;
        assert_eq!(read(root.path(), "docs/test.md")?.0, b"safe");
        std::os::unix::fs::symlink("docs", root.path().join("link"))?;
        assert!(read(root.path(), "link/test.md").is_err());
        std::os::unix::fs::symlink("test.md", root.path().join("docs/alias.md"))?;
        assert!(read(root.path(), "docs/alias.md").is_err());
        assert!(validate("x.md", b"secret\0binary").is_err());
        Ok(())
    }
    #[test]
    fn export_never_merges() -> Result<()> {
        let root = tempfile::tempdir()?;
        let a = root.path().join("a");
        let b = root.path().join("b");
        fs::create_dir(&a)?;
        fs::create_dir(&b)?;
        fs::write(b.join("world"), b"preserve")?;
        assert!(exclusive(&a, &b).is_err());
        assert_eq!(fs::read(b.join("world"))?, b"preserve");
        Ok(())
    }
}
