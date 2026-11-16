use crate::{atomic, atomic_bytes, digest, event, hex, read_json};
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
    refresh: Vec<[i32; 2]>,
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
    #[serde(default)]
    chunks: BTreeSet<(u8, i32, i32)>,
    destinations: Vec<Destination>,
}

struct Cache {
    folder: PathBuf,
    regions: BTreeMap<(u8, i32, i32), BTreeSet<[i32; 2]>>,
}

impl Cache {
    fn region(&mut self, dimension: u8, x: i32, z: i32) -> Result<&mut BTreeSet<[i32; 2]>> {
        ensure!(
            dimension < 3 && x.unsigned_abs() <= 1_874_998 && z.unsigned_abs() <= 1_874_998,
            "Invalid cached chunk"
        );
        let key = (dimension, x.div_euclid(32), z.div_euclid(32));
        if !self.regions.contains_key(&key) {
            let path = self
                .folder
                .join(format!("{}-{}-{}.json", key.0, key.1, key.2));
            ensure!(!path.is_symlink(), "A link blocks the scenery chunk index");
            let points: BTreeSet<[i32; 2]> = if path.exists() {
                read_json(&path, 64 * 1024)?
            } else {
                BTreeSet::new()
            };
            ensure!(
                points.len() <= 1024
                    && points
                        .iter()
                        .all(|[x, z]| x.div_euclid(32) == key.1 && z.div_euclid(32) == key.2),
                "Invalid scenery chunk index"
            );
            self.regions.insert(key, points);
        }
        self.regions.get_mut(&key).context("Missing scenery region")
    }

    fn save(&self) -> Result<()> {
        for (key, points) in &self.regions {
            atomic(
                &self
                    .folder
                    .join(format!("{}-{}-{}.json", key.0, key.1, key.2)),
                points,
            )?;
        }
        Ok(())
    }
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
                && self.chunks.len() <= 1225
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
        let mut unique = BTreeSet::new();
        self.chunks.retain(|point| unique.insert(*point));
        ensure!(
            self.refresh.len() <= self.chunks.len()
                && self.refresh.iter().all(|point| unique.contains(point)),
            "Invalid scenery repair region"
        );
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
        let name = entry.name()?.into_owned();
        total = total
            .checked_add(entry.size())
            .context("Invalid archive size")?;
        ensure!(
            total <= 600 * 1024 * 1024
                && !name.contains('\\')
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

#[derive(Default)]
struct Checks {
    done: BTreeSet<usize>,
    pending: BTreeSet<usize>,
}

impl Checks {
    fn commands(&mut self, window: usize, count: usize) -> Vec<String> {
        if !self.pending.is_empty() {
            return Vec::new();
        }
        let Some(first) = (0..count).find(|index| !self.done.contains(index)) else {
            return Vec::new();
        };
        let group = first / 16;
        self.pending = (group * 16..count.min((group + 1) * 16)).collect();
        vec![
            format!("function scenery/window{window}/batch{group}"),
            format!(
                "scoreboard players test progress scenery {} {}",
                self.pending.len(),
                self.pending.len()
            ),
            "list".into(),
        ]
    }

    fn completed(&mut self, count: usize) -> bool {
        if self.pending.is_empty() || count != self.pending.len() {
            return false;
        }
        let before = self.done.len();
        self.done.extend(&self.pending);
        self.done.len() != before
    }

    fn finish(&mut self, text: &str) {
        // The pinned server's list reply follows every check in this batch
        if barrier(text) {
            self.pending.clear();
        }
    }

    fn complete(&self, count: usize) -> bool {
        self.done.len() == count && self.pending.is_empty()
    }
}

fn barrier(text: &str) -> bool {
    text.contains("There are ") && text.contains(" players online:")
}

struct Window {
    chunks: Vec<[i32; 2]>,
    areas: Vec<String>,
}

fn windows(dimension: u8, chunks: &[[i32; 2]]) -> Result<Vec<Window>> {
    let mut positions = BTreeMap::new();
    let mut groups: Vec<Vec<[i32; 2]>> = Vec::new();
    for &[x, z] in chunks {
        let next = groups.len();
        let index = *positions
            .entry((x.div_euclid(8), z.div_euclid(8)))
            .or_insert_with(|| {
                groups.push(Vec::new());
                next
            });
        groups[index].push([x, z]);
    }
    let prefix = format!("execute in {} run ", DIMENSIONS[dimension as usize]);
    groups
        .chunks(10)
        .map(|groups| {
            let mut window = Window {
                chunks: Vec::new(),
                areas: Vec::new(),
            };
            for (index, points) in groups.iter().enumerate() {
                let x0 = points.iter().map(|p| p[0]).min().context("Empty region")? * 16;
                let z0 = points.iter().map(|p| p[1]).min().context("Empty region")? * 16;
                let x1 = points.iter().map(|p| p[0]).max().context("Empty region")? * 16 + 15;
                let z1 = points.iter().map(|p| p[1]).max().context("Empty region")? * 16 + 15;
                window.areas.push(format!(
                    "{prefix}tickingarea add {x0} 64 {z0} {x1} 64 {z1} scenery{index} true"
                ));
                window.chunks.extend_from_slice(points);
            }
            Ok(window)
        })
        .collect()
}

fn functions(folder: &Path, dimension: u8, windows: &[Window]) -> Result<()> {
    let mut pack = folder.to_path_buf();
    for component in ["behavior_packs", "scenery"] {
        pack.push(component);
        private_directory(&pack)?;
    }
    atomic_bytes(
        &pack.join("manifest.json"),
        &serde_json::to_vec(
            &json!({"format_version":2,"header":{"name":"Launcher scenery checks","description":"Private generation checks","uuid":"a2958bc5-2abc-4bdb-9b90-a372808e5dbe","version":[1,0,0],"min_engine_version":[1,21,0]},"modules":[{"type":"data","uuid":"5c7d63e9-7c1c-43d7-80f8-4080b17d74b0","version":[1,0,0]}]}),
        )?,
    )?;
    let enabled = folder.join("world_behavior_packs.json");
    let mut entries: Vec<serde_json::Value> = if enabled.exists() {
        read_json(&enabled, 64 * 1024)?
    } else {
        Vec::new()
    };
    ensure!(entries.len() <= 16, "Too many scenery behaviour packs");
    if !entries
        .iter()
        .any(|entry| entry["pack_id"] == "a2958bc5-2abc-4bdb-9b90-a372808e5dbe")
    {
        entries.push(json!({"pack_id":"a2958bc5-2abc-4bdb-9b90-a372808e5dbe","version":[1,0,0]}));
        atomic(&enabled, &entries)?;
    }
    pack.push("functions");
    private_directory(&pack)?;
    pack.push("scenery");
    private_directory(&pack)?;
    let prefix = format!("execute in {} run ", DIMENSIONS[dimension as usize]);
    let (y, original) = if dimension == 0 {
        (-64, "bedrock")
    } else if dimension == 1 {
        (0, "bedrock")
    } else {
        (255, "air")
    };
    for (window, region) in windows.iter().enumerate() {
        let directory = pack.join(format!("window{window}"));
        private_directory(&directory)?;
        for (group, points) in region.chunks.chunks(16).enumerate() {
            let mut batch = String::from("scoreboard players set progress scenery 0\n");
            for (offset, &[x, z]) in points.iter().enumerate() {
                let index = group * 16 + offset;
                let position = format!("{} {y} {}", x * 16, z * 16);
                for block in [original, "barrier"] {
                    batch.push_str(&format!("{prefix}execute if block {position} {block} run function scenery/window{window}/chunk{index}\n"));
                }
                let text = format!(
                    "{prefix}execute if block {position} barrier run setblock {position} {original}\n{prefix}execute if block {position} {original} run setblock {position} barrier\n{prefix}execute if block {position} barrier run setblock {position} {original}\n{prefix}execute if block {position} {original} run scoreboard players add progress scenery 1\n"
                );
                atomic_bytes(
                    &directory.join(format!("chunk{index}.mcfunction")),
                    text.as_bytes(),
                )?;
            }
            atomic_bytes(
                &directory.join(format!("batch{group}.mcfunction")),
                batch.as_bytes(),
            )?;
        }
    }
    Ok(())
}

fn acquire(lock: &File, cancelled: &AtomicBool) -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        ensure!(
            !cancelled.load(Ordering::Relaxed),
            "World generation was cancelled"
        );
        match lock.try_lock() {
            Ok(()) => return Ok(()),
            Err(std::fs::TryLockError::WouldBlock) if Instant::now() < deadline => {
                std::thread::sleep(Duration::from_millis(100));
            }
            Err(error) => {
                return Err(error)
                    .context("Another scenery world is still being prepared; try again shortly");
            }
        }
    }
}

enum Phase {
    Starting,
    Clearing,
    Settling(Instant),
    Configuring,
    Checking,
    Stopping,
}

fn generate(
    paths: &Paths,
    root: &Path,
    folder: &Path,
    dimension: u8,
    chunks: &[[i32; 2]],
    locators: &[Locator],
    cancelled: &AtomicBool,
) -> Result<Vec<Destination>> {
    let mut windows = windows(dimension, chunks)?;
    if windows.is_empty() {
        windows.push(Window {
            chunks: Vec::new(),
            areas: Vec::new(),
        });
    }
    functions(folder, dimension, &windows)?;
    let prefix = if dimension == 0 {
        String::new()
    } else {
        format!("execute in {} run ", DIMENSIONS[dimension as usize])
    };
    let mut commands: Vec<String> = [
        "doMobSpawning false",
        "doDaylightCycle false",
        "doWeatherCycle false",
        "randomTickSpeed 0",
    ]
    .map(|rule| format!("gamerule {rule}"))
    .into();
    commands.push("scoreboard objectives add scenery dummy".into());
    let discoveries: Vec<_> = locators
        .iter()
        .map(|locator| format!("{prefix}locate {} {}", locator.kind, locator.id))
        .collect();
    ensure!(
        !cancelled.load(Ordering::Relaxed),
        "World generation was cancelled"
    );
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
    let (mut buffer, mut block, mut destinations) = (Vec::new(), [0_u8; 65536], Vec::new());
    let mut checks = Checks::default();
    let loaded = Regex::new(r"Score (\d+) is in range")?;
    let nearest = Regex::new(
        r"The nearest (minecraft:[a-z_0-9]+) is at block (-?\d+), (\(y\?\)|-?\d+), (-?\d+)",
    )?;
    let ansi = Regex::new(r"\x1b\[[0-?]*[ -/]*[@-~]")?;
    let deadline = Instant::now()
        + Duration::from_secs(180 + windows.len() as u64)
        + Duration::from_millis(chunks.len() as u64 * 500);
    let mut phase = Phase::Starting;
    let (mut window, mut completed, mut saved) = (0, 0, false);
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
                if engine.child.try_wait()?.is_some() {
                    break;
                }
                std::thread::sleep(Duration::from_millis(50));
                continue;
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
                if matches!(phase, Phase::Starting) && text.contains("Server started.") {
                    let mut cleanup = DIMENSIONS
                        .map(|name| format!("execute in {name} run tickingarea remove_all"))
                        .to_vec();
                    cleanup.push("list".into());
                    engine.send(&cleanup)?;
                    phase = Phase::Clearing;
                }
                if let Some(capture) = loaded.captures(&text)
                    && checks.completed(capture[1].parse()?)
                {
                    event(
                        json!({"state":"progress", "detail":format!("{} / {} chunks", completed + checks.done.len(), chunks.len()), "progress":(completed + checks.done.len()) as f64 / chunks.len() as f64}),
                    );
                }
                checks.finish(&text);
                if barrier(&text) {
                    match &phase {
                        Phase::Clearing if window == windows.len() => {
                            event(json!({"state":"progress", "detail":"Saving your world"}));
                            engine.send(&["stop".into()])?;
                            phase = Phase::Stopping;
                        }
                        Phase::Clearing => phase = Phase::Settling(Instant::now()),
                        Phase::Configuring => phase = Phase::Checking,
                        _ => {}
                    }
                }
                saved |= text.contains("Quit correctly");
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
        // Area removal settles after its ordered console reply, before slots are reused
        if let Phase::Settling(time) = &phase
            && time.elapsed() >= Duration::from_secs(1)
        {
            if window == 0 {
                engine.send(&commands)?;
            }
            engine.send(&windows[window].areas)?;
            if window == 0 {
                engine.send(&discoveries)?;
            }
            engine.send(&["list".into()])?;
            phase = Phase::Configuring;
        }
        if matches!(phase, Phase::Checking) {
            let count = windows[window].chunks.len();
            if checks.complete(count) {
                completed += count;
                window += 1;
                checks = Checks::default();
                engine.send(&[format!("{prefix}tickingarea remove_all"), "list".into()])?;
                phase = Phase::Clearing;
            } else if polled.elapsed() >= Duration::from_millis(100) {
                engine.send(&checks.commands(window, count))?;
                polled = Instant::now();
            }
        }
        if engine.child.try_wait()?.is_some() && available == 0 {
            break;
        }
    }
    saved |= ansi
        .replace_all(&String::from_utf8_lossy(&buffer), "")
        .contains("Quit correctly");
    ensure!(
        engine.child.wait()?.success()
            && matches!(phase, Phase::Stopping)
            && saved
            && completed == chunks.len(),
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
    event(json!({"state":"progress", "detail":"Opening your scenery world"}));
    acquire(&lock, &cancelled)?;
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
    let completed = folder.join("completed");
    private_directory(&completed)?;
    let mut cache = Cache {
        folder: completed,
        regions: BTreeMap::new(),
    };
    for (dimension, x, z) in std::mem::take(&mut manifest.chunks) {
        cache.region(dimension, x, z)?.insert([x, z]);
    }
    cache.save()?;
    for &[x, z] in &request.refresh {
        cache.region(request.dimension, x, z)?.remove(&[x, z]);
    }
    cache.save()?;
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
    let mut chunks = Vec::new();
    for &[x, z] in &request.chunks {
        if !cache.region(request.dimension, x, z)?.contains(&[x, z]) {
            chunks.push([x, z]);
        }
    }
    request.locate.retain(|locator| {
        !manifest
            .destinations
            .iter()
            .any(|point| point.dimension == request.dimension && point.id == locator.id)
    });
    if !chunks.is_empty() || !request.locate.is_empty() {
        manifest.destinations.extend(generate(
            &paths,
            &generator,
            &folder,
            request.dimension,
            &chunks,
            &request.locate,
            &cancelled,
        )?);
        for &[x, z] in &chunks {
            cache.region(request.dimension, x, z)?.insert([x, z]);
        }
        cache.save()?;
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
    fn paged_manifest_retains_the_previous_builds_header_contract() {
        let manifest = Manifest {
            version: VERSION.into(),
            seed: "42".into(),
            chunks: BTreeSet::new(),
            destinations: Vec::new(),
        };
        let value = serde_json::to_value(&manifest).unwrap();
        assert_eq!(value["chunks"], json!([]));
        let restored: Manifest = serde_json::from_value(value).unwrap();
        assert_eq!(restored.seed, "42");
    }

    #[test]
    fn chunk_index_is_paged_and_keeps_dimension_and_negative_coordinates() {
        let folder = tempfile::tempdir().unwrap();
        let mut cache = Cache {
            folder: folder.path().into(),
            regions: BTreeMap::new(),
        };
        cache.region(0, -1, 32).unwrap().insert([-1, 32]);
        cache.region(1, -1, 32).unwrap().insert([-1, 32]);
        cache.save().unwrap();
        let mut reopened = Cache {
            folder: folder.path().into(),
            regions: BTreeMap::new(),
        };
        assert!(reopened.region(0, -1, 32).unwrap().contains(&[-1, 32]));
        assert!(!reopened.region(2, -1, 32).unwrap().contains(&[-1, 32]));
        reopened.region(0, -1, 32).unwrap().remove(&[-1, 32]);
        assert!(reopened.region(1, -1, 32).unwrap().contains(&[-1, 32]));
        reopened.save().unwrap();
        let mut repaired = Cache {
            folder: folder.path().into(),
            regions: BTreeMap::new(),
        };
        assert!(!repaired.region(0, -1, 32).unwrap().contains(&[-1, 32]));
        assert!(repaired.region(1, -1, 32).unwrap().contains(&[-1, 32]));
        assert!(reopened.region(0, i32::MIN, 0).is_err());
        let mut request: Request = serde_json::from_value(
            json!({"seed":"0","dimension":0,"chunks":[[0,0]],"refresh":[[1,1]]}),
        )
        .unwrap();
        assert!(request.validate().is_err());
        request.refresh = vec![[0, 0]];
        request.validate().unwrap();
    }

    #[test]
    fn checks_wait_for_console_drain_and_retry_only_unfinished_chunks() {
        let mut checks = Checks::default();
        assert_eq!(checks.commands(2, 330).len(), 3);
        for _ in 0..100 {
            assert!(checks.commands(2, 330).is_empty());
        }
        assert!(!checks.completed(15));
        checks.finish("[INFO] There are 0/1 players online:");
        assert_eq!(
            checks.commands(2, 330)[0],
            "function scenery/window2/batch0"
        );
        assert!(checks.pending.contains(&15));
        while checks.done.len() < 330 {
            assert!(checks.completed(checks.pending.len()));
            assert!(!checks.completed(checks.pending.len()));
            assert!(!checks.complete(checks.done.len()));
            checks.finish("[INFO] There are 0/1 players online:");
            assert!(checks.commands(2, 330).len() <= 3);
        }
        assert!(checks.complete(330));
        assert!(checks.commands(2, 330).is_empty());
    }

    #[test]
    fn windows_keep_requested_group_order_and_reuse_only_ten_area_slots() {
        let mut chunks: Vec<_> = (0..21).map(|index| [(10 - index) * 8, -1]).collect();
        chunks.push([81, -1]);
        let windows = windows(1, &chunks).unwrap();
        assert_eq!(windows.len(), 3);
        assert_eq!(windows[0].areas.len(), 10);
        assert_eq!(windows[1].areas.len(), 10);
        assert_eq!(windows[2].areas.len(), 1);
        assert_eq!(&windows[0].chunks[..3], &[[80, -1], [81, -1], [72, -1]]);
        assert_eq!(windows[1].chunks[0], [0, -1]);
        assert!(windows[2].areas[0].starts_with("execute in nether run tickingarea add"));
        assert!(windows[2].areas[0].ends_with("scenery0 true"));
        let retained: BTreeSet<_> = windows
            .iter()
            .flat_map(|window| window.chunks.iter().copied())
            .collect();
        assert_eq!(retained, chunks.into_iter().collect());
    }

    #[test]
    fn function_batches_restore_sentinels_in_the_requested_dimension() {
        let folder = tempfile::tempdir().unwrap();
        let retained = json!({"pack_id":"unrelated","version":[1,0,0]});
        atomic(
            &folder.path().join("world_behavior_packs.json"),
            &vec![&retained],
        )
        .unwrap();
        functions(
            folder.path(),
            1,
            &[
                Window {
                    chunks: vec![[2, -3]; 17],
                    areas: Vec::new(),
                },
                Window {
                    chunks: vec![[4, 5]],
                    areas: Vec::new(),
                },
            ],
        )
        .unwrap();
        let pack = folder
            .path()
            .join("behavior_packs/scenery/functions/scenery");
        let first = fs::read_to_string(pack.join("window0/batch0.mcfunction")).unwrap();
        assert_eq!(first.lines().count(), 33);
        assert!(first.contains("execute in nether run execute if block 32 0 -48 bedrock"));
        let chunk = fs::read_to_string(pack.join("window0/chunk16.mcfunction")).unwrap();
        assert!(chunk.contains("barrier run setblock 32 0 -48 bedrock"));
        assert!(chunk.ends_with("run scoreboard players add progress scenery 1\n"));
        let last = fs::read_to_string(pack.join("window1/batch0.mcfunction")).unwrap();
        assert_eq!(last.lines().count(), 3);
        assert!(last.contains("run function scenery/window1/chunk0"));
        let entries: Vec<serde_json::Value> =
            read_json(&folder.path().join("world_behavior_packs.json"), 65536).unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0], retained);
    }

    #[test]
    fn waits_for_owned_generator_cleanup_and_allows_cancellation() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let held = File::open(file.path()).unwrap();
        let waiting = File::open(file.path()).unwrap();
        held.try_lock().unwrap();
        assert!(matches!(
            waiting.try_lock(),
            Err(std::fs::TryLockError::WouldBlock)
        ));
        assert!(acquire(&waiting, &AtomicBool::new(true)).is_err());
        let release = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(150));
            drop(held);
        });
        acquire(&waiting, &AtomicBool::new(false)).unwrap();
        release.join().unwrap();
    }

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
    fn accepts_the_full_near_radius_with_a_halo_and_preserves_near_first_order() {
        let mut chunks: Vec<_> = (-17_i32..=17)
            .flat_map(|x| (-17_i32..=17).map(move |z| [x, z]))
            .collect();
        chunks.sort_by_key(|[x, z]| (x.abs().max(z.abs()), x * x + z * z, *x, *z));
        let mut request: Request = serde_json::from_value(
            json!({"seed":"0","dimension":0,"chunks":chunks,"refresh":[[17,17],[0,0]]}),
        )
        .unwrap();
        request.validate().unwrap();
        assert_eq!(request.chunks.len(), 1225);
        assert_eq!(request.chunks[0], [0, 0]);
        let windows = windows(0, &request.chunks).unwrap();
        assert!(windows.len() > 1);
        assert!(windows.iter().all(|window| window.areas.len() <= 10));
        assert!(windows.iter().all(|window| window.chunks.len() <= 640));
        assert_eq!(
            windows
                .iter()
                .map(|window| window.chunks.len())
                .sum::<usize>(),
            1225
        );
        request.chunks.push([18, 18]);
        assert!(request.validate().is_err());
        request.chunks = vec![[3, 2], [0, 0], [3, 2], [-1, -1]];
        request.refresh.clear();
        request.validate().unwrap();
        assert_eq!(request.chunks, [[3, 2], [0, 0], [-1, -1]]);
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
