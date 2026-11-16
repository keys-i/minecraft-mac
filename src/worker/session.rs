use crate::{atomic, digest, event, input, read_json};
use anyhow::{Context as _, Result, bail, ensure};
use serde_json::{Value, json};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt, symlink};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const THREADING: &str = "aa611155057ebd01cf315ad702a4b5725aa9d5e6fad87732c956fe0a1e5fcfba";
const OVERRIDES: &str = "xgameruntime,windows.web,twinapi.appcore,windows.ui.core.textinput,wintypes=b;d3d11,dxgi,d3d10core,winemetal=b;d3d12,d3d12core,mscoree,mshtml=";
const SOCKET: &str = "/tmp/xodus.sock";

pub struct Context {
    pub root: PathBuf,
    pub bundle: Option<PathBuf>,
}

impl Context {
    pub fn load() -> Result<Self> {
        let bundle = std::env::var_os("BEDROCK_BUNDLE").map(PathBuf::from);
        let root = if bundle.is_some() {
            PathBuf::from(std::env::var_os("HOME").context("Missing home directory")?)
                .join("Library/Application Support/Bedrock for Mac")
        } else {
            std::env::var_os("BEDROCK_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")))
        };
        Ok(Self { root, bundle })
    }
    pub fn wine(&self) -> PathBuf {
        self.root.join("runtime/standalone/wine")
    }
    pub fn dxmt(&self) -> PathBuf {
        self.root.join("runtime/standalone/dxmt")
    }
    pub fn prefix(&self) -> PathBuf {
        self.root.join("bottles/Bedrock-Standalone")
    }
    pub fn game(&self) -> PathBuf {
        self.root.join("game")
    }
    pub fn helper(&self) -> PathBuf {
        self.root
            .join("sources/xodus/target/release/examples/standalone_helper")
    }

    pub fn initialise(&self) -> Result<()> {
        let Some(bundle) = &self.bundle else {
            return Ok(());
        };
        fs::create_dir_all(&self.root)?;
        for (relative, name) in [
            ("runtime/standalone/wine", "runtime/wine"),
            ("runtime/standalone/dxmt", "runtime/dxmt"),
            (
                "sources/xodus/target/release/examples/standalone_helper",
                "standalone_helper",
            ),
        ] {
            let destination = self.root.join(relative);
            let target = bundle.join(name);
            fs::create_dir_all(destination.parent().context("Missing runtime directory")?)?;
            if destination.is_symlink() {
                if destination.canonicalize().ok() == target.canonicalize().ok() {
                    continue;
                }
                fs::remove_file(&destination)?;
            } else {
                ensure!(
                    !destination.exists(),
                    "An existing installation blocks app setup: {relative}"
                );
            }
            symlink(target, destination)?;
        }
        Ok(())
    }

    pub fn environment(&self, program: impl AsRef<std::ffi::OsStr>) -> Command {
        let mut command = clean(program);
        command
            .env("WINEPREFIX", self.prefix())
            .env("WINEARCH", "win64")
            .env("WINEDEBUG", "-all")
            .env("WINEDLLPATH", self.dxmt())
            .env("WINEDLLOVERRIDES", OVERRIDES)
            .env("LC_ALL", "en_US.UTF-8");
        command
    }

    pub fn bridge(&self) -> Result<()> {
        let sources = self
            .bundle
            .as_ref()
            .map(|bundle| bundle.join("scripts"))
            .unwrap_or_else(|| self.root.clone());
        bridge(&self.wine(), &self.dxmt(), &sources)
    }

    pub fn prerequisites(&self, game: &Path) -> Result<()> {
        for path in [
            self.wine().join("bin/wine"),
            self.wine().join("bin/wineserver"),
            self.wine().join("lib/wine/x86_64-windows/xgameruntime.dll"),
            self.dxmt().join("x86_64-windows/d3d11.dll"),
            self.dxmt().join("x86_64-unix/winemetal.so"),
            self.root.join("runtime/xgameruntime.dll.threading"),
            game.join("Minecraft.Windows.exe"),
            game.join("MicrosoftGame.Config"),
            game.join(".xodus-streaming.msixvc"),
            game.join("Installers/GameInputRedist.msi"),
        ] {
            ensure!(path.is_file(), "Missing required file: {}", path.display());
        }
        for relative in [
            "x86_64-windows/d3d11.dll",
            "x86_64-windows/dxgi.dll",
            "x86_64-windows/d3d10core.dll",
            "x86_64-windows/winemetal.dll",
            "x86_64-unix/winemetal.so",
        ] {
            if relative == "x86_64-unix/winemetal.so"
                && self.wine().join("dxmt-unix-bridge.json").is_file()
            {
                self.bridge()?;
            } else {
                ensure!(
                    digest(&self.wine().join("lib/wine").join(relative))?
                        == digest(&self.dxmt().join(relative))?,
                    "The installed graphics overlay differs from DXMT; reinstall the complete runtime"
                );
            }
        }
        ensure!(
            digest(&self.root.join("runtime/xgameruntime.dll.threading"))? == THREADING,
            "Microsoft’s threading DLL does not match the pinned official version"
        );
        let mut magic = [0; 2];
        File::open(game.join("Minecraft.Windows.exe"))?.read_exact(&mut magic)?;
        ensure!(
            magic == *b"MZ",
            "The game executable did not pass verification"
        );
        Ok(())
    }

    pub fn signature(&self, game: &Path) -> Result<Value> {
        Ok(json!({"setup_version":2,"game":game,"threading":THREADING,
            "gameinput":digest(&game.join("Installers/GameInputRedist.msi"))?,"wine":digest(&self.wine().join("bin/wine"))?,"dxmt":digest(&self.dxmt().join("x86_64-windows/d3d11.dll"))?}))
    }

    pub fn installed(&self) -> bool {
        let game = self.game();
        self.helper().is_file()
            && self.prerequisites(&game).is_ok()
            && self.signature(&game).ok().is_some_and(|desired| {
                read_json::<Value>(&self.prefix().join(".bedrock-setup.json"), 64 * 1024).ok()
                    == Some(desired)
            })
    }

    fn map(&self, letter: &str, folder: &Path) -> Result<()> {
        let link = self.prefix().join("dosdevices").join(format!("{letter}:"));
        if link.is_symlink() && link.canonicalize()? == folder.canonicalize()? {
            return Ok(());
        }
        ensure!(
            !link.exists() && !link.is_symlink(),
            "Unexpected existing drive mapping: {}",
            link.display()
        );
        symlink(folder.canonicalize()?, link)?;
        Ok(())
    }

    fn idle(&self, cancelled: &AtomicBool) -> Result<()> {
        if self.prefix().exists() {
            run(
                self.environment(self.wine().join("bin/wineserver"))
                    .arg("-w"),
                cancelled,
                Some(Duration::from_secs(1)),
                None,
            )?;
        }
        Ok(())
    }

    fn stop_setup(&self, cancelled: &AtomicBool) -> Result<()> {
        run(
            self.environment(self.wine().join("bin/wineserver"))
                .arg("-k"),
            cancelled,
            Some(Duration::from_secs(5)),
            None,
        )?;
        run(
            self.environment(self.wine().join("bin/wineserver"))
                .arg("-w"),
            cancelled,
            Some(Duration::from_secs(10)),
            None,
        )?;
        Ok(())
    }

    fn wine_run(
        &self,
        args: &[&str],
        game: &Path,
        log: &File,
        cancelled: &AtomicBool,
        timeout: Option<Duration>,
    ) -> Result<()> {
        let mut command = self.environment(self.wine().join("bin/wine"));
        command
            .args(args)
            .current_dir(game)
            .stdout(log.try_clone()?)
            .stderr(log.try_clone()?);
        run(&mut command, cancelled, timeout, None)
    }

    pub fn prepare(&self, game: &Path, cancelled: &AtomicBool) -> Result<()> {
        self.prerequisites(game)?;
        let prefix = self.prefix();
        ensure!(
            !self.root.join("bottles").is_symlink()
                && !prefix.is_symlink()
                && prefix != self.root.join("bottles/Bedrock-Mac"),
            "The standalone prefix must be a separate directory"
        );
        fs::create_dir_all(prefix.parent().context("Missing prefix directory")?)?;
        fs::create_dir_all(self.root.join("logs/standalone"))?;
        let desired = self.signature(game)?;
        if read_json::<Value>(&prefix.join(".bedrock-setup.json"), 64 * 1024).ok()
            == Some(desired.clone())
        {
            self.map("g", game)?;
            self.map("r", &self.root)?;
            return Ok(());
        }
        self.idle(cancelled)
            .context("Close programs using the standalone prefix before updating its setup")?;
        let result = (|| -> Result<()> {
            let log = private_log(&self.root.join("logs/standalone/prefix-setup.log"))?;
            self.wine_run(
                &["wineboot", "-u"],
                game,
                &log,
                cancelled,
                Some(Duration::from_secs(180)),
            )?;
            self.map("g", game)?;
            self.map("r", &self.root)?;
            let system32 = prefix.join("drive_c/windows/system32");
            for path in [
                prefix.join("drive_c"),
                prefix.join("drive_c/windows"),
                system32.clone(),
            ] {
                ensure!(
                    !path.is_symlink(),
                    "A symbolic link blocks safe prefix preparation"
                );
            }
            fs::create_dir_all(&system32)?;
            fs::copy(
                self.root.join("runtime/xgameruntime.dll.threading"),
                system32.join("xgameruntime.dll.threading"),
            )?;
            let registry = self
                .bundle
                .as_ref()
                .map(|bundle| bundle.join("scripts/winrt.reg"))
                .unwrap_or_else(|| self.root.join("src/winrt.reg"));
            self.wine_run(
                &[
                    "reg",
                    "import",
                    &format!("Z:{}", registry.to_string_lossy().replace('/', "\\")),
                ],
                game,
                &log,
                cancelled,
                Some(Duration::from_secs(60)),
            )?;
            self.wine_run(
                &[
                    "reg",
                    "add",
                    r"HKCU\Software\Wine",
                    "/v",
                    "Version",
                    "/d",
                    "win10",
                    "/f",
                ],
                game,
                &log,
                cancelled,
                Some(Duration::from_secs(60)),
            )?;
            self.stop_setup(cancelled)?;
            input::install(
                &prefix,
                &game.join("Installers/GameInputRedist.msi"),
                &self.root,
            )?;
            self.wine_run(
                &[
                    "reg",
                    "import",
                    r"R:\bottles\Bedrock-Standalone\.standalone-gameinput.reg",
                ],
                game,
                &log,
                cancelled,
                Some(Duration::from_secs(60)),
            )?;
            self.stop_setup(cancelled)?;
            ensure!(
                input::valid(&prefix)?,
                "GameInput failed verification after installation"
            );
            atomic(&prefix.join(".bedrock-setup.json"), &desired)?;
            Ok(())
        })();
        if result.is_err() {
            // Preparation acquired this idle prefix before it started Wine
            let cleanup = AtomicBool::new(false);
            self.stop_setup(&cleanup)?;
        }
        result
    }

    pub fn launch(&self, game: &Path, cancelled: &AtomicBool) -> Result<()> {
        self.prepare(game, cancelled)?;
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
        let log = private_log(
            &self
                .root
                .join(format!("logs/standalone/minecraft-{stamp}.log")),
        )?;
        let mut command = self.environment(self.wine().join("bin/wine"));
        command
            .arg(r"G:\Minecraft.Windows.exe")
            .current_dir(game)
            .stdout(log.try_clone()?)
            .stderr(log);
        run(
            &mut command,
            cancelled,
            None,
            Some(&|pid| {
                event(
                    json!({"state":"playing","title":"Minecraft is running","detail":"Quit Minecraft to return to the launcher","game_pid":pid}),
                )
            }),
        )
    }

    fn owners(&self) -> [(PathBuf, PathBuf); 2] {
        [
            (
                self.root.join("runtime/standalone/helper-session.json"),
                self.helper(),
            ),
            (
                self.root.join("runtime/helper-session.json"),
                self.root
                    .join("sources/xodus/target/release/examples/bedrock_helper"),
            ),
        ]
    }

    pub fn account_pid(&self) -> Option<u32> {
        for (state, expected) in self.owners() {
            let Ok(value) = read_json::<Value>(&state, 64 * 1024) else {
                continue;
            };
            let Some(pid) = value["pid"]
                .as_u64()
                .filter(|pid| *pid > 1 && *pid <= i32::MAX as u64)
            else {
                continue;
            };
            if value["executable"].as_str() != expected.to_str() {
                continue;
            }
            let Ok(output) = Command::new("/bin/ps")
                .args(["-p", &pid.to_string(), "-o", "comm="])
                .output()
            else {
                continue;
            };
            let path = PathBuf::from(String::from_utf8_lossy(&output.stdout).trim());
            let actual = if path.is_absolute() {
                path
            } else {
                self.root.join(path)
            };
            if actual
                .canonicalize()
                .ok()
                .is_some_and(|actual| expected.canonicalize().ok() == Some(actual))
            {
                return Some(pid as u32);
            }
        }
        None
    }

    pub fn ready(&self, owner: Option<&mut Child>) -> Result<bool> {
        if socket(Path::new(SOCKET))?.is_none() {
            return Ok(false);
        }
        let running = if let Some(owner) = owner {
            owner.try_wait()?.is_none()
        } else {
            self.account_pid().is_some()
        };
        ensure!(
            running,
            "An unrecognised account helper owns the socket; close it first"
        );
        Ok(true)
    }

    pub fn recover(&self) -> Result<()> {
        if self.account_pid().is_some() {
            return Ok(());
        }
        let mut dead = false;
        for (state, expected) in self.owners() {
            let Ok(value) = read_json::<Value>(&state, 64 * 1024) else {
                continue;
            };
            if value["executable"].as_str() != expected.to_str() {
                continue;
            }
            let Some(pid) = value["pid"]
                .as_u64()
                .filter(|pid| *pid > 1 && *pid <= i32::MAX as u64)
            else {
                continue;
            };
            // Signal zero checks only the recorded process; it never sends a signal
            if unsafe { libc::kill(pid as i32, 0) } == 0 {
                return Ok(());
            }
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH) {
                dead = true;
            }
        }
        if !dead {
            return Ok(());
        }
        recover_socket(Path::new(SOCKET))
    }
}

fn socket(path: &Path) -> Result<Option<fs::Metadata>> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    // getuid reads the current identity without changing privilege
    let uid = unsafe { libc::getuid() };
    ensure!(
        metadata.file_type().is_socket() && metadata.uid() == uid && metadata.mode() & 0o077 == 0,
        "The account socket has unexpected ownership or permissions"
    );
    Ok(Some(metadata))
}

// Call only after proving a recorded helper has exited
fn recover_socket(path: &Path) -> Result<()> {
    let Some(before) = socket(path).ok().flatten() else {
        return Ok(());
    };
    if UnixStream::connect(path)
        .is_err_and(|error| error.raw_os_error() == Some(libc::ECONNREFUSED))
        && let Ok(after) = fs::symlink_metadata(path)
        && before.dev() == after.dev()
        && before.ino() == after.ino()
    {
        fs::remove_file(path)?;
    }
    Ok(())
}

pub fn bridge(wine: &Path, dxmt: &Path, sources: &Path) -> Result<()> {
    let metadata: Value = read_json(&wine.join("dxmt-unix-bridge.json"), 64 * 1024)?;
    ensure!(
        metadata["version"] == "v0.80"
            && metadata["source_commit"] == "589adb780354b461645b29999cefaf533594ee99",
        "The rebuilt DXMT bridge has unexpected source metadata"
    );
    let files = metadata["files"]
        .as_object()
        .context("The graphics bridge file list is missing")?;
    ensure!(
        files.len() == 2
            && files.contains_key("winemetal.so")
            && files.contains_key("winemetal-upstream.so"),
        "The graphics bridge file list changed"
    );
    let upstream = metadata
        .get("packaged_upstream_sha256")
        .unwrap_or(&files["winemetal-upstream.so"]);
    ensure!(
        upstream.as_str() == Some(digest(&dxmt.join("x86_64-unix/winemetal.so"))?.as_str()),
        "The upstream graphics library changed"
    );
    for (key, path) in [
        (
            "patch_sha256",
            "vendor/patches/standalone-dxmt-memory-lifetime.patch",
        ),
        (
            "handoff_patch_sha256",
            "vendor/patches/standalone-dxmt-handoff.patch",
        ),
        (
            "trace_source_sha256",
            "tools/probes/standalone-dxmt-display-trace.c",
        ),
    ] {
        if key == "handoff_patch_sha256" && metadata.get(key).is_none() {
            continue;
        }
        ensure!(
            metadata[key].as_str() == Some(digest(&sources.join(path))?.as_str()),
            "The graphics bridge source failed verification"
        );
    }
    for (name, expected) in files {
        ensure!(
            expected.as_str()
                == Some(digest(&wine.join("lib/wine/x86_64-unix").join(name))?.as_str()),
            "The installed graphics bridge failed verification"
        );
    }
    Ok(())
}

pub fn clean(program: impl AsRef<std::ffi::OsStr>) -> Command {
    let mut command = Command::new(program);
    command
        .env_clear()
        .envs(std::env::vars_os().filter(|(key, _)| {
            !["CX_", "WINE", "DYLD_"]
                .iter()
                .any(|prefix| key.to_string_lossy().starts_with(prefix))
        }));
    command
}

pub fn private_log(path: &Path) -> Result<File> {
    fs::create_dir_all(path.parent().context("Missing log directory")?)?;
    ensure!(!path.is_symlink(), "A symbolic link blocks the setup log");
    Ok(OpenOptions::new()
        .create(true)
        .append(true)
        .read(true)
        .mode(0o600)
        .open(path)?)
}

pub fn wait(child: &mut Child, duration: Duration) -> Result<bool> {
    let deadline = Instant::now() + duration;
    loop {
        if child.try_wait()?.is_some() {
            return Ok(true);
        }
        if Instant::now() >= deadline {
            return Ok(false);
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

struct Group(Child);

impl Drop for Group {
    fn drop(&mut self) {
        if self.0.try_wait().ok().flatten().is_none() {
            // The unreaped child remains the leader of our newly created process group
            unsafe {
                libc::kill(-(self.0.id() as i32), libc::SIGTERM);
            }
            if !wait(&mut self.0, Duration::from_secs(5)).unwrap_or(false) {
                unsafe {
                    libc::kill(-(self.0.id() as i32), libc::SIGKILL);
                }
                let _ = self.0.wait();
            }
        }
    }
}

pub fn run(
    command: &mut Command,
    cancelled: &AtomicBool,
    timeout: Option<Duration>,
    started: Option<&dyn Fn(u32)>,
) -> Result<()> {
    let mut child = Group(command.process_group(0).spawn()?);
    if let Some(started) = started {
        started(child.0.id());
    }
    let begin = Instant::now();
    loop {
        if let Some(status) = child.0.try_wait()? {
            ensure!(
                status.success(),
                "Minecraft preparation stopped with {status}"
            );
            return Ok(());
        }
        if cancelled.load(Ordering::Relaxed)
            || timeout.is_some_and(|duration| begin.elapsed() >= duration)
        {
            // The live child is the leader of the process group created above
            unsafe {
                libc::kill(-(child.0.id() as i32), libc::SIGTERM);
            }
            if !wait(&mut child.0, Duration::from_secs(10))? {
                unsafe {
                    libc::kill(-(child.0.id() as i32), libc::SIGKILL);
                }
                child.0.wait()?;
            }
            bail!(if cancelled.load(Ordering::Relaxed) {
                "Setup was cancelled"
            } else {
                "Minecraft preparation took too long"
            });
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

pub struct Account<'a> {
    context: &'a Context,
    child: Option<Child>,
    output: Option<File>,
    buffer: Vec<u8>,
    failure: Option<String>,
}

impl<'a> Account<'a> {
    pub fn start(
        context: &'a Context,
        game: &Path,
        download: bool,
        market: &str,
        cancelled: &AtomicBool,
    ) -> Result<Self> {
        context.recover()?;
        let mut account = Self {
            context,
            child: None,
            output: None,
            buffer: Vec::new(),
            failure: None,
        };
        if !context.ready(None)? && context.account_pid().is_none() {
            let log_path = context.root.join("logs/standalone/account.log");
            let mut log = private_log(&log_path)?;
            let offset = log.seek(SeekFrom::End(0))?;
            let mut command = clean(context.helper().canonicalize()?);
            command
                .arg(if download { "--download" } else { "--serve" })
                .arg(game)
                .args(["--market", market]);
            if download {
                command.arg("--serve-after");
            }
            let child = command
                .current_dir(&context.root)
                .env("XODUS_LOG", "off")
                .env("RUST_LOG", "off")
                .stdout(log.try_clone()?)
                .stderr(log)
                .spawn()?;
            let pid = child.id();
            account.child = Some(child);
            let state = &context.owners()[0].0;
            fs::create_dir_all(state.parent().context("Missing account state directory")?)?;
            atomic(state, &json!({"pid":pid,"executable":context.helper()}))?;
            let mut output = File::open(log_path)?;
            output.seek(SeekFrom::Start(offset))?;
            account.output = Some(output);
        }
        let deadline = Instant::now() + Duration::from_secs(if download { 7200 } else { 900 });
        loop {
            ensure!(!cancelled.load(Ordering::Relaxed), "Sign-in was cancelled");
            account.progress()?;
            if context.ready(account.child.as_mut())? {
                return Ok(account);
            }
            let stopped = if let Some(child) = &mut account.child {
                child.try_wait()?.is_some()
            } else {
                context.account_pid().is_none()
            };
            if stopped {
                account.progress()?;
                bail!(
                    "{}",
                    account
                        .failure
                        .as_deref()
                        .unwrap_or("The account helper stopped; open the setup log for details")
                );
            }
            ensure!(
                Instant::now() < deadline,
                "Sign-in took too long; check your connection and try again"
            );
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    fn progress(&mut self) -> Result<()> {
        let Some(output) = &mut self.output else {
            return Ok(());
        };
        let mut bytes = [0; 65536];
        loop {
            let count = output.read(&mut bytes)?;
            if count == 0 {
                break;
            }
            self.buffer.extend_from_slice(&bytes[..count]);
            ensure!(
                self.buffer.len() <= 1024 * 1024,
                "The account helper returned an oversized status"
            );
        }
        while let Some(end) = self.buffer.iter().position(|&byte| byte == b'\n') {
            let bytes: Vec<_> = self.buffer.drain(..=end).collect();
            if let Some(code) = bytes.strip_prefix(b"BEDROCK_ERROR:") {
                self.failure = Some(account_error(String::from_utf8_lossy(code).trim()).into());
            } else if bytes.starts_with(b"Keychain: requesting saved sign-in entry") {
                status(
                    "busy",
                    "Signing you in",
                    "Allow access to your saved sign-in in the macOS prompt",
                    Some(0.2),
                );
            } else if bytes.starts_with(b"Finding the Windows package") {
                status("busy", "Checking your Minecraft purchase", "", Some(0.3));
            } else if bytes.starts_with(b"Downloading Minecraft ") {
                status(
                    "busy",
                    "Downloading Minecraft",
                    "Keep this app open",
                    Some(0.35),
                );
            } else if let Some(line) = bytes
                .strip_prefix(b"Downloaded ")
                .and_then(|line| line.strip_suffix(b" files.\n"))
                && let Some((done, total)) = String::from_utf8_lossy(line).split_once('/')
                && let (Ok(done), Ok(total)) = (done.parse::<u64>(), total.parse::<u64>())
                && total > 0
                && done <= total
            {
                status(
                    "busy",
                    "Downloading Minecraft",
                    &format!("{}%", done * 100 / total),
                    Some(0.35 + 0.5 * done as f64 / total as f64),
                );
            }
        }
        Ok(())
    }
}

impl Drop for Account<'_> {
    fn drop(&mut self) {
        if let Some(child) = &mut self.child {
            if child.try_wait().ok().flatten().is_none() {
                // This unreaped child belongs to this account session
                unsafe {
                    libc::kill(child.id() as i32, libc::SIGINT);
                }
                if !wait(child, Duration::from_secs(8)).unwrap_or(false) {
                    let _ = child.kill();
                    let _ = child.wait();
                }
            }
            let pid = child.id();
            let _ = self.context.recover();
            let state = &self.context.owners()[0].0;
            if fs::symlink_metadata(SOCKET).is_err()
                && read_json::<Value>(state, 64 * 1024)
                    .ok()
                    .and_then(|value| value["pid"].as_u64())
                    == Some(pid as u64)
            {
                let _ = fs::remove_file(state);
            }
        }
    }
}

pub fn status(state: &str, title: &str, detail: &str, progress: Option<f64>) {
    event(json!({"state":state,"title":title,"detail":detail,"progress":progress}));
}

fn account_error(code: &str) -> &'static str {
    match code {
        "account_timeout" => "Sign-in took too long; check your connection and try again",
        "signin_cancelled" => "Sign-in was closed; try again when you’re ready",
        "keychain_access" => {
            "Allow access to your saved sign-in in the macOS Keychain prompt, then retry"
        }
        "content_license" => {
            "Microsoft could not verify a Minecraft for Windows licence for this account"
        }
        "package_connection" => {
            "Could not connect to Microsoft’s game download; check your connection and retry"
        }
        "package_size" | "package_cache" | "package_format" | "package_files"
        | "package_segments" | "package_filesystem" => {
            "Minecraft’s download could not be verified; existing files were kept"
        }
        _ => "Microsoft sign-in did not finish; open the setup log for details and try again",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::net::UnixListener;
    #[test]
    fn socket_recovery_keeps_live_and_untrusted_endpoints() -> Result<()> {
        let root = tempfile::tempdir()?;
        let path = root.path().join("account.sock");
        let listener = UnixListener::bind(&path)?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
        assert!(socket(&path)?.is_some());
        recover_socket(&path)?;
        assert!(path.exists());
        let alias = root.path().join("alias.sock");
        symlink(&path, &alias)?;
        assert!(socket(&alias).is_err());
        recover_socket(&alias)?;
        assert!(alias.is_symlink());
        fs::set_permissions(&path, fs::Permissions::from_mode(0o666))?;
        assert!(socket(&path).is_err());
        recover_socket(&path)?;
        assert!(path.exists());
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
        drop(listener);
        recover_socket(&path)?;
        assert!(!path.exists());
        Ok(())
    }
    #[test]
    fn existing_drive_mapping_is_never_repointed() -> Result<()> {
        let root = tempfile::tempdir()?;
        let context = Context {
            root: root.path().into(),
            bundle: None,
        };
        fs::create_dir_all(context.prefix().join("dosdevices"))?;
        fs::create_dir(root.path().join("worlds"))?;
        fs::create_dir(root.path().join("other"))?;
        context.map("g", &root.path().join("worlds"))?;
        context.map("g", &root.path().join("worlds"))?;
        assert!(context.map("g", &root.path().join("other")).is_err());
        assert_eq!(
            context.prefix().join("dosdevices/g:").canonicalize()?,
            root.path().join("worlds").canonicalize()?
        );
        Ok(())
    }
    #[test]
    fn cancellation_and_timeout_reap_owned_processes() -> Result<()> {
        let cancelled = AtomicBool::new(true);
        let mut pid = 0;
        let cell = std::cell::Cell::new(0);
        assert!(
            run(
                Command::new("/bin/sh").args(["-c", "exec sleep 30"]),
                &cancelled,
                None,
                Some(&|value| cell.set(value))
            )
            .is_err()
        );
        pid += cell.get();
        assert!(pid > 1);
        // Signal zero verifies that the just-reaped fixture process no longer exists
        assert_eq!(unsafe { libc::kill(pid as i32, 0) }, -1);
        let error = run(
            Command::new("/bin/sh").args(["-c", "exec sleep 30"]),
            &AtomicBool::new(false),
            Some(Duration::from_millis(30)),
            None,
        )
        .expect_err("Expected fixture timeout");
        assert!(error.to_string().contains("too long"));
        Ok(())
    }
    #[test]
    fn status_and_error_mapping_never_echo_helper_text() {
        for code in [
            "secret token from helper",
            "https://private.example/?key=secret",
            "signin_failed",
        ] {
            assert!(!account_error(code).contains(code));
        }
        assert!(account_error("content_license").contains("licence"));
        let command = clean("/usr/bin/true");
        assert!(command.get_envs().all(|(name, _)| {
            !["WINE", "DYLD_", "CX_"]
                .iter()
                .any(|prefix| name.to_string_lossy().starts_with(prefix))
        }));
    }
}
