use crate::input::{Event, Metrics, PING, QUEUE};
use crate::ring::Producer;
use crate::sha1;
use anyhow::{Context, Result, bail, ensure};
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::Thread;
use std::time::Duration;

const INDEX: &str = include_str!("../../web/index.html");
const SCRIPT: &str = include_str!("../../web/app.js");
const STYLE: &str = include_str!("../../web/app.css");
const MAX_CONNECTIONS: usize = 32;

pub struct Config {
    pub bind: SocketAddr,
    pub origin: String,
    pub token: String,
}

struct State {
    config: Config,
    producer: Mutex<Producer<Event, QUEUE>>,
    input: Thread,
    running: Arc<AtomicBool>,
    metrics: Arc<Metrics>,
    controller: Arc<AtomicBool>,
}

pub fn run(
    config: Config,
    producer: Producer<Event, QUEUE>,
    input: Thread,
    running: Arc<AtomicBool>,
    metrics: Arc<Metrics>,
) -> Result<()> {
    ensure!(
        config.bind.ip().is_loopback(),
        "Stream host must bind to loopback behind TLS"
    );
    ensure!(
        config.origin.starts_with("https://"),
        "Browser origin must use HTTPS"
    );
    ensure!(
        config.token.len() >= 32 && config.token.len() <= 128,
        "Stream token must contain 32–128 bytes"
    );
    ensure!(
        config.token.bytes().all(|byte| byte.is_ascii_graphic()),
        "Stream token must be printable ASCII"
    );
    let listener = TcpListener::bind(config.bind)?;
    listener.set_nonblocking(true)?;
    let connections = Arc::new(AtomicUsize::new(0));
    let state = Arc::new(State {
        config,
        producer: Mutex::new(producer),
        input,
        running: running.clone(),
        metrics,
        controller: Arc::new(AtomicBool::new(false)),
    });
    while !running.load(Ordering::Acquire) {
        let (stream, _) = match listener.accept() {
            Ok(value) => value,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::park_timeout(Duration::from_millis(20));
                continue;
            }
            Err(error) => return Err(error.into()),
        };
        if connections.load(Ordering::Relaxed) >= MAX_CONNECTIONS {
            reject(stream, 503, "Busy")?;
            continue;
        }
        connections.fetch_add(1, Ordering::Relaxed);
        let state = state.clone();
        let connections = connections.clone();
        std::thread::spawn(move || {
            let _guard = Count(connections);
            if let Err(error) = connection(stream, &state) {
                eprintln!("Stream connection: {error:#}");
            }
        });
    }
    Ok(())
}

struct Count(Arc<AtomicUsize>);
impl Drop for Count {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

struct Controller(Arc<AtomicBool>);
impl Drop for Controller {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

struct Release {
    metrics: Arc<Metrics>,
    input: Thread,
}
impl Drop for Release {
    fn drop(&mut self) {
        self.metrics.release.store(true, Ordering::Release);
        self.input.unpark();
    }
}

trait Wire: Read + Write {
    fn configure(&self) -> std::io::Result<()>;
    fn input_timeout(&self) -> std::io::Result<()>;
}

impl Wire for TcpStream {
    fn configure(&self) -> std::io::Result<()> {
        self.set_read_timeout(Some(Duration::from_secs(5)))?;
        self.set_write_timeout(Some(Duration::from_secs(5)))?;
        self.set_nodelay(true)
    }

    fn input_timeout(&self) -> std::io::Result<()> {
        self.set_read_timeout(Some(Duration::from_secs(15)))
    }
}

#[cfg(test)]
impl Wire for std::os::unix::net::UnixStream {
    fn configure(&self) -> std::io::Result<()> {
        self.set_read_timeout(Some(Duration::from_secs(5)))?;
        self.set_write_timeout(Some(Duration::from_secs(5)))
    }

    fn input_timeout(&self) -> std::io::Result<()> {
        self.set_read_timeout(Some(Duration::from_secs(15)))
    }
}

fn connection(mut stream: impl Wire, state: &State) -> Result<()> {
    stream.configure()?;
    let mut request = [0; 8192];
    let length = header(&mut stream, &mut request)?;
    let mut headers = [httparse::EMPTY_HEADER; 32];
    let mut parsed = httparse::Request::new(&mut headers);
    ensure!(
        parsed.parse(&request[..length])?.is_complete(),
        "Incomplete request"
    );
    ensure!(
        parsed.method == Some("GET") && parsed.version == Some(1),
        "Unsupported request"
    );
    let path = parsed.path.context("Missing request path")?;
    if path == "/input" {
        return websocket(stream, &parsed, state);
    }
    let (status, content_type, body) = match path {
        "/" | "/index.html" => (200, "text/html; charset=utf-8", INDEX.as_bytes()),
        "/app.js" => (200, "text/javascript; charset=utf-8", SCRIPT.as_bytes()),
        "/app.css" => (200, "text/css; charset=utf-8", STYLE.as_bytes()),
        "/health" => {
            let body = format!(
                "{{\"state\":\"ready\",\"received\":{},\"applied\":{},\"dropped\":{},\"queue\":{},\"high_water\":{}}}",
                state.metrics.received.load(Ordering::Relaxed),
                state.metrics.applied.load(Ordering::Relaxed),
                state.metrics.dropped.load(Ordering::Relaxed),
                state.metrics.queue.load(Ordering::Relaxed),
                state.metrics.high_water.load(Ordering::Relaxed),
            );
            return response(&mut stream, 200, "application/json", body.as_bytes());
        }
        _ => (404, "text/plain; charset=utf-8", b"Not found".as_slice()),
    };
    response(&mut stream, status, content_type, body)
}

fn header(stream: &mut impl Read, bytes: &mut [u8]) -> Result<usize> {
    let mut length = 0;
    while length < bytes.len() {
        let count = stream.read(&mut bytes[length..])?;
        ensure!(count > 0, "Connection closed before request");
        length += count;
        if bytes[..length].windows(4).any(|part| part == b"\r\n\r\n") {
            return Ok(length);
        }
    }
    bail!("Request headers are too large")
}

fn response(stream: &mut impl Write, status: u16, content_type: &str, body: &[u8]) -> Result<()> {
    let reason = if status == 200 { "OK" } else { "Not Found" };
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'self'; connect-src 'self' wss:; media-src 'self' blob:; img-src 'self' data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'\r\nCross-Origin-Opener-Policy: same-origin\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",
        body.len()
    )?;
    stream.write_all(body)?;
    Ok(())
}

fn reject(mut stream: TcpStream, status: u16, body: &str) -> Result<()> {
    write!(
        stream,
        "HTTP/1.1 {status} {body}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )?;
    Ok(())
}

fn websocket(
    mut stream: impl Wire,
    request: &httparse::Request<'_, '_>,
    state: &State,
) -> Result<()> {
    ensure!(
        header_value(request, "origin") == Some(state.config.origin.as_str()),
        "Unexpected browser origin"
    );
    ensure!(
        header_value(request, "sec-websocket-version") == Some("13"),
        "Unsupported WebSocket version"
    );
    let key = header_value(request, "sec-websocket-key").context("Missing WebSocket key")?;
    ensure!(
        header_value(request, "upgrade")
            .is_some_and(|value| value.eq_ignore_ascii_case("websocket")),
        "Missing WebSocket upgrade"
    );
    ensure!(
        header_value(request, "connection").is_some_and(|value| value
            .split(',')
            .any(|part| part.trim().eq_ignore_ascii_case("upgrade"))),
        "Missing upgrade connection"
    );
    let mut source = Vec::with_capacity(key.len() + 36);
    source.extend_from_slice(key.as_bytes());
    source.extend_from_slice(b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    let accept = STANDARD.encode(sha1::digest(&source));
    write!(
        stream,
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n"
    )?;
    let mut payload = [0; 256];
    let (opcode, length) = frame(&mut stream, &mut payload)?;
    ensure!(
        opcode == 1 && constant_time(&payload[..length], state.config.token.as_bytes()),
        "Stream authentication failed"
    );
    ensure!(
        state
            .controller
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok(),
        "Another controller is active"
    );
    let _controller = Controller(state.controller.clone());
    let _release = Release {
        metrics: state.metrics.clone(),
        input: state.input.clone(),
    };
    let mut producer = state
        .producer
        .lock()
        .map_err(|_| anyhow::anyhow!("Input queue failed"))?;
    stream.input_timeout()?;
    while !state.running.load(Ordering::Acquire) {
        let (opcode, length) = match frame(&mut stream, &mut payload) {
            Ok(frame) => frame,
            Err(error)
                if error.downcast_ref::<std::io::Error>().is_some_and(|error| {
                    matches!(
                        error.kind(),
                        std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
                    )
                }) =>
            {
                continue;
            }
            Err(error) => return Err(error),
        };
        match opcode {
            2 => {
                let event = Event::parse(&payload[..length])?;
                if event.kind == PING {
                    send(&mut stream, 2, &payload[..length])?;
                    continue;
                }
                match producer.try_push(event) {
                    Ok(()) => {
                        state.metrics.observe(producer.len());
                        state.input.unpark();
                    }
                    Err(_) => {
                        state.metrics.dropped.fetch_add(1, Ordering::Relaxed);
                    }
                }
            }
            8 => break,
            9 => send(&mut stream, 10, &payload[..length])?,
            10 => {}
            _ => bail!("Unsupported WebSocket frame"),
        }
    }
    Ok(())
}

fn header_value<'a>(request: &'a httparse::Request<'_, '_>, name: &str) -> Option<&'a str> {
    request
        .headers
        .iter()
        .find(|header| header.name.eq_ignore_ascii_case(name))
        .and_then(|header| std::str::from_utf8(header.value).ok())
}

fn frame(stream: &mut impl Read, payload: &mut [u8]) -> Result<(u8, usize)> {
    let mut header = [0; 2];
    stream.read_exact(&mut header)?;
    ensure!(
        header[0] & 0x80 != 0 && header[0] & 0x70 == 0,
        "Fragmented WebSocket frame"
    );
    ensure!(header[1] & 0x80 != 0, "Browser frame must be masked");
    let opcode = header[0] & 0x0f;
    let mut length = usize::from(header[1] & 0x7f);
    if length == 126 {
        let mut extended = [0; 2];
        stream.read_exact(&mut extended)?;
        length = usize::from(u16::from_be_bytes(extended));
    } else if length == 127 {
        bail!("WebSocket frame is too large");
    }
    ensure!(length <= payload.len(), "WebSocket frame is too large");
    let mut mask = [0; 4];
    stream.read_exact(&mut mask)?;
    stream.read_exact(&mut payload[..length])?;
    for (index, byte) in payload[..length].iter_mut().enumerate() {
        *byte ^= mask[index & 3];
    }
    Ok((opcode, length))
}

fn send(stream: &mut impl Write, opcode: u8, payload: &[u8]) -> Result<()> {
    ensure!(payload.len() <= 125, "Server frame is too large");
    stream.write_all(&[0x80 | opcode, payload.len() as u8])?;
    stream.write_all(payload)?;
    Ok(())
}

fn constant_time(left: &[u8], right: &[u8]) -> bool {
    let mut difference = left.len() ^ right.len();
    for index in 0..left.len().max(right.len()) {
        difference |= usize::from(
            left.get(index).copied().unwrap_or(0) ^ right.get(index).copied().unwrap_or(0),
        );
    }
    difference == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ring;
    use std::io::{Read, Write};
    use std::net::Shutdown;
    use std::os::unix::net::UnixStream;
    use std::sync::atomic::AtomicBool;

    fn state() -> Arc<State> {
        let (producer, _) = ring::channel::<Event, QUEUE>();
        Arc::new(State {
            config: Config {
                bind: "127.0.0.1:0".parse().unwrap(),
                origin: "https://stream.example".into(),
                token: "0123456789abcdef0123456789abcdef".into(),
            },
            producer: Mutex::new(producer),
            input: std::thread::current(),
            running: Arc::new(AtomicBool::new(false)),
            metrics: Arc::new(Metrics::new()),
            controller: Arc::new(AtomicBool::new(false)),
        })
    }

    fn connect(state: Arc<State>) -> (UnixStream, std::thread::JoinHandle<Result<()>>) {
        let (client, server) = UnixStream::pair().unwrap();
        let worker = std::thread::spawn(move || connection(server, &state));
        (client, worker)
    }

    fn masked(opcode: u8, payload: &[u8]) -> Vec<u8> {
        assert!(payload.len() <= 125);
        let mask = [0x12, 0x34, 0x56, 0x78];
        let mut frame = vec![0x80 | opcode, 0x80 | payload.len() as u8];
        frame.extend_from_slice(&mask);
        frame.extend(
            payload
                .iter()
                .enumerate()
                .map(|(index, byte)| byte ^ mask[index & 3]),
        );
        frame
    }

    #[test]
    fn websocket_accept_matches_rfc() {
        let mut source = b"dGhlIHNhbXBsZSBub25jZQ==".to_vec();
        source.extend_from_slice(b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
        assert_eq!(
            STANDARD.encode(sha1::digest(&source)),
            "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        );
    }

    #[test]
    fn token_comparison_checks_length_and_content() {
        assert!(constant_time(b"secret", b"secret"));
        assert!(!constant_time(b"secret", b"secrex"));
        assert!(!constant_time(b"secret", b"secret-long"));
    }

    #[test]
    fn serves_embedded_client_with_browser_security_headers() {
        let (mut client, worker) = connect(state());
        client
            .write_all(b"GET / HTTP/1.1\r\nHost: stream.example\r\n\r\n")
            .unwrap();
        client.shutdown(Shutdown::Write).unwrap();
        let mut response = String::new();
        client.read_to_string(&mut response).unwrap();
        worker.join().unwrap().unwrap();
        assert!(response.starts_with("HTTP/1.1 200 OK"));
        assert!(response.contains("Content-Security-Policy:"));
        assert!(response.contains("Minecraft Stream"));
    }

    #[test]
    fn authenticates_websocket_and_enqueues_binary_input() {
        let state = state();
        let metrics = state.metrics.clone();
        let controller = state.controller.clone();
        let token = state.config.token.clone();
        let (mut client, worker) = connect(state);
        client
            .write_all(
                b"GET /input HTTP/1.1\r\nHost: stream.example\r\nOrigin: https://stream.example\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n",
            )
            .unwrap();
        let mut response = Vec::new();
        let mut byte = [0; 1];
        while !response.ends_with(b"\r\n\r\n") {
            client.read_exact(&mut byte).unwrap();
            response.push(byte[0]);
        }
        assert!(response.starts_with(b"HTTP/1.1 101 Switching Protocols"));
        client.write_all(&masked(1, token.as_bytes())).unwrap();
        let mut event = [0; 24];
        event[0] = 1;
        event[1] = 2;
        event[8..12].copy_from_slice(&7_i32.to_le_bytes());
        event[12..16].copy_from_slice(&(-4_i32).to_le_bytes());
        client.write_all(&masked(2, &event)).unwrap();
        client.write_all(&masked(8, &[])).unwrap();
        worker.join().unwrap().unwrap();
        assert_eq!(metrics.received.load(Ordering::Relaxed), 1);
        assert!(!controller.load(Ordering::Acquire));
    }
}
