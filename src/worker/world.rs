use crate::{atomic, digest, event, hex, read_json};
use anyhow::{Context, Result, ensure};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::{
    fs::{OpenOptionsExt, PermissionsExt, symlink},
    process::CommandExt,
};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::{Duration, Instant};

const VERSION: &str = "1.26.52.3";
const ARCHIVE: &str = "2c9b98d07d2504786996f2335980e88bd969b4a77514925e75471a1349995825";
const EXECUTABLE: &str = "19c88569af2e4b7d984e999055a31cbcb0799dacf8bbbf7371eda42f5772a443";
const DIMENSIONS: [&str; 3] = ["overworld", "nether", "the_end"];

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    seed: String,
    dimension: u8,
    chunks: Vec<[i32; 2]>,
    #[serde(default)]
    locate: Vec<Locator>,
}

#[derive(Deserialize)]
struct Locator {
    kind: String,
    id: String,
}

#[derive(Deserialize, Serialize)]
struct Destination {
    id: String,
    x: i32,
    y: Option<i32>,
    z: i32,
    dimension: u8,
}

#[derive(Deserialize, Serialize)]
struct Manifest {
    version: String,
    seed: String,
    chunks: BTreeSet<(u8, i32, i32)>,
    destinations: Vec<Destination>,
}

struct Paths {
    root: PathBuf,
    wine: PathBuf,
    network: PathBuf,
    request: PathBuf,
}

impl Paths {
    fn parse(args: Vec<OsString>) -> Result<Self> {
        ensure!(
            args.len() == 8,
            "Supply the scenery request and runtime paths"
        );
        let mut values = BTreeMap::new();
        for pair in args.chunks_exact(2) {
            let key = pair[0].to_str().context("Invalid scenery argument")?;
            ensure!(
                ["--root", "--wine", "--network", "--request"].contains(&key)
                    && values.insert(key, PathBuf::from(&pair[1])).is_none(),
                "Invalid scenery argument"
            );
        }
        Ok(Self {
            root: values
                .remove("--root")
                .context("Missing scenery root")?
                .canonicalize()?,
            wine: values
                .remove("--wine")
                .context("Missing scenery runtime")?
                .canonicalize()?,
            network: values
                .remove("--network")
                .context("Missing scenery network guard")?
                .canonicalize()?,
            request: values
                .remove("--request")
                .context("Missing scenery request")?,
        })
    }
}

impl Request {
    fn validate(&mut self) -> Result<()> {
        ensure!(
            !self.seed.is_empty()
                && self.seed.len() <= 256
                && !self.seed.chars().any(char::is_control),
            "Choose a seed without control characters, up to 256 bytes long"
        );
        ensure!(
            self.dimension < 3
                && self.chunks.len() <= 1089
                && self.locate.len() <= 64
                && (!self.chunks.is_empty() || !self.locate.is_empty()),
            "Invalid scenery region"
        );
        ensure!(
            self.chunks
                .iter()
                .flatten()
                .all(|&value| value.unsigned_abs() <= 1_874_998),
            "This part of the world is outside the generation limit"
        );
        for locator in &self.locate {
            ensure!(
                ["biome", "structure"].contains(&locator.kind.as_str())
                    && locator
                        .id
                        .strip_prefix("minecraft:")
                        .is_some_and(|id| !id.is_empty()
                            && id.bytes().all(|byte| byte.is_ascii_lowercase()
                                || byte.is_ascii_digit()
                                || byte == b'_')),
                "Invalid scenery destination"
            );
        }
        self.chunks.sort_unstable();
        self.chunks.dedup();
        Ok(())
    }
}

fn private_directory(path: &Path) -> Result<()> {
    ensure!(
        !path.is_symlink(),
        "A link blocks the isolated scenery runtime: {}",
        path.display()
    );
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

fn server(root: &Path) -> Result<PathBuf> {
    let target = root.join("server");
    if target.exists() || target.is_symlink() {
        ensure!(
            !target.is_symlink() && target.join("launcher.json").is_file(),
            "An existing folder blocks scenery setup: {}",
            target.display()
        );
        let receipt: serde_json::Value = read_json(&target.join("launcher.json"), 4096)?;
        ensure!(
            receipt["sha256"] == ARCHIVE
                && digest(&target.join("bedrock_server.exe"))? == EXECUTABLE,
            "The scenery generator did not pass verification"
        );
        return Ok(target);
    }
    let stage = tempfile::Builder::new()
        .prefix(".server-")
        .tempdir_in(root)?;
    let archive = stage.path().join("server.zip");
    event(json!({"state":"progress", "detail":"Downloading the world generator"}));
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(180))
        .user_agent("Mozilla/5.0")
        .build()?;
    let response = client
        .get(format!(
            "https://www.minecraft.net/bedrockdedicatedserver/bin-win/bedrock-server-{VERSION}.zip"
        ))
        .send()?
        .error_for_status()?;
    ensure!(
        response.url().scheme() == "https",
        "The generator download changed to an insecure address"
    );
    let mut output = File::create(&archive)?;
    let size = std::io::copy(&mut response.take(150_000_001), &mut output)?;
    ensure!(
        size <= 150_000_000 && digest(&archive)? == ARCHIVE,
        "The world generator download did not pass verification"
    );
    let mut archive = zip::ZipArchive::new(File::open(archive)?)?;
    ensure!(
        archive.len() <= 100_000,
        "The world generator archive is larger than expected"
    );
    let payload = stage.path().join("payload");
    fs::create_dir(&payload)?;
    let mut total = 0_u64;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        total = total
            .checked_add(entry.size())
            .context("Invalid archive size")?;
        ensure!(
            total <= 600 * 1024 * 1024
                && !entry.name().contains('\\')
                && entry
                    .unix_mode()
                    .is_none_or(|mode| mode & 0o170000 != 0o120000),
            "The world generator archive contains an unsafe entry"
        );
        let relative = entry
            .enclosed_name()
            .context("The world generator archive contains an unsafe path")?;
        let path = payload.join(relative);
        if entry.is_dir() {
            fs::create_dir_all(path)?;
        } else {
            fs::create_dir_all(path.parent().context("Invalid archive path")?)?;
            std::io::copy(&mut entry, &mut File::create(path)?)?;
        }
    }
    ensure!(
        digest(&payload.join("bedrock_server.exe"))? == EXECUTABLE,
        "The generator executable did not pass verification"
    );
    atomic(
        &payload.join("launcher.json"),
        &json!({"version":VERSION,"sha256":ARCHIVE}),
    )?;
    fs::rename(payload, &target)?;
    Ok(target)
}

fn properties(folder: &Path, seed: &str, name: &str) -> Result<()> {
    let values = [
        ("server-name", "Minecraft scenery"),
        ("gamemode", "creative"),
        ("difficulty", "normal"),
        ("allow-cheats", "true"),
        ("level-name", name),
        ("level-seed", seed),
        ("transport", "nethernet"),
        ("server-ip", "127.0.0.1"),
        ("server-port", "29134"),
        ("server-portv6", "29135"),
        ("enable-lan-visibility", "false"),
        ("allow-player-joining", "false"),
        ("max-players", "1"),
        ("max-threads", "2"),
        ("view-distance", "8"),
        ("tick-distance", "4"),
        ("emit-server-telemetry", "false"),
        ("allow-outbound-script-debugging", "false"),
        ("allow-inbound-script-debugging", "false"),
        ("script-debugger-auto-attach", "disabled"),
        ("content-log-file-enabled", "false"),
        ("online-mode", "false"),
        ("allow-list", "false"),
    ];
    let mut output = File::create(folder.join("server.properties"))?;
    for (key, value) in values {
        writeln!(output, "{key}={value}")?;
    }
    Ok(())
}

fn command(program: &Path, root: &Path, network: &Path) -> Command {
    let mut command = Command::new(program);
    command
        .env_clear()
        .envs(std::env::vars_os().filter(|(key, _)| {
            !["WINE", "DYLD_", "CX_"]
                .iter()
                .any(|prefix| key.to_string_lossy().starts_with(prefix))
        }))
        .env("WINEPREFIX", root.join("prefix"))
        .env("WINEARCH", "win64")
        .env("WINEDEBUG", "-all")
        .env("WINEDLLOVERRIDES", "winemenubuilder.exe,mscoree,mshtml=")
        .env("LC_ALL", "en_US.UTF-8")
        .env("DYLD_INSERT_LIBRARIES", network);
    command
}

struct Engine {
    child: Child,
    input: ChildStdin,
    root: PathBuf,
    wine: PathBuf,
    network: PathBuf,
}

impl Engine {
    fn send(&mut self, lines: &[String]) -> Result<()> {
        for line in lines {
            writeln!(self.input, "{line}")?;
        }
        self.input.flush()?;
        Ok(())
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.send(&["stop".into()]);
            let deadline = Instant::now() + Duration::from_secs(10);
            while Instant::now() < deadline && self.child.try_wait().ok().flatten().is_none() {
                std::thread::sleep(Duration::from_millis(50));
            }
            if self.child.try_wait().ok().flatten().is_none() {
                let _ = self.child.kill();
            }
            let _ = self.child.wait();
        }
        // Only the prefix acquired under this generator's lock is stopped
        let _ = crate::session::run(
            command(&self.wine.join("bin/wineserver"), &self.root, &self.network)
                .arg("-k")
                .stdout(Stdio::null())
                .stderr(Stdio::null()),
            &AtomicBool::new(false),
            Some(Duration::from_secs(10)),
            None,
        );
    }
}

fn generate(
    paths: &Paths,
    root: &Path,
    dimension: u8,
    chunks: &[[i32; 2]],
    locators: &[Locator],
    cancelled: &AtomicBool,
) -> Result<Vec<Destination>> {
    let prefix = if dimension == 0 {
        String::new()
    } else {
        format!("execute in {} run ", DIMENSIONS[dimension as usize])
    };
    let mut groups: BTreeMap<(i32, i32), Vec<[i32; 2]>> = BTreeMap::new();
    for &[x, z] in chunks {
        groups
            .entry((x.div_euclid(8), z.div_euclid(8)))
            .or_default()
            .push([x, z]);
    }
    ensure!(groups.len() <= 10, "Generate nearby chunks together");
    let mut commands: Vec<String> = [
        "doMobSpawning false",
        "doDaylightCycle false",
        "doWeatherCycle false",
        "randomTickSpeed 0",
    ]
    .map(|rule| format!("gamerule {rule}"))
    .into();
    for (index, points) in groups.values().enumerate() {
        let x0 = points.iter().map(|p| p[0]).min().context("Empty region")? * 16;
        let z0 = points.iter().map(|p| p[1]).min().context("Empty region")? * 16;
        let x1 = points.iter().map(|p| p[0]).max().context("Empty region")? * 16 + 15;
        let z1 = points.iter().map(|p| p[1]).max().context("Empty region")? * 16 + 15;
        commands.push(format!(
            "{prefix}tickingarea add {x0} 64 {z0} {x1} 64 {z1} scenery{index} true"
        ));
    }
    commands.extend(
        locators
            .iter()
            .map(|locator| format!("{prefix}locate {} {}", locator.kind, locator.id)),
    );
    let (y, original) = match dimension {
        0 => (-64, "bedrock"),
        1 => (0, "bedrock"),
        _ => (255, "air"),
    };
    let mut positions = BTreeMap::new();
    let mut edits = Vec::new();
    let mut probes = Vec::new();
    for (index, &[x, z]) in chunks.iter().enumerate() {
        positions.insert((x * 16, y, z * 16), index);
        let position = format!("{} {y} {}", x * 16, z * 16);
        edits.push(vec![
            format!(
                "{prefix}execute if block {position} barrier run setblock {position} {original}"
            ),
            format!(
                "{prefix}execute if block {position} {original} run setblock {position} barrier"
            ),
            format!(
                "{prefix}execute if block {position} barrier run setblock {position} {original}"
            ),
            format!("{prefix}testforblock {position} {original}"),
        ]);
        probes.push(vec![
            format!("{prefix}testforblock {position} {original}"),
            format!("{prefix}testforblock {position} barrier"),
        ]);
    }
    let mut child = command(Path::new("/usr/bin/nice"), root, &paths.network)
        .args(["-n", "10", "/usr/bin/sandbox-exec", "-f"])
        .arg(root.join("sandbox.sb"))
        .arg(paths.wine.join("bin/wine"))
        .arg(root.join("server/bedrock_server.exe"))
        .current_dir(root.join("server"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()?;
    let input = child
        .stdin
        .take()
        .context("The generator input is unavailable")?;
    let mut output = child
        .stdout
        .take()
        .context("The generator output is unavailable")?;
    let mut engine = Engine {
        child,
        input,
        root: root.into(),
        wine: paths.wine.clone(),
        network: paths.network.clone(),
    };
    let mut log = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(root.join("generator.log"))?;
    let mut poll = libc::pollfd {
        fd: output.as_raw_fd(),
        events: libc::POLLIN,
        revents: 0,
    };
    let (mut buffer, mut block, mut done, mut destinations) =
        (Vec::new(), [0_u8; 65536], BTreeSet::new(), Vec::new());
    let mut editing = BTreeSet::new();
    let loaded = Regex::new(r"Successfully found the block at (-?\d+),\s*(-?\d+),\s*(-?\d+)")?;
    let nearest = Regex::new(
        r"The nearest (minecraft:[a-z_0-9]+) is at block (-?\d+), (\(y\?\)|-?\d+), (-?\d+)",
    )?;
    let ansi = Regex::new(r"\x1b\[[0-?]*[ -/]*[@-~]")?;
    let deadline = Instant::now()
        + Duration::from_secs(180)
        + Duration::from_millis(chunks.len() as u64 * 500);
    let (mut ready, mut configured, mut stopping) = (None, false, false);
    let mut polled = Instant::now();
    event(
        json!({"state":"progress", "detail":"Starting Minecraft’s world generator", "progress":0}),
    );
    loop {
        ensure!(
            !cancelled.load(Ordering::Relaxed),
            "World generation was cancelled"
        );
        ensure!(
            Instant::now() < deadline,
            "World generation took too long; the previous scenery is preserved"
        );
        // The descriptor is owned by output and remains open for this single-entry poll
        let available = unsafe { libc::poll(&mut poll, 1, 100) };
        if available < 0 {
            let error = std::io::Error::last_os_error();
            if error.kind() != std::io::ErrorKind::Interrupted {
                return Err(error.into());
            }
        }
        if available > 0 {
            let count = output.read(&mut block)?;
            if count == 0 {
                break;
            }
            log.write_all(&block[..count])?;
            log.flush()?;
            buffer.extend_from_slice(&block[..count]);
            ensure!(
                buffer.len() <= 1024 * 1024,
                "The generator returned an oversized message"
            );
            while let Some(end) = buffer.iter().position(|&byte| byte == b'\n') {
                let bytes: Vec<_> = buffer.drain(..=end).collect();
                let line = String::from_utf8_lossy(&bytes);
                let text = ansi.replace_all(&line, "");
                if text.contains("Server started.") {
                    ready = Some(Instant::now());
                    engine.send(
                        &DIMENSIONS
                            .map(|name| format!("execute in {name} run tickingarea remove_all")),
                    )?;
                }
                if let Some(capture) = loaded.captures(&text) {
                    let position = (
                        capture[1].parse()?,
                        capture[2].parse()?,
                        capture[3].parse()?,
                    );
                    if let Some(&index) = positions.get(&position) {
                        if editing.insert(index) {
                            engine.send(&edits[index])?;
                        } else if done.insert(index) {
                            event(
                                json!({"state":"progress", "detail":format!("{} / {} chunks", done.len(), chunks.len()), "progress":done.len() as f64 / chunks.len() as f64}),
                            );
                        }
                    }
                }
                if let Some(capture) = nearest.captures(&text) {
                    destinations.push(Destination {
                        id: capture[1].into(),
                        x: capture[2].parse()?,
                        y: if &capture[3] == "(y?)" {
                            None
                        } else {
                            Some(capture[3].parse()?)
                        },
                        z: capture[4].parse()?,
                        dimension,
                    });
                }
            }
        }
        if ready.is_some_and(|time| time.elapsed() >= Duration::from_secs(1)) && !configured {
            engine.send(&commands)?;
            configured = true;
        }
        if configured && polled.elapsed() >= Duration::from_secs(1) && !stopping {
            for (index, lines) in probes.iter().enumerate() {
                if !editing.contains(&index) {
                    engine.send(lines)?;
                }
            }
            polled = Instant::now();
        }
        if configured && done.len() == chunks.len() && !stopping {
            engine.send(&["stop".into()])?;
            stopping = true;
        }
        if engine.child.try_wait()?.is_some() && available == 0 {
            break;
        }
    }
    ensure!(
        engine.child.wait()?.success() && done.len() == chunks.len(),
        "World generation stopped before all chunks were saved; try Generate again"
    );
    Ok(destinations)
}

pub fn run(args: Vec<OsString>, cancelled: Arc<AtomicBool>) -> Result<()> {
    let paths = Paths::parse(args)?;
    let mut request: Request = read_json(&paths.request, 1024 * 1024)?;
    request.validate()?;
    ensure!(
        paths.wine.join("bin/wine").is_file() && paths.network.is_file(),
        "The scenery generator runtime is incomplete"
    );
    let root = paths.root.join("scenery");
    private_directory(&root)?;
    let generator = root.join("generator");
    private_directory(&generator)?;
    ensure!(
        !generator.join("prefix").is_symlink(),
        "A link blocks the isolated scenery runtime"
    );
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .append(true)
        .mode(0o600)
        .open(generator.join("lock"))?;
    lock.try_lock()
        .context("Another scenery world is being prepared; try again shortly")?;
    let payload = server(&generator)?;
    let identifier = hex(&Sha256::digest(format!("{VERSION}\0{}", request.seed)))[..24].to_owned();
    let worlds = root.join("worlds");
    private_directory(&worlds)?;
    let folder = worlds.join(&identifier);
    ensure!(
        !folder.is_symlink() && (!folder.exists() || folder.join("launcher.json").is_file()),
        "An existing folder blocks this scenery world"
    );
    private_directory(&folder)?;
    let marker = folder.join("launcher.json");
    let mut manifest = if marker.exists() {
        read_json::<Manifest>(&marker, 4 * 1024 * 1024)?
    } else {
        Manifest {
            version: VERSION.into(),
            seed: request.seed.clone(),
            chunks: BTreeSet::new(),
            destinations: Vec::new(),
        }
    };
    ensure!(
        manifest.version == VERSION && manifest.seed == request.seed,
        "This scenery cache belongs to another world"
    );
    atomic(&marker, &manifest)?;
    let link = payload.join("worlds");
    if link.is_symlink() {
        ensure!(
            link.canonicalize()? == worlds.canonicalize()?,
            "An existing link blocks the isolated scenery worlds"
        );
    } else {
        ensure!(
            !link.exists(),
            "An existing folder blocks the isolated scenery worlds"
        );
        symlink(&worlds, &link)?;
    }
    properties(&payload, &request.seed, &identifier)?;
    let mut sandbox = String::from(
        "(version 1)\n(allow default)\n(deny network-outbound)\n(allow network-outbound (remote unix-socket))\n(allow network-outbound (remote ip \"localhost:*\"))\n(deny network-inbound)\n(allow network-inbound (local unix-socket))\n(allow network-inbound (local ip \"localhost:*\"))\n",
    );
    for protected in [
        paths.root.join("game"),
        paths.root.join("bottles"),
        PathBuf::from(std::env::var_os("HOME").context("Missing home directory")?)
            .join("Library/Keychains"),
    ] {
        sandbox.push_str(&format!(
            "(deny file-write* (subpath {}))\n",
            serde_json::to_string(&protected)?
        ));
    }
    fs::write(generator.join("sandbox.sb"), sandbox)?;
    let mut groups: BTreeMap<(i32, i32), Vec<[i32; 2]>> = BTreeMap::new();
    for &[x, z] in &request.chunks {
        if !manifest.chunks.contains(&(request.dimension, x, z)) {
            groups
                .entry((x.div_euclid(8), z.div_euclid(8)))
                .or_default()
                .push([x, z]);
        }
    }
    request.locate.retain(|locator| {
        !manifest
            .destinations
            .iter()
            .any(|point| point.dimension == request.dimension && point.id == locator.id)
    });
    let grouped: Vec<_> = groups.into_values().collect();
    if grouped.is_empty() && !request.locate.is_empty() {
        manifest.destinations.extend(generate(
            &paths,
            &generator,
            request.dimension,
            &[],
            &request.locate,
            &cancelled,
        )?);
    }
    for (index, group) in grouped.chunks(10).enumerate() {
        let chunks: Vec<_> = group.iter().flatten().copied().collect();
        manifest.destinations.extend(generate(
            &paths,
            &generator,
            request.dimension,
            &chunks,
            if index == 0 { &request.locate } else { &[] },
            &cancelled,
        )?);
        manifest
            .chunks
            .extend(chunks.iter().map(|&[x, z]| (request.dimension, x, z)));
        atomic(&marker, &manifest)?;
    }
    atomic(&marker, &manifest)?;
    event(
        json!({"state":"world_ready", "database":folder.join("db"), "version":VERSION, "manifest":marker}),
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_and_deduplicates_requests() {
        let mut request: Request = serde_json::from_value(
            json!({"seed":"Adventure 2026","dimension":0,"chunks":[[-1,-1],[0,0],[-1,-1]]}),
        )
        .unwrap();
        request.validate().unwrap();
        assert_eq!(request.chunks, [[-1, -1], [0, 0]]);
        for seed in ["", "0\nallow-player-joining=true"] {
            request.seed = seed.into();
            assert!(request.validate().is_err());
        }
    }

    #[test]
    fn accepts_discovery_and_rejects_command_injection() {
        for (id, valid) in [
            ("minecraft:cherry_grove", true),
            ("cherry_grove", false),
            ("minecraft:cherry_grove\nstop", false),
            ("../worlds", false),
        ] {
            let mut request: Request = serde_json::from_value(
                json!({"seed":"0","dimension":0,"chunks":[],"locate":[{"kind":"biome","id":id}]}),
            )
            .unwrap();
            assert_eq!(request.validate().is_ok(), valid);
        }
    }

    #[test]
    fn rejects_wrong_coordinate_and_dimension_types() {
        for value in [
            json!({"seed":"0","dimension":true,"chunks":[[0,0]]}),
            json!({"seed":"0","dimension":0,"chunks":[[true,0]]}),
        ] {
            assert!(serde_json::from_value::<Request>(value).is_err());
        }
        let mut request: Request =
            serde_json::from_value(json!({"seed":"0","dimension":3,"chunks":[[0,0]]})).unwrap();
        assert!(request.validate().is_err());
        request.dimension = 0;
        request.chunks = vec![[i32::MIN, 0]];
        assert!(request.validate().is_err());
    }
}
