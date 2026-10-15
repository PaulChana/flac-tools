use base64::Engine;
use metaflac::block::{Block, Picture, PictureType};
use metaflac::Tag;
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::io::Cursor;
use std::fs;
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use crate::files::modified_secs;
use crate::par::{cpu_threads, par_map, IO_THREADS};

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FlacInfo {
    path: String,
    name: String,
    size: u64,
    modified: u64,
    tags: Vec<(String, String)>,
    vendor: String,
    duration: f64,
    sample_rate: u32,
    bits_per_sample: u8,
    channels: u8,
    pictures: u32,
    id3v2: bool,
    id3v1: bool,
    error: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PictureInfo {
    data_url: String,
    mime_type: String,
    width: u32,
    height: u32,
    kind: String,
    bytes: usize,
}

#[derive(Deserialize)]
pub struct TagChange {
    key: String,
    value: Option<String>,
}

fn scan_metadata(path: &Path, info: &mut FlacInfo, id3v1: bool) -> Result<(), String> {
    use metaflac::block::{StreamInfo, VorbisComment};
    use std::io::{BufReader, Read, Seek, SeekFrom};
    let err = |e: std::io::Error| e.to_string();
    let mut file = fs::File::open(path).map_err(err)?;
    if let Ok(meta) = file.metadata() {
        info.size = meta.len();
        info.modified = modified_secs(&meta);
    }
    let mut ident = [0u8; 4];
    if id3v1 {
        if file.seek(SeekFrom::End(-128)).is_ok() && file.read_exact(&mut ident[..3]).is_ok() {
            info.id3v1 = &ident[..3] == b"TAG";
        }
        file.seek(SeekFrom::Start(0)).map_err(err)?;
    }
    let mut r = BufReader::with_capacity(16 * 1024, file);

    r.read_exact(&mut ident).map_err(err)?;
    if &ident[..3] == b"ID3" {
        info.id3v2 = true;
        let mut head = [0u8; 6];
        r.read_exact(&mut head).map_err(err)?;
        let size = head[2..].iter().fold(0i64, |n, b| (n << 7) | (b & 0x7f) as i64);
        let footer = if head[1] & 0x10 != 0 { 10 } else { 0 };
        r.seek_relative(size + footer).map_err(err)?;
        r.read_exact(&mut ident).map_err(err)?;
    }
    if &ident != b"fLaC" {
        return Err("reader does not contain flac metadata".into());
    }
    loop {
        let mut head = [0u8; 4];
        r.read_exact(&mut head).map_err(err)?;
        let len = u32::from_be_bytes([0, head[1], head[2], head[3]]) as usize;
        match head[0] & 0x7f {
            kind @ (0 | 4) => {
                let mut data = vec![0u8; len];
                r.read_exact(&mut data).map_err(err)?;
                if kind == 4 {
                    let vc = VorbisComment::from_bytes(&data).map_err(|e| e.to_string())?;
                    info.vendor = vc.vendor_string;
                    let mut comments: Vec<_> = vc.comments.into_iter().collect();
                    comments.sort();
                    for (k, vs) in comments {
                        info.tags.extend(vs.into_iter().map(|v| (k.clone(), v)));
                    }
                } else if len >= 34 {
                    let si = StreamInfo::from_bytes(&data);
                    info.sample_rate = si.sample_rate;
                    info.bits_per_sample = si.bits_per_sample;
                    info.channels = si.num_channels;
                    if si.sample_rate > 0 {
                        info.duration = si.total_samples as f64 / si.sample_rate as f64;
                    }
                }
            }
            kind => {
                if kind == 6 {
                    info.pictures += 1;
                }
                r.seek_relative(len as i64).map_err(err)?;
            }
        }
        if head[0] & 0x80 != 0 {
            return Ok(());
        }
    }
}

fn read_info(path: &str) -> FlacInfo {
    read_info_with(path, true)
}

fn read_info_with(path: &str, id3v1: bool) -> FlacInfo {
    let p = Path::new(path);
    let mut info = FlacInfo {
        path: path.to_string(),
        name: p
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default(),
        size: 0,
        modified: 0,
        tags: Vec::new(),
        vendor: String::new(),
        duration: 0.0,
        sample_rate: 0,
        bits_per_sample: 0,
        channels: 0,
        pictures: 0,
        id3v2: false,
        id3v1: false,
        error: None,
    };
    if let Err(e) = scan_metadata(p, &mut info, id3v1) {
        info.error = Some(e);
    }
    info
}

#[tauri::command]
pub async fn read_flacs(paths: Vec<String>, id3v1: Option<bool>) -> Vec<FlacInfo> {
    let id3v1 = id3v1.unwrap_or(true);
    par_map(&paths, IO_THREADS, |p| crate::cache::info(p, id3v1, || read_info_with(p, id3v1)))
}

fn front_picture(tag: &Tag) -> Option<&Picture> {
    let pics: Vec<_> = tag.pictures().collect();
    pics.iter()
        .find(|p| p.picture_type == PictureType::CoverFront)
        .or(pics.first())
        .copied()
}

#[tauri::command]
pub async fn read_picture(path: String) -> Result<Option<PictureInfo>, String> {
    let tag = Tag::read_from_path(&path).map_err(|e| e.to_string())?;
    let pic = front_picture(&tag);
    Ok(pic.map(|p| {
        let mime = if p.mime_type.is_empty() {
            "image/jpeg".to_string()
        } else {
            p.mime_type.clone()
        };
        PictureInfo {
            data_url: format!(
                "data:{mime};base64,{}",
                base64::engine::general_purpose::STANDARD.encode(&p.data)
            ),
            mime_type: mime,
            width: p.width,
            height: p.height,
            kind: format!("{:?}", p.picture_type),
            bytes: p.data.len(),
        }
    }))
}

fn thumb_cache() -> &'static Mutex<HashMap<(u64, u32), Option<String>>> {
    static CACHE: OnceLock<Mutex<HashMap<(u64, u32), Option<String>>>> = OnceLock::new();
    CACHE.get_or_init(Default::default)
}

fn thumbnail(path: &str, size: u32) -> Option<String> {
    let tag = Tag::read_from_path(path).ok()?;
    let data = &front_picture(&tag)?.data;
    let mut h = DefaultHasher::new();
    data.hash(&mut h);
    let key = (h.finish(), size);
    if let Some(hit) = thumb_cache().lock().unwrap().get(&key) {
        return hit.clone();
    }
    let made = image::load_from_memory(data).ok().and_then(|img| {
        let small = image::DynamicImage::ImageRgb8(img.thumbnail(size, size).to_rgb8());
        let mut out = Cursor::new(Vec::new());
        small.write_to(&mut out, image::ImageFormat::Jpeg).ok()?;
        Some(format!(
            "data:image/jpeg;base64,{}",
            base64::engine::general_purpose::STANDARD.encode(out.into_inner())
        ))
    });
    thumb_cache().lock().unwrap().insert(key, made.clone());
    made
}

#[tauri::command]
pub async fn read_thumbnails(paths: Vec<String>, size: u32) -> Vec<Option<String>> {
    par_map(&paths, IO_THREADS, |p| crate::cache::thumb(p, size, || thumbnail(p, size)))
}

fn metadata_len(tag: &Tag, include_padding: bool) -> u32 {
    tag.blocks()
        .filter(|b| include_padding || !matches!(b, Block::Padding(_)))
        .map(|b| b.write_to(false, &mut Vec::new()).unwrap_or(0))
        .sum()
}

fn edit_tag(path: &str, edit: impl FnOnce(&mut Tag)) -> Result<(), String> {
    crate::cache::forget(path);
    let err = |e: &dyn std::fmt::Display| format!("{path}: {e}");
    let mut tag = Tag::read_from_path(path).map_err(|e| err(&e))?;
    let available = metadata_len(&tag, true);
    edit(&mut tag);
    if metadata_len(&tag, false) + 4 <= available {
        return tag.save().map_err(|e| err(&e));
    }
    let p = Path::new(path);
    let tmp = p.with_file_name(format!(
        ".{}.flac-tools-tmp",
        p.file_name().unwrap_or_default().to_string_lossy()
    ));
    let result = fs::copy(p, &tmp)
        .map_err(|e| err(&e))
        .and_then(|_| tag.write_to_path(&tmp).map_err(|e| err(&e)))
        .and_then(|_| fs::rename(&tmp, p).map_err(|e| err(&e)));
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

fn normalize_key(key: &str) -> Result<String, String> {
    let k = key.trim().to_ascii_uppercase();
    if k.is_empty() || k.chars().any(|c| !(' '..='}').contains(&c) || c == '=') {
        return Err(format!("Invalid tag name '{key}'"));
    }
    Ok(k)
}

#[tauri::command]
pub async fn save_tags(path: String, tags: Vec<(String, String)>) -> Result<FlacInfo, String> {
    let mut comments: HashMap<String, Vec<String>> = HashMap::new();
    for (k, v) in tags {
        comments.entry(normalize_key(&k)?).or_default().push(v);
    }
    edit_tag(&path, |tag| tag.vorbis_comments_mut().comments = comments)?;
    Ok(read_info(&path))
}

#[tauri::command]
pub async fn apply_tag_changes(
    paths: Vec<String>,
    changes: Vec<TagChange>,
) -> Result<Vec<FlacInfo>, String> {
    let changes: Vec<(String, Option<String>)> = changes
        .into_iter()
        .map(|c| normalize_key(&c.key).map(|k| (k, c.value)))
        .collect::<Result<_, _>>()?;
    let mut errors = Vec::new();
    for path in &paths {
        let result = edit_tag(path, |tag| {
            let vc = tag.vorbis_comments_mut();
            for (k, v) in &changes {
                match v {
                    Some(v) => vc.set(k.clone(), vec![v.clone()]),
                    None => vc.remove(k),
                }
            }
        });
        if let Err(e) = result {
            errors.push(e);
        }
    }
    if !errors.is_empty() {
        return Err(errors.join("\n"));
    }
    Ok(paths.iter().map(|p| read_info(p)).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    fn sample(dir: &Path, name: &str) -> Option<String> {
        let raw = dir.join("silence.raw");
        fs::write(&raw, vec![0u8; 44100 * 4]).unwrap();
        let out = dir.join(name);
        let ok = Command::new("flac")
            .args(["-s", "-f", "--force-raw-format", "--endian=little", "--sign=signed"])
            .args(["--channels=2", "--bps=16", "--sample-rate=44100", "-o"])
            .arg(&out)
            .arg(&raw)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        ok.then(|| out.to_string_lossy().into_owned())
    }

    fn temp_dir(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("flac-tools-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn decodes(path: &str) -> bool {
        Command::new("flac").args(["-t", "-s", path]).status().map(|s| s.success()).unwrap_or(false)
    }

    #[test]
    fn save_and_batch_edit_round_trip() {
        let dir = temp_dir("roundtrip");
        let Some(a) = sample(&dir, "a.flac") else { return };
        let b = sample(&dir, "b.flac").unwrap();

        let tags = vec![
            ("title".to_string(), "Hello".to_string()),
            ("ARTIST".to_string(), "One".to_string()),
            ("ARTIST".to_string(), "Two".to_string()),
        ];
        let info = tauri::async_runtime::block_on(save_tags(a.clone(), tags)).unwrap();
        assert_eq!(
            info.tags,
            vec![
                ("ARTIST".into(), "One".into()),
                ("ARTIST".into(), "Two".into()),
                ("TITLE".into(), "Hello".into()),
            ]
        );
        assert!((info.duration - 1.0).abs() < 0.01);

        let changes = vec![
            TagChange { key: "album".into(), value: Some("Shared".into()) },
            TagChange { key: "TITLE".into(), value: None },
        ];
        let infos =
            tauri::async_runtime::block_on(apply_tag_changes(vec![a.clone(), b.clone()], changes)).unwrap();
        for i in &infos {
            assert!(i.tags.contains(&("ALBUM".into(), "Shared".into())));
            assert!(!i.tags.iter().any(|(k, _)| k == "TITLE"));
        }
        assert!(decodes(&a) && decodes(&b));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn outgrowing_padding_keeps_audio_intact() {
        let dir = temp_dir("grow");
        let Some(a) = sample(&dir, "a.flac") else { return };
        let big = "x".repeat(64 * 1024);
        let info = tauri::async_runtime::block_on(save_tags(a.clone(), vec![("LYRICS".into(), big.clone())])).unwrap();
        assert_eq!(info.tags, vec![("LYRICS".into(), big)]);
        assert!(decodes(&a));
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 2, "temp file left behind");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn thumbnails_embedded_cover() {
        let dir = temp_dir("thumb");
        let Some(a) = sample(&dir, "a.flac") else { return };
        let b = sample(&dir, "b.flac").unwrap();
        let mut png = Cursor::new(Vec::new());
        image::DynamicImage::new_rgb8(600, 400).write_to(&mut png, image::ImageFormat::Png).unwrap();
        let mut tag = Tag::read_from_path(&a).unwrap();
        tag.add_picture("image/png", PictureType::CoverFront, png.into_inner());
        tag.save().unwrap();

        tag.set_vorbis("TITLE", vec!["After"]);
        tag.save().unwrap();
        let infos = tauri::async_runtime::block_on(read_flacs(vec![a.clone(), b.clone()], None));
        assert_eq!((infos[0].pictures, infos[1].pictures), (1, 0));
        assert_eq!(infos[0].tags, vec![("TITLE".into(), "After".into())]);
        assert!((infos[0].duration - 1.0).abs() < 0.01 && infos[0].error.is_none());

        let thumbs = tauri::async_runtime::block_on(read_thumbnails(vec![a, b], 48));
        let url = thumbs[0].as_deref().unwrap();
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(url.trim_start_matches("data:image/jpeg;base64,"))
            .unwrap();
        let img = image::load_from_memory(&bytes).unwrap();
        assert_eq!((img.width(), img.height()), (48, 32));
        assert!(thumbs[1].is_none());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn detects_id3_and_verifies() {
        let dir = temp_dir("id3");
        let Some(a) = sample(&dir, "a.flac") else { return };
        let clean = sample(&dir, "clean.flac").unwrap();
        let body = fs::read(&a).unwrap();
        let mut tagged = b"ID3\x03\x00\x00\x00\x00\x00\x00".to_vec();
        tagged.extend(&body);
        let mut v1 = b"TAG".to_vec();
        v1.resize(128, b' ');
        tagged.extend(&v1);
        fs::write(&a, tagged).unwrap();

        let infos = tauri::async_runtime::block_on(read_flacs(vec![a.clone(), clean.clone()], None));
        assert!(infos[0].id3v2 && infos[0].id3v1 && infos[0].error.is_none());
        assert!(!infos[1].id3v2 && !infos[1].id3v1);

        let m3u = dir.join("list.m3u");
        fs::write(&m3u, "#EXTM3U\nclean.flac\ngone.flac\n").unwrap();
        let checks = tauri::async_runtime::block_on(check_playlists(vec![m3u.to_string_lossy().into()]));
        assert_eq!(checks[0].missing, vec!["gone.flac"]);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn cache_follows_edits_from_the_app_and_elsewhere() {
        let dir = temp_dir("cache");
        let Some(a) = sample(&dir, "a.flac") else { return };
        let title = |infos: Vec<FlacInfo>| tagged(&infos[0], "TITLE");
        crate::cache::init(dir.join("cache"));

        tauri::async_runtime::block_on(crate::files::dir_contents(dir.to_string_lossy().into(), false)).unwrap();
        assert_eq!(title(tauri::async_runtime::block_on(read_flacs(vec![a.clone()], None))), None);

        tauri::async_runtime::block_on(save_tags(a.clone(), vec![("TITLE".into(), "One".into())])).unwrap();
        assert_eq!(title(tauri::async_runtime::block_on(read_flacs(vec![a.clone()], None))), Some("One".into()));

        let mut tag = Tag::read_from_path(&a).unwrap();
        tag.set_vorbis("TITLE", vec!["Two"]);
        tag.save().unwrap();
        tauri::async_runtime::block_on(crate::files::dir_contents(dir.to_string_lossy().into(), false)).unwrap();
        assert_eq!(title(tauri::async_runtime::block_on(read_flacs(vec![a.clone()], None))), Some("Two".into()));

        std::thread::sleep(std::time::Duration::from_secs(6));
        let saved = fs::read_to_string(dir.join("cache/file-cache.json")).unwrap();
        assert!(saved.contains("a.flac") && saved.contains("Two"));
        fs::remove_dir_all(dir).unwrap();
    }

    fn tagged(info: &FlacInfo, key: &str) -> Option<String> {
        info.tags.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone())
    }

    #[test]
    fn rejects_bad_keys() {
        assert!(normalize_key("A=B").is_err());
        assert!(normalize_key("").is_err());
        assert_eq!(normalize_key(" date ").unwrap(), "DATE");
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct VerifyResult {
    path: String,
    ok: bool,
    message: Option<String>,
}

#[derive(Serialize, Clone)]
struct VerifyProgress {
    done: usize,
    total: usize,
}

#[tauri::command]
pub async fn verify_flacs(app: tauri::AppHandle, paths: Vec<String>) -> Vec<VerifyResult> {
    use std::process::Command;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tauri::Emitter;
    let total = paths.len();
    let done = AtomicUsize::new(0);
    let path_env = format!("/opt/homebrew/bin:/usr/local/bin:{}", std::env::var("PATH").unwrap_or_default());
    par_map(&paths, cpu_threads(), |path| {
        let out = Command::new("flac").args(["-t", "-s"]).arg(path).env("PATH", &path_env).output();
        let r = match out {
            Err(e) => VerifyResult { path: path.clone(), ok: false, message: Some(format!("Couldn't run flac: {e}")) },
            Ok(o) => {
                let err = String::from_utf8_lossy(&o.stderr);
                let problem = err
                    .lines()
                    .find(|l| l.contains("ERROR") || l.contains("error code"))
                    .map(|l| l.splitn(2, ": ").nth(1).unwrap_or(l).trim().to_string());
                let ok = o.status.success() && problem.is_none();
                let message = (!ok).then(|| problem.unwrap_or_else(|| err.trim().to_string()));
                VerifyResult { path: path.clone(), ok, message }
            }
        };
        let d = done.fetch_add(1, Ordering::Relaxed) + 1;
        if d % 5 == 0 || d == total {
            let _ = app.emit("verify-progress", VerifyProgress { done: d, total });
        }
        r
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaylistCheck {
    playlist: String,
    missing: Vec<String>,
}

#[tauri::command]
pub async fn check_playlists(paths: Vec<String>) -> Vec<PlaylistCheck> {
    par_map(&paths, IO_THREADS, |playlist| {
            let text = fs::read(playlist).ok()?;
            let text = String::from_utf8_lossy(&text);
            let dir = Path::new(playlist).parent()?.to_path_buf();
            let missing = text
                .lines()
                .map(|l| l.trim().trim_start_matches('\u{feff}'))
                .filter(|l| !l.is_empty() && !l.starts_with('#') && !l.contains("://"))
                .filter(|l| {
                    let p = Path::new(l);
                    !(if p.is_absolute() { p.to_path_buf() } else { dir.join(p) }).exists()
                })
                .map(String::from)
                .collect();
            Some(PlaylistCheck { playlist: playlist.clone(), missing })
        })
        .into_iter()
        .flatten()
        .collect()
}

#[cfg(test)]
#[test]
#[ignore]
fn bench_check() {
    use std::time::Instant;
    let Ok(dir) = std::env::var("CHECK_DIR") else { return };
    let mode = std::env::var("BENCH_MODE").unwrap_or("fast".into());
    let t = Instant::now();
    let c = tauri::async_runtime::block_on(crate::files::dir_contents(dir, true)).unwrap();
    let flacs = c.flacs_for_bench();
    eprintln!("list: {:?} ({} flacs)", t.elapsed(), flacs.len());
    let t = Instant::now();
    match mode.as_str() {
        "old" => drop(par_map(&flacs, IO_THREADS, |p| Tag::read_from_path(p).map(|t| t.pictures().count()).ok())),
        m => drop(par_map(&flacs, IO_THREADS, |p| read_info_with(p, m == "full"))),
    }
    let ms = t.elapsed().as_millis() as usize / flacs.len().max(1);
    eprintln!("tags ({mode}): {:?}, {ms} ms per file", t.elapsed());

    for pass in ["cold", "cached"] {
        let t = Instant::now();
        tauri::async_runtime::block_on(read_flacs(flacs.clone(), None));
        let tags = t.elapsed();
        let t = Instant::now();
        tauri::async_runtime::block_on(read_thumbnails(flacs.clone(), 64));
        eprintln!("{pass}: tags {tags:?}, thumbnails {:?}", t.elapsed());
    }
}
