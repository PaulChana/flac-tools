use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, UNIX_EPOCH};

use crate::flac::FlacInfo;

const VERSION: u32 = 1;

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
pub struct Stamp {
    size: u64,
    mtime: u64,
}

impl Stamp {
    pub fn of(meta: &fs::Metadata) -> Stamp {
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0);
        Stamp {
            size: meta.len(),
            mtime,
        }
    }
}

#[derive(Serialize, Deserialize)]
struct Entry<T> {
    stamp: Stamp,
    value: T,
}

#[derive(Serialize, Deserialize, Default)]
struct Store {
    version: u32,
    infos: HashMap<String, Entry<(FlacInfo, bool)>>,
    thumbs: HashMap<String, Entry<Option<String>>>,
    dims: HashMap<String, Entry<Option<(u32, u32)>>>,
}

fn store() -> &'static Mutex<Store> {
    static STORE: OnceLock<Mutex<Store>> = OnceLock::new();
    STORE.get_or_init(Default::default)
}

fn seen() -> &'static Mutex<HashMap<String, Stamp>> {
    static SEEN: OnceLock<Mutex<HashMap<String, Stamp>>> = OnceLock::new();
    SEEN.get_or_init(Default::default)
}

static DIRTY: AtomicBool = AtomicBool::new(false);

pub fn init(dir: PathBuf) {
    let file = dir.join("file-cache.json");
    if let Ok(bytes) = fs::read(&file) {
        if let Ok(loaded) = serde_json::from_slice::<Store>(&bytes) {
            if loaded.version == VERSION {
                *store().lock().unwrap() = loaded;
            }
        }
    }
    thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(5));
        if DIRTY.swap(false, Ordering::Relaxed) {
            let bytes = {
                let mut s = store().lock().unwrap();
                s.version = VERSION;
                serde_json::to_vec(&*s)
            };
            let tmp = file.with_extension("json.tmp");
            let _ = bytes
                .map_err(std::io::Error::other)
                .and_then(|b| fs::create_dir_all(&dir).and_then(|_| fs::write(&tmp, b)))
                .and_then(|_| fs::rename(&tmp, &file));
        }
    });
}

pub fn note(path: &str, meta: &fs::Metadata) {
    seen()
        .lock()
        .unwrap()
        .insert(path.to_string(), Stamp::of(meta));
}

pub fn stamp(path: &str) -> Option<Stamp> {
    if let Some(s) = seen().lock().unwrap().get(path) {
        return Some(*s);
    }
    fs::metadata(path).ok().map(|m| Stamp::of(&m))
}

pub fn forget(path: &str) {
    seen().lock().unwrap().remove(path);
    let mut s = store().lock().unwrap();
    s.infos.remove(path);
    s.thumbs
        .retain(|k, _| k.split_once(':').map(|(_, p)| p) != Some(path));
    s.dims.remove(path);
}

fn cached<T: Clone + Serialize + DeserializeOwned>(
    pick: fn(&mut Store) -> &mut HashMap<String, Entry<T>>,
    key: String,
    stamp: Option<Stamp>,
    accept: impl Fn(&T) -> bool,
    read: impl FnOnce() -> T,
) -> T {
    let Some(stamp) = stamp else { return read() };
    if let Some(e) = pick(&mut store().lock().unwrap()).get(&key) {
        if e.stamp == stamp && accept(&e.value) {
            return e.value.clone();
        }
    }
    let value = read();
    pick(&mut store().lock().unwrap()).insert(
        key,
        Entry {
            stamp,
            value: value.clone(),
        },
    );
    DIRTY.store(true, Ordering::Relaxed);
    value
}

pub fn info(path: &str, id3v1: bool, read: impl FnOnce() -> FlacInfo) -> FlacInfo {
    cached(
        |s| &mut s.infos,
        path.to_string(),
        stamp(path),
        |(_, checked)| *checked || !id3v1,
        || (read(), id3v1),
    )
    .0
}

pub fn thumb(path: &str, px: u32, read: impl FnOnce() -> Option<String>) -> Option<String> {
    cached(
        |s| &mut s.thumbs,
        format!("{px}:{path}"),
        stamp(path),
        |_| true,
        read,
    )
}

pub fn dims(
    path: &str,
    meta: &fs::Metadata,
    read: impl FnOnce() -> Option<(u32, u32)>,
) -> Option<(u32, u32)> {
    cached(
        |s| &mut s.dims,
        path.to_string(),
        Some(Stamp::of(meta)),
        |_| true,
        read,
    )
}
