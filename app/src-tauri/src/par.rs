use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;

pub const IO_THREADS: usize = 16;

pub fn cpu_threads() -> usize {
    thread::available_parallelism().map(|n| n.get()).unwrap_or(4)
}

pub fn par_map<T: Sync, R: Send>(items: &[T], workers: usize, f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    let next = AtomicUsize::new(0);
    let workers = workers.min(items.len()).max(1);
    let mut done: Vec<(usize, R)> = thread::scope(|s| {
        let handles: Vec<_> = (0..workers)
            .map(|_| {
                s.spawn(|| {
                    let mut out = Vec::new();
                    loop {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        let Some(item) = items.get(i) else { break };
                        out.push((i, f(item)));
                    }
                    out
                })
            })
            .collect();
        handles.into_iter().flat_map(|h| h.join().unwrap()).collect()
    });
    done.sort_unstable_by_key(|(i, _)| *i);
    done.into_iter().map(|(_, r)| r).collect()
}
