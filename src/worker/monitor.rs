use crate::{
    atomic, cli, read_json,
    session::{self, Context},
    setup,
};
use anyhow::{Context as _, Result, bail, ensure};
use serde_json::{Value, json};
use std::collections::{BTreeMap, VecDeque};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
fn stamp() -> String {
    format!("{}-{}", (now() * 1_000_000.0) as u64, std::process::id())
}
fn data(context: &Context) -> PathBuf {
    context.root.join("logs/standalone/monitor")
}

fn append(path: &Path, value: &Value) -> Result<()> {
    let mut file = session::private_log(path)?;
    file.lock()?;
    writeln!(file, "{value}")?;
    Ok(())
}
fn event(context: &Context, kind: &str, message: &str, details: Value) -> Result<Value> {
    let mut value = json!({"time":now(),"id":stamp(),"kind":kind,"message":message});
    if let Some(details) = details.as_object() {
        value
            .as_object_mut()
            .context("Missing event")?
            .extend(details.clone());
    }
    append(&data(context).join("events.jsonl"), &value)?;
    Ok(value)
}

fn output(args: &[&str]) -> Result<String> {
    let result = Command::new(args[0]).args(&args[1..]).output()?;
    ensure!(
        result.status.success(),
        "Diagnostic command failed: {}",
        args[0]
    );
    ensure!(
        result.stdout.len() <= 4 * 1024 * 1024,
        "Oversized diagnostic result"
    );
    Ok(String::from_utf8_lossy(&result.stdout).trim().into())
}

#[cfg(target_os = "macos")]
fn usage(pid: u32) -> Result<Value> {
    let mut value = std::mem::MaybeUninit::<libc::rusage_info_v2>::uninit();
    // The SDK function fills exactly rusage_info_v2 for flavor 2
    ensure!(
        unsafe { libc::proc_pid_rusage(pid as i32, 2, value.as_mut_ptr().cast()) } == 0,
        "Couldn’t inspect process memory"
    );
    let value = unsafe { value.assume_init() };
    Ok(
        json!({"birth":value.ri_proc_start_abstime,"rss_bytes":value.ri_resident_size,"footprint_bytes":value.ri_phys_footprint,"pageins":value.ri_pageins,"read_bytes":value.ri_diskio_bytesread,"written_bytes":value.ri_diskio_byteswritten}),
    )
}
#[cfg(not(target_os = "macos"))]
fn usage(_: u32) -> Result<Value> {
    bail!("Process monitoring requires macOS");
}

fn same(pid: u32, birth: u64) -> bool {
    usage(pid).ok().is_some_and(|value| value["birth"] == birth)
}
fn owned(context: &Context, pid: u32) -> bool {
    output(&[
        "/usr/sbin/lsof",
        "-a",
        "-p",
        &pid.to_string(),
        "-d",
        "txt",
        "-Fn",
    ])
    .ok()
    .is_some_and(|text| {
        text.lines()
            .any(|line| line.starts_with(&format!("n{}/", context.wine().display())))
    })
}
fn alive(_context: &Context, state: &Value) -> bool {
    let Some(pid) = state["monitor_pid"]
        .as_u64()
        .filter(|pid| *pid > 1 && *pid <= i32::MAX as u64)
    else {
        return false;
    };
    let Some(birth) = state["monitor_birth"].as_u64() else {
        return false;
    };
    same(pid as u32, birth)
        && output(&["/bin/ps", "-p", &pid.to_string(), "-o", "args="])
            .ok()
            .is_some_and(|args| {
                std::env::current_exe()
                    .ok()
                    .is_some_and(|exe| args.starts_with(exe.to_string_lossy().as_ref()))
                    && args.split_whitespace().any(|arg| arg == "watch")
            })
}

fn memory() -> Value {
    let mut value = json!({});
    if let Ok(text) = output(&[
        "/usr/sbin/sysctl",
        "-n",
        "kern.memorystatus_vm_pressure_level",
    ]) && let Ok(number) = text.parse::<u32>()
    {
        value["pressure_level"] = number.into();
    }
    if let Ok(text) = output(&["/usr/sbin/sysctl", "-n", "vm.swapusage"])
        && let Some(number) = text
            .split("used = ")
            .nth(1)
            .and_then(|part| part.split('M').next())
            .and_then(|part| part.parse::<f64>().ok())
    {
        value["swap_used_bytes"] = ((number * 1024.0 * 1024.0) as u64).into();
    }
    if let Ok(text) = output(&["/usr/bin/vm_stat"]) {
        let page = text
            .split("page size of ")
            .nth(1)
            .and_then(|part| part.split(' ').next())
            .and_then(|part| part.parse::<u64>().ok())
            .unwrap_or(16384);
        for (name, label) in [
            ("compressed_bytes", "Pages occupied by compressor"),
            ("swapins", "Swapins"),
            ("swapouts", "Swapouts"),
        ] {
            if let Some(number) = text.lines().find_map(|line| {
                line.strip_prefix(&format!("{label}:"))
                    .and_then(|tail| tail.trim().trim_end_matches('.').parse::<u64>().ok())
            }) {
                value[name] = (number * if name.ends_with("bytes") { page } else { 1 }).into();
            }
        }
    }
    value
}

fn warnings(history: &VecDeque<Value>, sample: &Value) -> Vec<(&'static str, &'static str)> {
    let mut reasons = Vec::new();
    let footprint = sample["footprint_bytes"].as_u64().unwrap_or(0);
    if footprint >= 10 * 1024 * 1024 * 1024 {
        reasons.push((
            "urgent-memory",
            "Game memory is above 10 GB; save and close Minecraft soon",
        ));
    } else if footprint >= 6 * 1024 * 1024 * 1024 {
        reasons.push((
            "high-memory",
            "Game memory is above 6 GB; save your progress",
        ));
    }
    if matches!(sample["system"]["pressure_level"].as_u64(), Some(2 | 4)) {
        reasons.push((
            "system-pressure",
            "macOS reports memory pressure; save your progress",
        ));
    }
    let time = sample["monotonic"].as_f64().unwrap_or(0.0);
    if sample["session_seconds"].as_f64().unwrap_or(0.0) >= 780.0
        && history
            .iter()
            .rev()
            .find(|item| {
                (480.0..=660.0).contains(&(time - item["monotonic"].as_f64().unwrap_or(time)))
            })
            .is_some_and(|item| {
                footprint.saturating_sub(item["footprint_bytes"].as_u64().unwrap_or(footprint))
                    >= 512 * 1024 * 1024
            })
    {
        reasons.push((
            "memory-growth",
            "Game memory grew by at least 512 MB over about ten minutes",
        ));
    }
    reasons
}

fn notify(message: &str) {
    let _ = Command::new("/usr/bin/osascript").args(["-e","on run argv\ndisplay notification (item 1 of argv) with title \"Minecraft monitor\"\nend run",message]).stdout(Stdio::null()).stderr(Stdio::null()).status();
}

fn capture(
    context: &Context,
    reason: &str,
    games: &[Value],
    cancelled: &AtomicBool,
) -> Result<PathBuf> {
    let directory = data(context).join("incidents").join(stamp());
    fs::create_dir_all(&directory)?;
    let mut records = Vec::new();
    for game in games {
        let (Some(pid), Some(birth)) = (game["pid"].as_u64(), game["birth"].as_u64()) else {
            continue;
        };
        if pid > i32::MAX as u64 || !same(pid as u32, birth) || !owned(context, pid as u32) {
            continue;
        }
        for (name, args) in [
            (
                "memory",
                vec!["/usr/bin/vmmap".into(), "-summary".into(), pid.to_string()],
            ),
            (
                "threads",
                vec![
                    "/usr/bin/sample".into(),
                    pid.to_string(),
                    "1".into(),
                    "10".into(),
                    "-file".into(),
                    directory
                        .join(format!("{pid}-threads.txt"))
                        .to_string_lossy()
                        .into_owned(),
                ],
            ),
        ] {
            let path = directory.join(format!("{pid}-{name}-command.txt"));
            let log = session::private_log(&path)?;
            let result = session::run(
                Command::new(&args[0])
                    .args(&args[1..])
                    .stdout(log.try_clone()?)
                    .stderr(log),
                cancelled,
                Some(Duration::from_secs(12)),
                None,
            );
            records.push(json!({"path":path,"error":result.err().map(|error| error.to_string())}));
        }
    }
    atomic(
        &directory.join("incident.json"),
        &json!({"time":now(),"reason":reason,"processes":games,"system":memory(),"diagnostics":records}),
    )?;
    Ok(directory)
}

struct Session {
    path: PathBuf,
    history: VecDeque<Value>,
    started: Instant,
    wall: f64,
    peak: u64,
}

fn games(context: &Context, known: &BTreeMap<(u32, u64), Session>) -> Result<Vec<Value>> {
    let text = output(&["/bin/ps", "-axo", "pid=,pcpu=,comm="])?;
    let mut games = Vec::new();
    for line in text.lines() {
        let mut fields = line.split_whitespace();
        let (Some(pid), Some(cpu)) = (fields.next(), fields.next()) else {
            continue;
        };
        let command = fields.collect::<Vec<_>>().join(" ").to_lowercase();
        if !command.ends_with("\\minecraft.windows.exe")
            && !command.ends_with("/minecraft.windows.exe")
        {
            continue;
        }
        let pid = pid.parse::<u32>()?;
        let Ok(mut value) = usage(pid) else {
            continue;
        };
        let Some(birth) = value["birth"].as_u64() else {
            continue;
        };
        if !known.contains_key(&(pid, birth)) && !owned(context, pid) {
            continue;
        }
        value["pid"] = pid.into();
        value["cpu_percent"] = cpu.parse::<f64>()?.into();
        games.push(value);
    }
    Ok(games)
}

fn crashes(pid: u32, since: f64) -> Result<Vec<PathBuf>> {
    let home = std::env::var_os("HOME").context("Missing home directory")?;
    let directory = Path::new(&home).join("Library/Logs/DiagnosticReports");
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let pattern = regex::Regex::new(&format!(r#""pid"\s*:\s*{pid}\b"#))?;
    let mut result = Vec::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().is_none_or(|ext| ext != "ips") || !entry.file_type()?.is_file() {
            continue;
        }
        if entry
            .metadata()?
            .modified()?
            .duration_since(UNIX_EPOCH)?
            .as_secs_f64()
            < since
        {
            continue;
        }
        let mut bytes = Vec::new();
        File::open(&path)?.take(65536).read_to_end(&mut bytes)?;
        if pattern.is_match(&String::from_utf8_lossy(&bytes)) {
            result.push(path);
        }
    }
    Ok(result)
}

fn watch(context: &Context, cancelled: &AtomicBool) -> Result<()> {
    let directory = data(context);
    fs::create_dir_all(&directory)?;
    let lock = session::private_log(&directory.join("monitor.lock"))?;
    if lock.try_lock().is_err() {
        return Ok(());
    }
    // Monitoring yields CPU priority and never signals a game process
    unsafe {
        libc::nice(10);
    }
    let birth = usage(std::process::id())?["birth"].clone();
    let started = Instant::now();
    let mut state = json!({"monitor_pid":std::process::id(),"monitor_birth":birth,"started_at":now(),"interval_seconds":10,"status":"waiting","games":[],"warning_bytes":6_u64*1024*1024*1024,"urgent_bytes":10_u64*1024*1024*1024});
    let mut sessions = BTreeMap::<(u32, u64), Session>::new();
    let mut recent = BTreeMap::new();
    let mut exits = Vec::new();
    let mut pressure = 0;
    event(
        context,
        "monitor-started",
        "Background sampling started",
        json!({}),
    )?;
    let result = (|| -> Result<()> {
        while !cancelled.load(Ordering::Relaxed) {
            let sample = (|| -> Result<()> {
                let mut found = games(context, &sessions)?;
                let system = memory();
                pressure = if matches!(system["pressure_level"].as_u64(), Some(2 | 4)) {
                    pressure + 1
                } else {
                    0
                };
                let ended: Vec<_> = sessions
                    .keys()
                    .filter(|&&(pid, birth)| {
                        !found
                            .iter()
                            .any(|game| game["pid"] == pid && game["birth"] == birth)
                    })
                    .copied()
                    .collect();
                for key in ended {
                    let session = sessions.remove(&key).context("Missing ended session")?;
                    event(
                        context,
                        "game-ended",
                        "The game process exited",
                        json!({"pid":key.0,"samples":session.path}),
                    )?;
                    exits.push((key.0, session.wall, Instant::now()));
                }
                let mut remaining = Vec::new();
                for (pid, since, ended) in exits.drain(..) {
                    let reports = crashes(pid, since)?;
                    if !reports.is_empty() {
                        event(
                            context,
                            "crash",
                            "macOS recorded a game crash",
                            json!({"pid":pid,"crash_reports":reports}),
                        )?;
                        notify("macOS recorded a Minecraft crash");
                    } else if ended.elapsed() < Duration::from_secs(120) {
                        remaining.push((pid, since, ended));
                    }
                }
                exits = remaining;
                for game in &mut found {
                    let key = (
                        game["pid"].as_u64().context("Missing game PID")? as u32,
                        game["birth"].as_u64().context("Missing game birth")?,
                    );
                    let session = sessions.entry(key).or_insert_with(|| Session {
                        path: directory.join("sessions").join(format!(
                            "{}-{}.jsonl",
                            stamp(),
                            key.0
                        )),
                        history: VecDeque::with_capacity(90),
                        started: Instant::now(),
                        wall: now(),
                        peak: 0,
                    });
                    let mut sample = game.clone();
                    sample["time"] = now().into();
                    sample["monotonic"] = started.elapsed().as_secs_f64().into();
                    sample["session_seconds"] = session.started.elapsed().as_secs_f64().into();
                    sample["system"] = system.clone();
                    append(&session.path, &sample)?;
                    for (kind, message) in warnings(&session.history, &sample) {
                        if kind == "system-pressure" && pressure < 3 {
                            continue;
                        }
                        let alert = (key, kind);
                        if recent
                            .get(&alert)
                            .is_some_and(|time: &Instant| time.elapsed() < Duration::from_secs(600))
                        {
                            continue;
                        }
                        recent.insert(alert, Instant::now());
                        notify(message);
                        let incident =
                            capture(context, message, std::slice::from_ref(game), cancelled)?;
                        event(
                            context,
                            kind,
                            message,
                            json!({"pid":key.0,"footprint_bytes":game["footprint_bytes"],"incident":incident}),
                        )?;
                    }
                    if session.history.len() == 90 {
                        session.history.pop_front();
                    }
                    session.history.push_back(sample);
                    session.peak = session
                        .peak
                        .max(game["footprint_bytes"].as_u64().unwrap_or(0));
                    game["peak_footprint_bytes"] = session.peak.into();
                    game["samples"] = session.path.to_string_lossy().into_owned().into();
                }
                state["status"] = if found.is_empty() {
                    "waiting"
                } else {
                    "playing"
                }
                .into();
                state["games"] = found.into();
                state["system"] = system;
                state["last_error"] = Value::Null;
                Ok(())
            })();
            if let Err(error) = sample {
                state["status"] = "monitor-error".into();
                state["last_error"] = error.to_string().into();
            }
            state["updated_at"] = now().into();
            atomic(&directory.join("latest.json"), &state)?;
            for _ in 0..40 {
                if cancelled.load(Ordering::Relaxed) {
                    break;
                }
                std::thread::sleep(Duration::from_millis(250));
            }
        }
        Ok(())
    })();
    state["status"] = "stopped".into();
    state["games"] = json!([]);
    state["updated_at"] = now().into();
    atomic(&directory.join("latest.json"), &state)?;
    event(
        context,
        "monitor-stopped",
        "Background sampling stopped",
        json!({}),
    )?;
    result
}

fn start(context: &Context) -> Result<()> {
    let latest = data(context).join("latest.json");
    let state = read_json::<Value>(&latest, 1024 * 1024).unwrap_or(Value::Null);
    if alive(context, &state) {
        return Ok(());
    }
    let log = session::private_log(&data(context).join("background.log"))?;
    let mut child = Command::new(std::env::current_exe()?)
        .args(["monitor", "watch"])
        .env("BEDROCK_HOME", &context.root)
        .current_dir(&context.root)
        .stdout(log.try_clone()?)
        .stderr(log)
        .stdin(Stdio::null())
        .process_group(0)
        .spawn()?;
    for _ in 0..40 {
        if alive(
            context,
            &read_json::<Value>(&latest, 1024 * 1024).unwrap_or(Value::Null),
        ) {
            println!("Minecraft monitor is running; sampling every 10 seconds");
            return Ok(());
        }
        if child.try_wait()?.is_some() {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let _ = child.kill();
    let _ = child.wait();
    bail!("Monitor did not start; inspect logs/standalone/monitor/background.log")
}

pub fn run(context: &Context, mut args: Vec<String>, cancelled: &AtomicBool) -> Result<()> {
    let command = cli::command(&mut args, "monitor start|watch|status|mark|stop|play")?;
    if matches!(command.as_str(), "--help" | "-h") {
        println!(
            "monitor start|watch|status|stop\nmonitor mark [NOTE]\nmonitor play [runtime launch options]"
        );
        return Ok(());
    }
    let latest = data(context).join("latest.json");
    let mut state = read_json::<Value>(&latest, 1024 * 1024).unwrap_or(json!({}));
    match command.as_str() {
        "watch" => watch(context, cancelled),
        "start" => start(context),
        "status" => {
            state["monitor_alive"] = alive(context, &state).into();
            let path = data(context).join("events.jsonl");
            if path.exists() {
                let mut file = File::open(path)?;
                let size = file.metadata()?.len();
                file.seek(SeekFrom::Start(size.saturating_sub(32768)))?;
                let mut bytes = Vec::new();
                file.take(32768).read_to_end(&mut bytes)?;
                let events: Vec<Value> = String::from_utf8_lossy(&bytes)
                    .lines()
                    .filter_map(|line| serde_json::from_str(line).ok())
                    .collect();
                state["recent_events"] =
                    events.into_iter().rev().take(12).collect::<Vec<_>>().into();
            }
            println!("{}", serde_json::to_string_pretty(&state)?);
            Ok(())
        }
        "stop" => {
            if alive(context, &state) {
                let pid = state["monitor_pid"]
                    .as_u64()
                    .context("Missing monitor PID")?;
                let birth = state["monitor_birth"]
                    .as_u64()
                    .context("Missing monitor birth")?;
                if same(pid as u32, birth) {
                    unsafe {
                        libc::kill(pid as i32, libc::SIGTERM);
                    }
                }
                println!("Stopping the monitor; Minecraft continues running");
            }
            Ok(())
        }
        "mark" => {
            ensure!(alive(context, &state), "The monitor is not running");
            let note = if args.is_empty() {
                "Player noticed a problem".into()
            } else {
                args.join(" ")
            };
            let path = capture(
                context,
                &note,
                state["games"].as_array().map(Vec::as_slice).unwrap_or(&[]),
                cancelled,
            )?;
            event(context, "player-report", &note, json!({"incident":path}))?;
            println!("Diagnostics: {}", path.display());
            Ok(())
        }
        "play" => {
            start(context)?;
            if args.first().is_some_and(|arg| arg == "--") {
                args.remove(0);
            }
            args.insert(0, "launch".into());
            let requested = event(context, "launch-requested", "Starting Minecraft", json!({}))?;
            let result = setup::runtime(context, args, cancelled);
            event(
                context,
                "launcher-exited",
                "Minecraft launcher exited",
                json!({"launch_id":requested["id"],"success":result.is_ok()}),
            )?;
            if result.is_err() {
                let path = capture(
                    context,
                    "Minecraft launcher exited with an error",
                    &[],
                    cancelled,
                )?;
                event(
                    context,
                    "launch-error",
                    "Minecraft launcher exited with an error",
                    json!({"incident":path}),
                )?;
            }
            result
        }
        _ => bail!("Unknown monitor command"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sustained_growth_ignores_startup() {
        let history =
            VecDeque::from([json!({"monotonic":200,"footprint_bytes":1024*1024*1024_u64})]);
        let mut sample = json!({"monotonic":800,"session_seconds":800,"footprint_bytes":2*1024*1024*1024_u64,"system":{}});
        assert_eq!(warnings(&history, &sample)[0].0, "memory-growth");
        sample["session_seconds"] = 30.into();
        assert!(warnings(&history, &sample).is_empty());
        sample["footprint_bytes"] = (11 * 1024 * 1024 * 1024_u64).into();
        assert_eq!(warnings(&history, &sample)[0].0, "urgent-memory");
    }
}
