use crate::ring::Consumer;
use anyhow::{Result, bail, ensure};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

pub const EVENT_BYTES: usize = 24;
pub const QUEUE: usize = 1024;

const KEY: u8 = 1;
const MOTION: u8 = 2;
const BUTTON: u8 = 3;
const WHEEL: u8 = 4;
pub const PING: u8 = 5;
pub const RELEASE: u8 = 6;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Event {
    pub kind: u8,
    pub flags: u8,
    pub code: u16,
    pub x: i32,
    pub y: i32,
    pub sequence: u32,
    pub client_micros: u64,
}

impl Event {
    pub fn parse(bytes: &[u8]) -> Result<Self> {
        ensure!(bytes.len() == EVENT_BYTES, "Input event must be 24 bytes");
        ensure!(bytes[0] == 1, "Unsupported input protocol");
        let event = Self {
            kind: bytes[1],
            flags: bytes[2],
            code: u16::from_le_bytes(bytes[4..6].try_into()?),
            x: i32::from_le_bytes(bytes[8..12].try_into()?),
            y: i32::from_le_bytes(bytes[12..16].try_into()?),
            sequence: u32::from_le_bytes(bytes[16..20].try_into()?),
            client_micros: u64::from(u32::from_le_bytes(bytes[20..24].try_into()?)),
        };
        ensure!(
            bytes[3] == 0 && bytes[6..8] == [0, 0],
            "Reserved input bytes must be zero"
        );
        match event.kind {
            KEY => ensure!(key(event.code), "Unsupported keyboard code"),
            MOTION => ensure!(event.code == 0, "Motion code must be zero"),
            BUTTON => ensure!(event.code <= 4, "Unsupported mouse button"),
            WHEEL => ensure!(
                event.code == 0 && event.y.abs() <= 16,
                "Invalid wheel event"
            ),
            PING | RELEASE => ensure!(
                event.code == 0 && event.x == 0 && event.y == 0,
                "Invalid control event"
            ),
            _ => bail!("Unsupported input event"),
        }
        Ok(event)
    }
}

fn key(code: u16) -> bool {
    matches!(code,
        1..=69 | 87..=88 |
        97 | 100 | 102..=111 | 119 | 125..=126)
}

pub struct Metrics {
    pub received: AtomicU64,
    pub applied: AtomicU64,
    pub dropped: AtomicU64,
    pub high_water: AtomicU64,
    pub queue: AtomicU64,
    pub release: AtomicBool,
}

impl Metrics {
    pub fn new() -> Self {
        Self {
            received: AtomicU64::new(0),
            applied: AtomicU64::new(0),
            dropped: AtomicU64::new(0),
            high_water: AtomicU64::new(0),
            queue: AtomicU64::new(0),
            release: AtomicBool::new(false),
        }
    }

    pub fn observe(&self, depth: usize) {
        self.received.fetch_add(1, Ordering::Relaxed);
        self.high_water.fetch_max(depth as u64, Ordering::Relaxed);
        self.queue.store(depth as u64, Ordering::Relaxed);
    }
}

pub enum Device {
    Disabled,
    #[cfg(target_os = "linux")]
    Linux(linux::Device),
}

impl Device {
    pub fn open(path: &str) -> Result<Self> {
        if path == "disabled" {
            return Ok(Self::Disabled);
        }
        #[cfg(target_os = "linux")]
        {
            Ok(Self::Linux(linux::Device::open(path)?))
        }
        #[cfg(not(target_os = "linux"))]
        {
            let _ = path;
            bail!("Native remote input requires Linux or --input disabled")
        }
    }

    fn apply(&mut self, event: Event, held: &mut [bool; 768]) -> Result<()> {
        if event.kind == PING {
            return Ok(());
        }
        if event.kind == RELEASE {
            return self.release(held);
        }
        #[cfg(target_os = "linux")]
        if let Self::Linux(device) = self {
            return device.apply(event, held);
        }
        Ok(())
    }

    fn release(&mut self, held: &mut [bool; 768]) -> Result<()> {
        #[cfg(target_os = "linux")]
        if let Self::Linux(device) = self {
            device.release(held)?;
        }
        held.fill(false);
        Ok(())
    }
}

pub fn run(
    mut consumer: Consumer<Event, QUEUE>,
    mut device: Device,
    running: Arc<AtomicBool>,
    metrics: Arc<Metrics>,
) -> Result<()> {
    let mut held = [false; 768];
    while !running.load(Ordering::Acquire) {
        if metrics.release.swap(false, Ordering::AcqRel) {
            device.release(&mut held)?;
        }
        if let Some(event) = consumer.try_pop() {
            device.apply(event, &mut held)?;
            metrics.applied.fetch_add(1, Ordering::Relaxed);
            metrics
                .queue
                .store(consumer.len() as u64, Ordering::Relaxed);
        } else {
            std::thread::park();
        }
    }
    while let Some(event) = consumer.try_pop() {
        device.apply(event, &mut held)?;
    }
    device.release(&mut held)
}

#[cfg(target_os = "linux")]
mod linux {
    use super::{BUTTON, Event, KEY, MOTION, WHEEL};
    use anyhow::{Context, Result, ensure};
    use std::fs::{File, OpenOptions};
    use std::io::Write;
    use std::mem::size_of;
    use std::os::fd::AsRawFd;

    const EV_SYN: u16 = 0;
    const EV_KEY: u16 = 1;
    const EV_REL: u16 = 2;
    const SYN_REPORT: u16 = 0;
    const REL_X: u16 = 0;
    const REL_Y: u16 = 1;
    const REL_WHEEL: u16 = 8;
    const BTN_LEFT: u16 = 0x110;
    const BUS_USB: u16 = 3;
    const UINPUT_MAX_NAME_SIZE: usize = 80;

    const IOC_WRITE: u64 = 1;
    const fn ioc(direction: u64, number: u64, size: usize) -> libc::c_ulong {
        ((direction << 30) | ((b'U' as u64) << 8) | number | ((size as u64) << 16)) as libc::c_ulong
    }
    const fn io(number: u64) -> libc::c_ulong {
        ioc(0, number, 0)
    }
    const UI_DEV_CREATE: libc::c_ulong = io(1);
    const UI_DEV_DESTROY: libc::c_ulong = io(2);
    const UI_DEV_SETUP: libc::c_ulong = ioc(IOC_WRITE, 3, size_of::<Setup>());
    const UI_SET_EVBIT: libc::c_ulong = ioc(IOC_WRITE, 100, size_of::<libc::c_int>());
    const UI_SET_KEYBIT: libc::c_ulong = ioc(IOC_WRITE, 101, size_of::<libc::c_int>());
    const UI_SET_RELBIT: libc::c_ulong = ioc(IOC_WRITE, 102, size_of::<libc::c_int>());

    #[repr(C)]
    struct InputId {
        bustype: u16,
        vendor: u16,
        product: u16,
        version: u16,
    }

    #[repr(C)]
    struct Setup {
        id: InputId,
        name: [u8; UINPUT_MAX_NAME_SIZE],
        ff_effects_max: u32,
    }

    #[repr(C)]
    struct InputEvent {
        time: libc::timeval,
        kind: u16,
        code: u16,
        value: i32,
    }

    pub struct Device(File);

    impl Device {
        pub fn open(path: &str) -> Result<Self> {
            let file = OpenOptions::new()
                .write(true)
                .open(path)
                .with_context(|| format!("Couldn’t open {path}"))?;
            let fd = file.as_raw_fd();
            ioctl(fd, UI_SET_EVBIT, i32::from(EV_KEY))?;
            ioctl(fd, UI_SET_EVBIT, i32::from(EV_REL))?;
            for code in 0..=767 {
                if super::key(code) || (BTN_LEFT..=BTN_LEFT + 4).contains(&code) {
                    ioctl(fd, UI_SET_KEYBIT, i32::from(code))?;
                }
            }
            for code in [REL_X, REL_Y, REL_WHEEL] {
                ioctl(fd, UI_SET_RELBIT, i32::from(code))?;
            }
            let mut setup = Setup {
                id: InputId {
                    bustype: BUS_USB,
                    vendor: 0x045e,
                    product: 0x0b13,
                    version: 1,
                },
                name: [0; UINPUT_MAX_NAME_SIZE],
                ff_effects_max: 0,
            };
            let name = b"Minecraft Stream Input";
            setup.name[..name.len()].copy_from_slice(name);
            ensure!(
                unsafe { libc::ioctl(fd, UI_DEV_SETUP, &setup) } == 0,
                "Couldn’t configure uinput"
            );
            ensure!(
                unsafe { libc::ioctl(fd, UI_DEV_CREATE) } == 0,
                "Couldn’t create uinput device"
            );
            Ok(Self(file))
        }

        pub fn apply(&mut self, event: Event, held: &mut [bool; 768]) -> Result<()> {
            match event.kind {
                KEY => self.key(event.code, event.flags & 1 != 0, held)?,
                BUTTON => self.key(BTN_LEFT + event.code, event.flags & 1 != 0, held)?,
                MOTION => {
                    self.write(EV_REL, REL_X, event.x)?;
                    self.write(EV_REL, REL_Y, event.y)?;
                }
                WHEEL => self.write(EV_REL, REL_WHEEL, event.y)?,
                _ => {}
            }
            self.write(EV_SYN, SYN_REPORT, 0)
        }

        pub fn release(&mut self, held: &mut [bool; 768]) -> Result<()> {
            for (code, down) in held.iter_mut().enumerate() {
                if *down {
                    self.write(EV_KEY, code as u16, 0)?;
                    *down = false;
                }
            }
            self.write(EV_SYN, SYN_REPORT, 0)
        }

        fn key(&mut self, code: u16, down: bool, held: &mut [bool; 768]) -> Result<()> {
            let state = &mut held[usize::from(code)];
            if *state != down {
                self.write(EV_KEY, code, i32::from(down))?;
                *state = down;
            }
            Ok(())
        }

        fn write(&mut self, kind: u16, code: u16, value: i32) -> Result<()> {
            let event = InputEvent {
                time: libc::timeval {
                    tv_sec: 0,
                    tv_usec: 0,
                },
                kind,
                code,
                value,
            };
            let bytes = unsafe {
                std::slice::from_raw_parts(
                    (&event as *const InputEvent).cast::<u8>(),
                    size_of::<InputEvent>(),
                )
            };
            self.0.write_all(bytes)?;
            Ok(())
        }
    }

    impl Drop for Device {
        fn drop(&mut self) {
            unsafe { libc::ioctl(self.0.as_raw_fd(), UI_DEV_DESTROY) };
        }
    }

    fn ioctl(fd: libc::c_int, request: libc::c_ulong, value: libc::c_int) -> Result<()> {
        ensure!(
            unsafe { libc::ioctl(fd, request, value) } == 0,
            "uinput ioctl failed"
        );
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bytes(kind: u8, code: u16, x: i32, y: i32) -> [u8; EVENT_BYTES] {
        let mut bytes = [0; EVENT_BYTES];
        bytes[0] = 1;
        bytes[1] = kind;
        bytes[4..6].copy_from_slice(&code.to_le_bytes());
        bytes[8..12].copy_from_slice(&x.to_le_bytes());
        bytes[12..16].copy_from_slice(&y.to_le_bytes());
        bytes
    }

    #[test]
    fn validates_fixed_input_protocol() {
        assert_eq!(Event::parse(&bytes(MOTION, 0, -9, 7)).unwrap().x, -9);
        assert!(Event::parse(&bytes(KEY, 70, 0, 0)).is_err());
        assert!(Event::parse(&bytes(BUTTON, 5, 0, 0)).is_err());
        assert!(Event::parse(&bytes(WHEEL, 0, 0, 17)).is_err());
        assert!(Event::parse(&bytes(99, 0, 0, 0)).is_err());
    }
}
