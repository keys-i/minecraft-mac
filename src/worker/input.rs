use crate::{atomic_bytes, digest, hex};
use anyhow::{Context, Result, ensure};
use regex::Regex;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const MSI: &str = "4e325dbc8a6853ea7786504f6f326bee37a085b799d262a5ec296df95cc8601a";
const CAB: &str = "e1ef9aaf57b36bd75c75416772026835842353b764926ccf6242cf6a1cd676af";
const REDIST: &str = r"C:\Program Files\Microsoft GameInput\x64";
const FILES: [(&str, usize, &str, bool); 4] = [
    (
        "GameInputRedist.dll",
        895376,
        "ea6816937030fcf232de5c29628a0140d0643f81939b5ac47fb2a1f4bfaa374d",
        true,
    ),
    (
        "GameInputRedistService.exe",
        137616,
        "3959900e8a57e368e86f0b9d63585bc721d71ee78fba30086f224fc9981244c2",
        false,
    ),
    (
        "GameInputBridge.dll",
        80272,
        "00a5255333be1db3006485f5a5c6a9e1e42ccdb1d7ba35d05aeafedc9f1bc5c5",
        true,
    ),
    (
        "GameInputRawInputProxy.exe",
        80272,
        "76638d16c9bbd6c87b4b64bdbbcce166b2f83f261fc756ec6714a5a5f667dd81",
        false,
    ),
];

fn pe(data: &[u8], dll: bool) -> bool {
    if data.len() < 64 || !data.starts_with(b"MZ") {
        return false;
    }
    let offset = u32::from_le_bytes(data[60..64].try_into().expect("four bytes")) as usize;
    data.get(offset..offset + 6) == Some(b"PE\0\0\x64\x86")
        && data
            .get(offset + 22..offset + 24)
            .is_some_and(|flags| (u16::from_le_bytes([flags[0], flags[1]]) & 0x2000 != 0) == dll)
}

pub fn payload(msi: &Path) -> Result<BTreeMap<String, Vec<u8>>> {
    ensure!(
        fs::metadata(msi)?.len() <= 16 * 1024 * 1024 && digest(msi)? == MSI,
        "Unrecognised GameInput MSI; existing files were preserved"
    );
    let mut compound = cfb::open(msi)?;
    let streams: Vec<_> = compound
        .walk()
        .filter(|entry| entry.is_stream() && entry.len() >= 4 && entry.len() <= 16 * 1024 * 1024)
        .map(|entry| entry.path().to_path_buf())
        .collect();
    let mut cabinet = None;
    for path in streams {
        let mut stream = compound.open_stream(path)?;
        let mut magic = [0; 4];
        stream.read_exact(&mut magic)?;
        if magic != *b"MSCF" {
            continue;
        }
        let mut bytes = magic.to_vec();
        stream.take(16 * 1024 * 1024 + 1).read_to_end(&mut bytes)?;
        ensure!(
            bytes.len() <= 16 * 1024 * 1024 && hex(&Sha256::digest(&bytes)) == CAB,
            "GameInput CAB does not match the pinned Microsoft payload"
        );
        cabinet = Some(bytes);
        break;
    }
    let mut cabinet = cab::Cabinet::new(Cursor::new(
        cabinet.context("The GameInput cabinet is missing")?,
    ))?;
    let names: Vec<_> = cabinet
        .folder_entries()
        .flat_map(|folder| folder.file_entries())
        .map(|file| file.name().to_owned())
        .collect();
    ensure!(
        names.len() <= 256,
        "The GameInput cabinet has too many files"
    );
    let mut selected = BTreeMap::new();
    for name in names {
        let mut bytes = Vec::new();
        cabinet
            .read_file(&name)?
            .take(8 * 1024 * 1024 + 1)
            .read_to_end(&mut bytes)?;
        ensure!(
            bytes.len() <= 8 * 1024 * 1024,
            "The GameInput cabinet entry is larger than expected"
        );
        let checksum = hex(&Sha256::digest(&bytes));
        if let Some(&(name, size, _, dll)) = FILES.iter().find(|entry| entry.2 == checksum) {
            ensure!(
                bytes.len() == size && pe(&bytes, dll) && !selected.contains_key(name),
                "The native GameInput payload has an invalid PE image or size"
            );
            selected.insert(name.into(), bytes);
        }
    }
    ensure!(
        selected.len() == FILES.len(),
        "The pinned MSI is missing an expected native GameInput file"
    );
    Ok(selected)
}

pub fn validate(prefix: &Path, root: &Path) -> Result<()> {
    ensure!(
        !prefix.is_symlink()
            && !prefix.join("cxbottle.conf").exists()
            && prefix.canonicalize()? != root.join("bottles/Bedrock-Mac"),
        "Refusing to change the existing CrossOver prefix or a symbolic-link prefix"
    );
    let canonical = prefix.canonicalize()?;
    for relative in ["system.reg", "user.reg", "drive_c/windows/system32"] {
        ensure!(
            prefix
                .join(relative)
                .canonicalize()?
                .starts_with(&canonical),
            "Initialise the separate Wine prefix before installing GameInput"
        );
    }
    Ok(())
}

fn directory(prefix: &Path) -> PathBuf {
    prefix.join("drive_c/Program Files/Microsoft GameInput/x64")
}

#[derive(Clone, Debug, PartialEq)]
enum Value {
    Text(String),
    Number(u32),
    Expand(String),
}

fn registry() -> Vec<(String, Vec<(&'static str, Value)>)> {
    vec![
        (
            r"Software\Microsoft\GameInput".into(),
            vec![("RedistDir", Value::Text(REDIST.into()))],
        ),
        (
            r"Software\Wow6432Node\Microsoft\GameInput".into(),
            vec![("RedistDir", Value::Text(REDIST.into()))],
        ),
        (
            r"System\CurrentControlSet\Services\GameInputRedistService".into(),
            vec![
                (
                    "DisplayName",
                    Value::Text("GameInput Redist Service".into()),
                ),
                (
                    "Description",
                    Value::Text("GameInput Redist Service".into()),
                ),
                (
                    "ImagePath",
                    Value::Expand(format!(r"{REDIST}\GameInputRedistService.exe")),
                ),
                ("ObjectName", Value::Text("LocalSystem".into())),
                ("ErrorControl", Value::Number(0)),
                ("Start", Value::Number(3)),
                ("Type", Value::Number(0x10)),
                ("PreshutdownTimeout", Value::Number(180000)),
            ],
        ),
    ]
}

fn registry_text() -> String {
    let mut text = String::from("Windows Registry Editor Version 5.00\n\n");
    for (section, entries) in registry() {
        text.push_str(&format!("[HKEY_LOCAL_MACHINE\\{section}]\n"));
        for (key, value) in entries {
            let value = match value {
                Value::Number(value) => format!("dword:{value:08x}"),
                Value::Text(value) => {
                    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
                }
                Value::Expand(value) => {
                    "hex(2):".to_owned()
                        + &value
                            .encode_utf16()
                            .chain([0])
                            .flat_map(u16::to_le_bytes)
                            .map(|byte| format!("{byte:02x}"))
                            .collect::<Vec<_>>()
                            .join(",")
                }
            };
            text.push_str(&format!("\"{key}\"={value}\n"));
        }
        text.push('\n');
    }
    text
}

pub fn valid(prefix: &Path) -> Result<bool> {
    let canonical = prefix.canonicalize()?;
    let native = directory(prefix);
    if !native.is_dir() || !native.canonicalize()?.starts_with(canonical) {
        return Ok(false);
    }
    for (name, _, checksum, _) in FILES {
        let path = native.join(name);
        if path.is_symlink() || !path.is_file() || digest(&path)? != checksum {
            return Ok(false);
        }
    }
    let raw = fs::read_to_string(prefix.join("system.reg"))?;
    let pattern = Regex::new(r#"^"((?:\\.|[^"\\])*)"=(.*)$"#)?;
    let escapes = Regex::new(r"\\(.)")?;
    let mut sections: BTreeMap<String, BTreeMap<String, Value>> = BTreeMap::new();
    let mut current = String::new();
    for line in raw.lines() {
        if let Some(section) = line
            .strip_prefix('[')
            .and_then(|line| line.split_once(']'))
            .map(|pair| pair.0)
        {
            current = section.replace("\\\\", "\\").to_lowercase();
            sections.entry(current.clone()).or_default();
        } else if let Some(capture) = pattern.captures(line) {
            let raw = &capture[2];
            let value = if let Some(number) = raw.strip_prefix("dword:") {
                Value::Number(u32::from_str_radix(number, 16)?)
            } else {
                let raw = raw.strip_prefix("str(2):").unwrap_or(raw);
                Value::Text(
                    escapes
                        .replace_all(raw.trim_matches('"'), "$1")
                        .into_owned(),
                )
            };
            sections
                .entry(current.clone())
                .or_default()
                .insert(capture[1].to_lowercase(), value);
        }
    }
    let active = match sections
        .get(r"system\select")
        .and_then(|section| section.get("current"))
    {
        Some(Value::Number(value)) => *value,
        _ => 1,
    };
    for (section, entries) in registry() {
        let section = section.to_lowercase();
        let canonical =
            section.replace(r"\currentcontrolset\", &format!(r"\controlset{active:03}\"));
        let values = sections.get(&section).or_else(|| sections.get(&canonical));
        for (key, value) in entries {
            let expected = match value {
                Value::Expand(value) => Value::Text(value),
                value => value,
            };
            if values.and_then(|values| values.get(&key.to_lowercase())) != Some(&expected) {
                return Ok(false);
            }
        }
    }
    Ok(true)
}

pub fn install(prefix: &Path, msi: &Path, root: &Path) -> Result<()> {
    validate(prefix, root)?;
    let selected = payload(msi)?;
    let mut watcher = Command::new(root.join("runtime/standalone/wine/bin/wineserver"));
    watcher
        .env_clear()
        .envs(std::env::vars_os().filter(|(key, _)| {
            !["CX_", "WINE", "DYLD_"]
                .iter()
                .any(|prefix| key.to_string_lossy().starts_with(prefix))
        }))
        .env("WINEPREFIX", prefix)
        .env("WINEARCH", "win64")
        .arg("-w")
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut watcher = watcher.spawn()?;
    let deadline = Instant::now() + Duration::from_secs(1);
    loop {
        if let Some(status) = watcher.try_wait()? {
            ensure!(status.success(), "The Wine prefix could not be checked");
            break;
        }
        if Instant::now() >= deadline {
            watcher.kill()?;
            watcher.wait()?;
            anyhow::bail!("The selected standalone prefix is busy; no files changed");
        }
        std::thread::sleep(Duration::from_millis(25));
    }
    let native = directory(prefix);
    for ancestor in native.ancestors().take_while(|path| *path != prefix) {
        ensure!(
            !ancestor.is_symlink(),
            "GameInput destination contains a symbolic link; no files changed"
        );
    }
    for (name, data) in &selected {
        let path = native.join(name);
        ensure!(
            !path.is_symlink() && (!path.exists() || fs::read(&path)? == *data),
            "Existing GameInput file differs from this Microsoft package; it was preserved: {name}"
        );
    }
    fs::create_dir_all(&native)?;
    for (name, data) in &selected {
        let path = native.join(name);
        if !path.exists() {
            atomic_bytes(&path, data)?;
        }
    }
    let bytes = std::iter::once(0xfeff_u16)
        .chain(registry_text().encode_utf16())
        .flat_map(u16::to_le_bytes)
        .collect::<Vec<_>>();
    atomic_bytes(&prefix.join(".standalone-gameinput.reg"), &bytes)?;
    Ok(())
}

pub fn run(args: Vec<OsString>) -> Result<()> {
    let mut paths = BTreeMap::new();
    let (mut check, mut verify) = (false, false);
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("--check") => check = true,
            Some("--verify-payload") => verify = true,
            Some("--root" | "--prefix" | "--msi") => {
                let value = args.next().context("Missing GameInput path")?;
                ensure!(
                    paths.insert(arg, PathBuf::from(value)).is_none(),
                    "Repeated GameInput argument"
                );
            }
            _ => anyhow::bail!("Unknown GameInput argument"),
        }
    }
    let root = paths
        .remove(&OsString::from("--root"))
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")));
    let msi = paths
        .remove(&OsString::from("--msi"))
        .context("Supply --msi")?;
    if verify {
        let files = payload(&msi)?
            .into_iter()
            .map(|(name, data)| (name, hex(&Sha256::digest(data))))
            .collect::<BTreeMap<_, _>>();
        println!("{}", serde_json::json!({"msi_sha256":MSI,"files":files}));
        return Ok(());
    }
    let prefix = paths
        .remove(&OsString::from("--prefix"))
        .context("Supply --prefix")?;
    validate(&prefix, &root)?;
    if check {
        payload(&msi)?;
        ensure!(
            valid(&prefix)?,
            "The installed GameInput files or registry need repair"
        );
    } else {
        install(&prefix, &msi, &root)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn registry_preserves_service_types_and_utf16_expansion() {
        let text = registry_text();
        assert!(text.contains("\"Start\"=dword:00000003"));
        assert!(text.contains("\"ImagePath\"=hex(2):43,00,3a,00,5c,00"));
        assert!(text.contains("\"ObjectName\"=\"LocalSystem\""));
    }
    #[test]
    fn rejects_truncated_and_wrong_architecture_payloads() {
        for bytes in [Vec::new(), b"MZ".to_vec(), vec![0; 128]] {
            assert!(!pe(&bytes, true));
        }
        let mut bytes = vec![0; 128];
        bytes[..2].copy_from_slice(b"MZ");
        bytes[60..64].copy_from_slice(&64_u32.to_le_bytes());
        bytes[64..70].copy_from_slice(b"PE\0\0\x64\x86");
        bytes[86..88].copy_from_slice(&0x2000_u16.to_le_bytes());
        assert!(pe(&bytes, true));
        assert!(!pe(&bytes, false));
    }
}
