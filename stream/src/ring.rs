use std::cell::UnsafeCell;
use std::mem::MaybeUninit;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

#[repr(align(128))]
struct Cursor(AtomicUsize);

struct Inner<T, const N: usize> {
    slots: [UnsafeCell<MaybeUninit<T>>; N],
    head: Cursor,
    tail: Cursor,
}

unsafe impl<T: Send, const N: usize> Send for Inner<T, N> {}
unsafe impl<T: Send, const N: usize> Sync for Inner<T, N> {}

impl<T, const N: usize> Drop for Inner<T, N> {
    fn drop(&mut self) {
        let head = *self.head.0.get_mut();
        let mut tail = *self.tail.0.get_mut();
        while tail != head {
            unsafe { self.slots[tail & (N - 1)].get_mut().assume_init_drop() }
            tail = tail.wrapping_add(1);
        }
    }
}

pub struct Producer<T, const N: usize> {
    inner: Arc<Inner<T, N>>,
}

pub struct Consumer<T, const N: usize> {
    inner: Arc<Inner<T, N>>,
}

pub fn channel<T, const N: usize>() -> (Producer<T, N>, Consumer<T, N>) {
    assert!(N.is_power_of_two() && N > 1);
    let inner = Arc::new(Inner {
        slots: std::array::from_fn(|_| UnsafeCell::new(MaybeUninit::uninit())),
        head: Cursor(AtomicUsize::new(0)),
        tail: Cursor(AtomicUsize::new(0)),
    });
    (
        Producer {
            inner: inner.clone(),
        },
        Consumer { inner },
    )
}

impl<T, const N: usize> Producer<T, N> {
    pub fn try_push(&mut self, value: T) -> Result<(), T> {
        let head = self.inner.head.0.load(Ordering::Relaxed);
        let tail = self.inner.tail.0.load(Ordering::Acquire);
        if head.wrapping_sub(tail) == N {
            return Err(value);
        }
        unsafe { (*self.inner.slots[head & (N - 1)].get()).write(value) };
        self.inner
            .head
            .0
            .store(head.wrapping_add(1), Ordering::Release);
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.inner
            .head
            .0
            .load(Ordering::Acquire)
            .wrapping_sub(self.inner.tail.0.load(Ordering::Acquire))
    }
}

impl<T, const N: usize> Consumer<T, N> {
    pub fn try_pop(&mut self) -> Option<T> {
        let tail = self.inner.tail.0.load(Ordering::Relaxed);
        if tail == self.inner.head.0.load(Ordering::Acquire) {
            return None;
        }
        let value = unsafe { (*self.inner.slots[tail & (N - 1)].get()).assume_init_read() };
        self.inner
            .tail
            .0
            .store(tail.wrapping_add(1), Ordering::Release);
        Some(value)
    }

    pub fn len(&self) -> usize {
        self.inner
            .head
            .0
            .load(Ordering::Acquire)
            .wrapping_sub(self.inner.tail.0.load(Ordering::Acquire))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::time::Instant;

    #[test]
    fn preserves_order_and_bounds_capacity() {
        let (mut producer, mut consumer) = channel::<u32, 4>();
        for value in 0..4 {
            assert_eq!(producer.try_push(value), Ok(()));
        }
        assert_eq!(producer.try_push(9), Err(9));
        assert_eq!(producer.len(), 4);
        for value in 0..4 {
            assert_eq!(consumer.try_pop(), Some(value));
        }
        assert_eq!(consumer.try_pop(), None);
    }

    #[test]
    fn drops_each_retained_value_once() {
        static DROPS: AtomicUsize = AtomicUsize::new(0);
        struct Value;
        impl Drop for Value {
            fn drop(&mut self) {
                DROPS.fetch_add(1, Ordering::Relaxed);
            }
        }
        DROPS.store(0, Ordering::Relaxed);
        let (mut producer, mut consumer) = channel::<Value, 4>();
        producer.try_push(Value).ok().unwrap();
        producer.try_push(Value).ok().unwrap();
        drop(consumer.try_pop());
        drop(producer);
        drop(consumer);
        assert_eq!(DROPS.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn crosses_threads_without_reordering() {
        const COUNT: u32 = 100_000;
        let (mut producer, mut consumer) = channel::<u32, 64>();
        let writer = std::thread::spawn(move || {
            for value in 0..COUNT {
                let mut pending = value;
                loop {
                    match producer.try_push(pending) {
                        Ok(()) => break,
                        Err(value) => {
                            pending = value;
                            std::hint::spin_loop();
                        }
                    }
                }
            }
        });
        for expected in 0..COUNT {
            loop {
                if let Some(actual) = consumer.try_pop() {
                    assert_eq!(actual, expected);
                    break;
                }
                std::hint::spin_loop();
            }
        }
        writer.join().unwrap();
    }

    #[test]
    fn push_and_pop_do_not_allocate() {
        let (mut producer, mut consumer) = channel::<u64, 1024>();
        let allocations = crate::tracked_allocations(|| {
            for value in 0..100_000 {
                producer.try_push(value).unwrap();
                assert_eq!(consumer.try_pop(), Some(value));
            }
        });
        assert_eq!(allocations, 0);
    }

    #[test]
    #[ignore]
    fn saturation_profile() {
        const COUNT: usize = 1_000_000;
        let (mut producer, mut consumer) = channel::<Instant, 1024>();
        let done = Arc::new(AtomicBool::new(false));
        let writer_done = done.clone();
        let started = Instant::now();
        let writer = std::thread::spawn(move || {
            let mut dropped = 0;
            let mut high_water = 0;
            for _ in 0..COUNT {
                if producer.try_push(Instant::now()).is_err() {
                    dropped += 1;
                } else {
                    high_water = high_water.max(producer.len());
                }
            }
            writer_done.store(true, Ordering::Release);
            (dropped, high_water)
        });
        let mut latency = Vec::with_capacity(COUNT);
        while !done.load(Ordering::Acquire) || consumer.len() != 0 {
            if let Some(sent) = consumer.try_pop() {
                latency.push(sent.elapsed().as_nanos() as u64);
            } else {
                std::hint::spin_loop();
            }
        }
        let elapsed = started.elapsed();
        let (dropped, high_water) = writer.join().unwrap();
        latency.sort_unstable();
        let percentile = |fraction: f64| {
            latency[((latency.len() - 1) as f64 * fraction) as usize] as f64 / 1_000.0
        };
        eprintln!(
            "ring attempts={COUNT} delivered={} dropped={dropped} high_water={high_water} throughput={:.0}/s p50={:.2}us p95={:.2}us p99={:.2}us",
            latency.len(),
            COUNT as f64 / elapsed.as_secs_f64(),
            percentile(0.50),
            percentile(0.95),
            percentile(0.99),
        );
        assert!(!latency.is_empty());
    }
}
