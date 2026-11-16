use anyhow::{Context, Result, bail, ensure};
use serde_json::json;
use std::process::{Command, Stdio};

pub struct Config {
    pub ffmpeg: String,
    pub device: String,
    pub encoder: String,
    pub whip: String,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
    pub bitrate: u32,
    pub dry_run: bool,
}

pub fn run(config: Config) -> Result<()> {
    ensure!(
        cfg!(target_os = "linux") || config.dry_run,
        "Publishing requires Linux"
    );
    ensure!((30..=240).contains(&config.fps), "FPS must be 30–240");
    ensure!(
        (640..=3840).contains(&config.width) && (360..=2160).contains(&config.height),
        "Resolution is outside the supported range"
    );
    ensure!(
        (2_000..=50_000).contains(&config.bitrate),
        "Bitrate must be 2,000–50,000 Kbit/s"
    );
    ensure!(
        config.whip.starts_with("http://127.0.0.1:") || config.whip.starts_with("http://[::1]:"),
        "WHIP publisher must stay on loopback"
    );
    let mut command = command(&config)?;
    if config.dry_run {
        let program = command.get_program().to_string_lossy().into_owned();
        let arguments = command
            .get_args()
            .map(|argument| argument.to_string_lossy().into_owned())
            .collect::<Vec<_>>();
        println!(
            "{}",
            json!({
                "program": program,
                "arguments": arguments,
                "capture": "DRM PRIME",
                "mapping": "direct DMA-BUF",
                "renderer": "Vulkan",
                "encoder": config.encoder,
            })
        );
        return Ok(());
    }
    probe(&config)?;
    let status = command
        .stdin(Stdio::null())
        .status()
        .context("Couldn’t start FFmpeg publisher")?;
    ensure!(status.success(), "FFmpeg publisher stopped unexpectedly");
    Ok(())
}

fn command(config: &Config) -> Result<Command> {
    let mut command = Command::new(&config.ffmpeg);
    command.args([
        "-hide_banner",
        "-loglevel",
        "warning",
        "-fflags",
        "nobuffer",
        "-flags",
        "low_delay",
        "-f",
        "kmsgrab",
        "-device",
        &config.device,
        "-framerate",
        &config.fps.to_string(),
        "-i",
        "-",
        "-f",
        "pulse",
        "-i",
        "default",
        "-vf",
        &format!(
            "hwmap=mode=read+direct:derive_device={},scale_{}=w={}:h={}:format=nv12",
            config.encoder, config.encoder, config.width, config.height
        ),
    ]);
    match config.encoder.as_str() {
        "cuda" => {
            command.args([
                "-c:v",
                "h264_nvenc",
                "-preset",
                "p1",
                "-tune",
                "ull",
                "-zerolatency",
                "1",
                "-delay",
                "0",
                "-rc",
                "cbr",
            ]);
        }
        "vaapi" => {
            command.args(["-c:v", "h264_vaapi", "-low_power", "1", "-rc_mode", "CBR"]);
        }
        _ => bail!("Encoder must be cuda or vaapi"),
    }
    command.args([
        "-bf",
        "0",
        "-g",
        &config.fps.to_string(),
        "-b:v",
        &format!("{}k", config.bitrate),
        "-maxrate",
        &format!("{}k", config.bitrate),
        "-bufsize",
        &format!("{}k", config.bitrate / 4),
        "-c:a",
        "libopus",
        "-b:a",
        "128k",
        "-application",
        "lowdelay",
        "-frame_duration",
        "10",
        "-f",
        "whip",
        &config.whip,
    ]);
    Ok(command)
}

fn probe(config: &Config) -> Result<()> {
    for (argument, required) in [
        ("-devices", "kmsgrab"),
        ("-muxers", "whip"),
        ("-filters", "hwmap"),
        (
            "-filters",
            if config.encoder == "cuda" {
                "scale_cuda"
            } else {
                "scale_vaapi"
            },
        ),
        (
            "-encoders",
            if config.encoder == "cuda" {
                "h264_nvenc"
            } else {
                "h264_vaapi"
            },
        ),
    ] {
        let output = Command::new(&config.ffmpeg)
            .args(["-hide_banner", argument])
            .output()
            .with_context(|| format!("Couldn’t inspect {}", config.ffmpeg))?;
        ensure!(
            output.status.success() && String::from_utf8_lossy(&output.stdout).contains(required),
            "FFmpeg is missing {required}"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requires_direct_hardware_mapping() {
        let config = Config {
            ffmpeg: "ffmpeg".into(),
            device: "/dev/dri/card0".into(),
            encoder: "cuda".into(),
            whip: "http://127.0.0.1:8889/minecraft/whip".into(),
            width: 1920,
            height: 1080,
            fps: 60,
            bitrate: 12_000,
            dry_run: true,
        };
        let command = command(&config).unwrap();
        let arguments = command
            .get_args()
            .map(|argument| argument.to_string_lossy())
            .collect::<Vec<_>>();
        assert!(
            arguments
                .iter()
                .any(|argument| argument.contains("mode=read+direct"))
        );
        assert!(arguments.iter().any(|argument| argument == "h264_nvenc"));
        assert!(!arguments.iter().any(|argument| argument == "libx264"));
    }
}
