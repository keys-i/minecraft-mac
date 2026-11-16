mod input;
mod media;
mod ring;
mod server;
mod sha1;

use anyhow::{Context, Result, bail, ensure};
#[cfg(test)]
use std::alloc::{GlobalAlloc, Layout, System};
#[cfg(test)]
use std::cell::Cell;
use std::net::SocketAddr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

#[cfg(test)]
struct TestAllocator;

#[cfg(test)]
thread_local! {
    static TRACK_ALLOCATIONS: Cell<bool> = const { Cell::new(false) };
    static ALLOCATIONS: Cell<usize> = const { Cell::new(0) };
}

#[cfg(test)]
#[global_allocator]
static TEST_ALLOCATOR: TestAllocator = TestAllocator;

#[cfg(test)]
unsafe impl GlobalAlloc for TestAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        TRACK_ALLOCATIONS.with(|track| {
            if track.get() {
                ALLOCATIONS.set(ALLOCATIONS.get() + 1);
            }
        });
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        unsafe { System.dealloc(pointer, layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        TRACK_ALLOCATIONS.with(|track| {
            if track.get() {
                ALLOCATIONS.set(ALLOCATIONS.get() + 1);
            }
        });
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        TRACK_ALLOCATIONS.with(|track| {
            if track.get() {
                ALLOCATIONS.set(ALLOCATIONS.get() + 1);
            }
        });
        unsafe { System.realloc(pointer, layout, size) }
    }
}

#[cfg(test)]
fn tracked_allocations(action: impl FnOnce()) -> usize {
    ALLOCATIONS.set(0);
    TRACK_ALLOCATIONS.set(true);
    action();
    TRACK_ALLOCATIONS.set(false);
    ALLOCATIONS.get()
}

fn main() {
    if let Err(error) = execute() {
        eprintln!("Minecraft Stream: {error:#}");
        std::process::exit(1);
    }
}

fn execute() -> Result<()> {
    let mut args = std::env::args().skip(1).collect::<Vec<_>>();
    let command = take(&mut args).unwrap_or_else(|| "--help".into());
    match command.as_str() {
        "serve" => serve(args),
        "publish" => publish(args),
        "--help" | "-h" => {
            println!(
                "stream serve --origin URL [--bind 127.0.0.1:8090] [--input /dev/uinput|disabled]\nstream publish [--encoder cuda|vaapi] [--device /dev/dri/card0] [--whip URL] [--width 1920] [--height 1080] [--fps 60] [--bitrate 12000] [--ffmpeg PATH] [--dry-run]"
            );
            Ok(())
        }
        _ => bail!("Choose stream serve or publish"),
    }
}

fn serve(mut args: Vec<String>) -> Result<()> {
    if flag(&mut args, "--help") || flag(&mut args, "-h") {
        println!(
            "stream serve --origin URL [--bind 127.0.0.1:8090] [--input /dev/uinput|disabled]"
        );
        return Ok(());
    }
    let origin = option(&mut args, "--origin")?.context("Choose the public HTTPS origin")?;
    let bind = option(&mut args, "--bind")?
        .unwrap_or_else(|| "127.0.0.1:8090".into())
        .parse::<SocketAddr>()?;
    let input_path = option(&mut args, "--input")?.unwrap_or_else(|| {
        if cfg!(target_os = "linux") {
            "/dev/uinput".into()
        } else {
            "disabled".into()
        }
    });
    ensure!(args.is_empty(), "Unexpected stream arguments");
    let token = std::env::var("MINECRAFT_STREAM_TOKEN")
        .context("Set MINECRAFT_STREAM_TOKEN to a private random value")?;
    let device = input::Device::open(&input_path)?;
    let running = Arc::new(AtomicBool::new(false));
    signal_hook::flag::register(signal_hook::consts::SIGTERM, running.clone())?;
    signal_hook::flag::register(signal_hook::consts::SIGINT, running.clone())?;
    let (producer, consumer) = ring::channel::<input::Event, { input::QUEUE }>();
    let metrics = Arc::new(input::Metrics::new());
    let thread_running = running.clone();
    let thread_metrics = metrics.clone();
    let worker = std::thread::spawn(move || {
        let result = input::run(consumer, device, thread_running.clone(), thread_metrics);
        if result.is_err() {
            thread_running.store(true, Ordering::Release);
        }
        result
    });
    let input = worker.thread().clone();
    println!("Minecraft Stream listening on {bind}");
    let result = server::run(
        server::Config {
            bind,
            origin,
            token,
        },
        producer,
        input.clone(),
        running.clone(),
        metrics,
    );
    running.store(true, Ordering::Release);
    input.unpark();
    worker
        .join()
        .map_err(|_| anyhow::anyhow!("Input worker panicked"))??;
    result
}

fn publish(mut args: Vec<String>) -> Result<()> {
    if flag(&mut args, "--help") || flag(&mut args, "-h") {
        println!(
            "stream publish [--encoder cuda|vaapi] [--device PATH] [--whip URL] [--width N] [--height N] [--fps N] [--bitrate KBIT] [--ffmpeg PATH] [--dry-run]"
        );
        return Ok(());
    }
    let config = media::Config {
        ffmpeg: option(&mut args, "--ffmpeg")?.unwrap_or_else(|| "ffmpeg".into()),
        device: option(&mut args, "--device")?.unwrap_or_else(|| "/dev/dri/card0".into()),
        encoder: option(&mut args, "--encoder")?.unwrap_or_else(|| "cuda".into()),
        whip: option(&mut args, "--whip")?
            .unwrap_or_else(|| "http://127.0.0.1:8889/minecraft/whip".into()),
        width: number(&mut args, "--width", 1920)?,
        height: number(&mut args, "--height", 1080)?,
        fps: number(&mut args, "--fps", 60)?,
        bitrate: number(&mut args, "--bitrate", 12_000)?,
        dry_run: flag(&mut args, "--dry-run"),
    };
    ensure!(args.is_empty(), "Unexpected stream arguments");
    media::run(config)
}

fn take(args: &mut Vec<String>) -> Option<String> {
    (!args.is_empty()).then(|| args.remove(0))
}

fn option(args: &mut Vec<String>, name: &str) -> Result<Option<String>> {
    let Some(index) = args.iter().position(|argument| argument == name) else {
        return Ok(None);
    };
    ensure!(index + 1 < args.len(), "{name} needs a value");
    let value = args.remove(index + 1);
    args.remove(index);
    Ok(Some(value))
}

fn flag(args: &mut Vec<String>, name: &str) -> bool {
    if let Some(index) = args.iter().position(|argument| argument == name) {
        args.remove(index);
        true
    } else {
        false
    }
}

fn number(args: &mut Vec<String>, name: &str, default: u32) -> Result<u32> {
    option(args, name)?
        .map(|value| value.parse().with_context(|| format!("Invalid {name}")))
        .transpose()
        .map(|value| value.unwrap_or(default))
}
