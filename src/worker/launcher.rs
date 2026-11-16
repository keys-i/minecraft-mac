use crate::session::{Account, Context, clean, run as execute, status};
use crate::threading;
use anyhow::{Context as _, Result, ensure};
use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::sync::atomic::AtomicBool;
use std::time::Duration;

pub fn game_running() -> Result<bool> {
    let output = clean("/bin/ps").args(["-axo", "comm="]).output()?;
    ensure!(output.status.success(), "Couldn’t check the running game");
    Ok(String::from_utf8_lossy(&output.stdout).lines().any(|line| {
        line.trim()
            .to_lowercase()
            .ends_with("/minecraft.windows.exe")
            || line
                .trim()
                .to_lowercase()
                .ends_with("\\minecraft.windows.exe")
    }))
}

fn version(text: &str) -> Result<Vec<u32>> {
    Ok(text
        .trim()
        .split('.')
        .map(str::parse)
        .collect::<std::result::Result<Vec<_>, _>>()?)
}

fn validate(context: &Context, cancelled: &AtomicBool) -> Result<()> {
    let minimum = if let Some(bundle) = &context.bundle {
        let plist = plist::Value::from_file(
            bundle
                .parent()
                .context("Missing application directory")?
                .join("Info.plist"),
        )?;
        plist
            .as_dictionary()
            .and_then(|info| info.get("LSMinimumSystemVersion"))
            .and_then(plist::Value::as_string)
            .unwrap_or("15.0")
            .to_owned()
    } else {
        "15.0".into()
    };
    let output = clean("/usr/bin/sw_vers").arg("-productVersion").output()?;
    ensure!(
        std::env::consts::ARCH == "aarch64"
            && version(&String::from_utf8_lossy(&output.stdout))? >= version(&minimum)?,
        "This build requires an Apple Silicon Mac with macOS {minimum} or later"
    );
    execute(clean("/usr/bin/arch").args(["-x86_64","/usr/bin/true"]),cancelled,Some(Duration::from_secs(10)),None)
        .context("Rosetta is required to run Minecraft; see Minecraft Launcher Help for Apple’s setup instructions")?;
    ensure!(
        context.wine().join("build-manifest.json").is_file()
            && context.dxmt().join("manifest.json").is_file()
            && context.helper().is_file(),
        "This app is missing its bundled runtime; use a complete build of Minecraft Launcher"
    );
    ensure!(
        context.game().join("Minecraft.Windows.exe").is_file()
            || threading::space(&context.root)? >= 8 * 1024 * 1024 * 1024,
        "Free up at least 8 GB for Minecraft, then try again"
    );
    Ok(())
}

pub fn game_valid(game: &Path) -> Result<bool> {
    let mut bytes = Vec::new();
    use std::io::Read;
    let mut executable = match fs::File::open(game.join("Minecraft.Windows.exe")) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    let size = executable.metadata()?.len();
    if size < 64 {
        return Ok(false);
    }
    let mut dos = [0; 64];
    executable.read_exact(&mut dos)?;
    if !dos.starts_with(b"MZ") {
        return Ok(false);
    }
    let offset = u32::from_le_bytes(dos[60..64].try_into()?);
    if u64::from(offset).saturating_add(6) > size {
        return Ok(false);
    }
    use std::io::Seek;
    executable.seek(std::io::SeekFrom::Start(offset as u64))?;
    let mut pe = [0; 6];
    executable.read_exact(&mut pe)?;
    if pe != *b"PE\0\0\x64\x86" {
        return Ok(false);
    }
    let config = match fs::File::open(game.join("MicrosoftGame.Config")) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    config.take(4 * 1024 * 1024 + 1).read_to_end(&mut bytes)?;
    ensure!(
        bytes.len() <= 4 * 1024 * 1024,
        "The game configuration is larger than expected"
    );
    let Ok(text) = std::str::from_utf8(&bytes) else {
        return Ok(false);
    };
    let Ok(document) = roxmltree::Document::parse(text) else {
        return Ok(false);
    };
    let product = document
        .descendants()
        .find(|node| node.has_tag_name("StoreId"))
        .and_then(|node| node.text())
        .map(str::trim);
    Ok(product == Some("9NBLGGH2JHXJ")
        && game.join(".xodus-streaming.msixvc").is_file()
        && game.join("Installers/GameInputRedist.msi").is_file())
}

pub fn run(args: Vec<OsString>, cancelled: &AtomicBool) -> Result<()> {
    ensure!(
        args.len() <= 1
            && args
                .first()
                .is_none_or(|arg| ["--status", "--warmup", "--sign-out"]
                    .iter()
                    .any(|flag| arg == flag)),
        "Unknown launcher argument"
    );
    let context = Context::load()?;
    if context
        .bundle
        .as_ref()
        .is_some_and(|bundle| bundle.join("preview.json").is_file())
    {
        return crate::preview::run(&args, cancelled);
    }
    let command = args.first().and_then(|arg| arg.to_str()).unwrap_or("");
    if command == "--status" {
        let ready = context.installed();
        status(
            if ready { "ready" } else { "new" },
            if ready {
                "Ready to play"
            } else {
                "Minecraft on your Mac"
            },
            "",
            None,
        );
        return Ok(());
    }
    fs::create_dir_all(context.root.join("logs/standalone"))?;
    let lock = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(context.root.join("logs/standalone/onboarding.lock"))?;
    lock.try_lock()
        .context("Setup or Minecraft is already running; return to the other launcher window")?;
    ensure!(
        !game_running()?,
        "Minecraft is already running; return to Minecraft and quit it before starting another session"
    );
    let _prefix = crate::setup::lock(&context.root, "launcher.lock")?;
    context.initialise()?;
    let game = context.game();
    let ready = context.installed();
    if command == "--warmup" {
        if game.join("Minecraft.Windows.exe").is_file() {
            validate(&context, cancelled)?;
            status(
                "busy",
                "Getting Minecraft ready",
                "Preparing your installed game",
                Some(0.95),
            );
            context.prepare(&game, cancelled)?;
        }
        let ready = context.installed();
        status(
            if ready { "ready" } else { "new" },
            if ready {
                "Ready to play"
            } else {
                "Minecraft on your Mac"
            },
            "",
            None,
        );
        return Ok(());
    }
    if command == "--sign-out" {
        status("busy", "Signing out", "", None);
        let log =
            crate::session::private_log(&context.root.join("logs/standalone/onboarding.log"))?;
        execute(
            clean(context.helper().canonicalize()?)
                .arg("--sign-out")
                .arg(&game)
                .current_dir(&context.root)
                .stdout(log.try_clone()?)
                .stderr(log),
            cancelled,
            None,
            None,
        )?;
        status(
            if ready { "ready" } else { "new" },
            "Signed out",
            "Choose Play to sign in with another Microsoft account",
            None,
        );
        return Ok(());
    }
    validate(&context, cancelled)?;
    ensure!(
        !game.is_symlink() && (!game.exists() || game_valid(&game)?),
        "The existing game installation is incomplete; your files were kept, see Minecraft Launcher Help for recovery steps"
    );
    status(
        "busy",
        if ready {
            "Signing you in"
        } else {
            "Sign in to Microsoft"
        },
        if ready {
            ""
        } else {
            "Use the account that owns Minecraft for Windows"
        },
        Some(0.2),
    );
    let _account = Account::start(&context, &game, true, "CA", cancelled)?;
    if !ready {
        ensure!(
            game_valid(&game)?,
            "The downloaded game did not pass the Windows installation check"
        );
        status(
            "busy",
            "Preparing Minecraft",
            "Checking the required Microsoft game component",
            Some(0.9),
        );
        threading::acquire(&context, cancelled)?;
        status("busy", "Finishing setup", "", Some(0.95));
        context.prepare(&game, cancelled)?;
    }
    status(
        "busy",
        "Opening Minecraft",
        "Starting your game",
        Some(0.99),
    );
    context.launch(&game, cancelled)?;
    status("ready", "Ready to play", "", None);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compares_macos_versions_numerically() {
        assert!(version("15.0").unwrap() < version("27.0.1").unwrap());
        assert!(version("15.9").unwrap() < version("15.10").unwrap());
        assert!(version("27.bad").is_err());
    }
    #[test]
    fn malformed_game_is_preserved_and_never_reported_ready() -> Result<()> {
        let root = tempfile::tempdir()?;
        assert!(!game_valid(root.path())?);
        let executable = root.path().join("Minecraft.Windows.exe");
        fs::write(&executable, b"MZ")?;
        assert!(!game_valid(root.path())?);
        let mut bytes = vec![0; 80];
        bytes[..2].copy_from_slice(b"MZ");
        bytes[60..64].copy_from_slice(&64_u32.to_le_bytes());
        bytes[64..70].copy_from_slice(b"PE\0\0\x64\x86");
        fs::write(&executable, &bytes)?;
        assert!(!game_valid(root.path())?);
        fs::write(root.path().join("MicrosoftGame.Config"), "<broken>")?;
        assert!(!game_valid(root.path())?);
        fs::write(
            root.path().join("MicrosoftGame.Config"),
            "<Game><StoreId>9NBLGGH2JHXJ</StoreId></Game>",
        )?;
        fs::write(root.path().join(".xodus-streaming.msixvc"), b"fixture")?;
        fs::create_dir(root.path().join("Installers"))?;
        fs::write(
            root.path().join("Installers/GameInputRedist.msi"),
            b"fixture",
        )?;
        assert!(game_valid(root.path())?);
        assert_eq!(fs::read(executable)?, bytes);
        Ok(())
    }
}
