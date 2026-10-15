use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use crate::par::{par_map, IO_THREADS};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TreeNode {
    name: String,
    path: String,
    is_dir: bool,
    has_children: bool,
    cover: Option<String>,
    cover_modified: u64,
}

fn is_cover(name: &str) -> bool {
    let n = name.to_ascii_lowercase();
    matches!(n.as_str(), "cover.jpg" | "cover.jpeg" | "cover.png")
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DirSummary {
    name: String,
    path: String,
    subdirs: u32,
    flacs: u32,
    others: u32,
    modified: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileSummary {
    name: String,
    path: String,
    size: u64,
    modified: u64,
    width: Option<u32>,
    height: Option<u32>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DirContents {
    dirs: Vec<DirSummary>,
    flacs: Vec<String>,
    others: Vec<FileSummary>,
}

pub fn image_mime(path: &Path) -> Option<&'static str> {
    let ext = path.extension()?.to_str()?.to_ascii_lowercase();
    Some(match ext.as_str() {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "bmp" => "image/bmp",
        _ => return None,
    })
}

#[tauri::command]
pub async fn image_thumbnails(paths: Vec<String>, size: u32) -> Vec<Option<String>> {
    use base64::Engine;
    let one = |path: &String| -> Option<String> {
        crate::cache::thumb(path, size, || {
            let img = image::open(path).ok()?;
            let small = image::DynamicImage::ImageRgb8(img.thumbnail(size, size).to_rgb8());
            let mut out = std::io::Cursor::new(Vec::new());
            small.write_to(&mut out, image::ImageFormat::Jpeg).ok()?;
            Some(format!(
                "data:image/jpeg;base64,{}",
                base64::engine::general_purpose::STANDARD.encode(out.into_inner())
            ))
        })
    };
    par_map(&paths, IO_THREADS, one)
}

#[tauri::command]
pub async fn read_image(path: String) -> Result<String, String> {
    use base64::Engine;
    let mime = image_mime(Path::new(&path)).ok_or("Not an image file")?;
    let bytes = fs::read(&path).map_err(|e| format!("{path}: {e}"))?;
    Ok(format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    ))
}

pub fn is_flac(path: &Path) -> bool {
    path.extension()
        .map(|e| e.eq_ignore_ascii_case("flac"))
        .unwrap_or(false)
}

fn is_hidden(name: &str) -> bool {
    name.starts_with('.')
}

pub fn modified_secs(meta: &fs::Metadata) -> u64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn visible_entries(dir: &Path) -> Result<Vec<(String, PathBuf, fs::Metadata)>, String> {
    let read = fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let mut out: Vec<_> = read
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            if is_hidden(&name) {
                return None;
            }
            let meta = fs::metadata(e.path()).ok()?;
            if meta.is_file() {
                crate::cache::note(&e.path().to_string_lossy(), &meta);
            }
            Some((name, e.path(), meta))
        })
        .collect();
    out.sort_by_key(|(name, _, _)| name.to_lowercase());
    Ok(out)
}

#[tauri::command]
pub async fn list_tree(path: String, include_files: bool) -> Result<Vec<TreeNode>, String> {
    let mut dirs = Vec::new();
    let mut files = Vec::new();
    for (name, p, meta) in visible_entries(Path::new(&path))? {
        if meta.is_dir() {
            let kids = visible_entries(&p).unwrap_or_default();
            let has_children = kids
                .iter()
                .any(|(_, kp, km)| km.is_dir() || (include_files && is_flac(kp)));
            let cover = kids.iter().find(|(n, _, km)| km.is_file() && is_cover(n));
            dirs.push(TreeNode {
                name,
                path: p.to_string_lossy().into_owned(),
                is_dir: true,
                has_children,
                cover: cover.map(|(_, cp, _)| cp.to_string_lossy().into_owned()),
                cover_modified: cover.map(|(_, _, cm)| modified_secs(cm)).unwrap_or(0),
            });
        } else if include_files && is_flac(&p) {
            files.push(TreeNode {
                name,
                path: p.to_string_lossy().into_owned(),
                is_dir: false,
                has_children: false,
                cover: None,
                cover_modified: 0,
            });
        }
    }
    dirs.extend(files);
    Ok(dirs)
}

enum Entry {
    Dir(String, PathBuf, fs::Metadata),
    Flac(String),
    Other(FileSummary),
}

fn list_dir(dir: &Path, details: bool) -> Result<Vec<Entry>, String> {
    Ok(visible_entries(dir)?
        .into_iter()
        .map(|(name, p, meta)| {
            if meta.is_dir() {
                Entry::Dir(name, p, meta)
            } else if is_flac(&p) {
                Entry::Flac(p.to_string_lossy().into_owned())
            } else {
                let dims = image_mime(&p)
                    .filter(|_| details)
                    .and_then(|_| {
                        crate::cache::dims(&p.to_string_lossy(), &meta, || image::image_dimensions(&p).ok())
                    });
                Entry::Other(FileSummary {
                    name,
                    path: p.to_string_lossy().into_owned(),
                    size: meta.len(),
                    modified: modified_secs(&meta),
                    width: dims.map(|d| d.0),
                    height: dims.map(|d| d.1),
                })
            }
        })
        .collect())
}

fn subdirs(entries: &[Entry]) -> impl Iterator<Item = PathBuf> + '_ {
    entries.iter().filter_map(|e| match e {
        Entry::Dir(_, p, _) => Some(p.clone()),
        _ => None,
    })
}

fn assemble(entries: Vec<Entry>, listings: &mut HashMap<PathBuf, Vec<Entry>>, recursive: bool, out: &mut DirContents, top: bool) {
    for entry in entries {
        match entry {
            Entry::Dir(name, p, meta) => {
                if top {
                    let kids = listings.get(&p).map(Vec::as_slice).unwrap_or_default();
                    let count = |f: fn(&Entry) -> bool| kids.iter().filter(|e| f(e)).count() as u32;
                    out.dirs.push(DirSummary {
                        name,
                        path: p.to_string_lossy().into_owned(),
                        subdirs: count(|e| matches!(e, Entry::Dir(..))),
                        flacs: count(|e| matches!(e, Entry::Flac(_))),
                        others: count(|e| matches!(e, Entry::Other(_))),
                        modified: modified_secs(&meta),
                    });
                }
                if let Some(kids) = recursive.then(|| listings.remove(&p)).flatten() {
                    assemble(kids, listings, recursive, out, false);
                }
            }
            Entry::Flac(path) => out.flacs.push(path),
            Entry::Other(f) => out.others.push(f),
        }
    }
}

#[tauri::command]
pub async fn dir_contents(path: String, recursive: bool) -> Result<DirContents, String> {
    let top = list_dir(Path::new(&path), true)?;
    let mut listings = HashMap::new();
    let mut level: Vec<PathBuf> = subdirs(&top).collect();
    while !level.is_empty() {
        let got = par_map(&level, IO_THREADS, |d| list_dir(d, recursive).ok());
        let mut next = Vec::new();
        for (dir, entries) in level.into_iter().zip(got) {
            let Some(entries) = entries else { continue };
            if recursive {
                next.extend(subdirs(&entries));
            }
            listings.insert(dir, entries);
        }
        level = next;
    }
    let mut out = DirContents {
        dirs: Vec::new(),
        flacs: Vec::new(),
        others: Vec::new(),
    };
    assemble(top, &mut listings, recursive, &mut out, true);
    Ok(out)
}

fn check_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name == "." || name == ".." {
        return Err("Name can't be empty".into());
    }
    if name.contains('/') || name.contains('\0') {
        return Err(format!("'{name}' can't contain '/'"));
    }
    Ok(())
}

fn fold(p: &Path) -> String {
    p.to_string_lossy().to_lowercase()
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameItem {
    path: String,
    new_name: String,
}

#[tauri::command]
pub async fn rename_batch(items: Vec<RenameItem>) -> Result<Vec<String>, String> {
    let mut moves: Vec<(PathBuf, PathBuf)> = Vec::new();
    for it in &items {
        check_name(&it.new_name)?;
        let from = PathBuf::from(&it.path);
        let parent = from.parent().ok_or("Can't rename the filesystem root")?;
        let to = parent.join(&it.new_name);
        if to != from {
            moves.push((from, to));
        }
    }
    let sources: HashSet<String> = moves.iter().map(|(f, _)| fold(f)).collect();
    let mut targets = HashSet::new();
    for (from, to) in &moves {
        if !targets.insert(fold(to)) {
            return Err(format!("Two files would both be named '{}'", to.display()));
        }
        if to.exists() && !sources.contains(&fold(to)) && fold(to) != fold(from) {
            return Err(format!("'{}' already exists", to.display()));
        }
    }

    let temp_of = |i: usize, from: &Path| {
        from.with_file_name(format!(".flac-tools-rename-{}-{i}", std::process::id()))
    };
    for (i, (from, _)) in moves.iter().enumerate() {
        if let Err(e) = fs::rename(from, temp_of(i, from)) {
            for (j, (f, _)) in moves.iter().enumerate().take(i) {
                let _ = fs::rename(temp_of(j, f), f);
            }
            return Err(format!("Couldn't rename {}: {e}", from.display()));
        }
    }
    for (i, (from, to)) in moves.iter().enumerate() {
        if let Err(e) = fs::rename(temp_of(i, from), to) {
            for (j, (f, t)) in moves.iter().enumerate() {
                let src = if j < i { t.clone() } else { temp_of(j, f) };
                let _ = fs::rename(src, f);
            }
            return Err(format!("Couldn't rename {}: {e}", from.display()));
        }
    }
    Ok(items
        .iter()
        .map(|it| Path::new(&it.path).with_file_name(&it.new_name).to_string_lossy().into_owned())
        .collect())
}

#[tauri::command]
pub async fn rename_path(path: String, new_name: String) -> Result<String, String> {
    let new_name = new_name.trim();
    check_name(new_name)?;
    let from = PathBuf::from(&path);
    let parent = from.parent().ok_or("Can't rename the filesystem root")?;
    let to = parent.join(new_name);
    if to == from {
        return Ok(path);
    }
    let case_only = to.to_string_lossy().to_lowercase() == from.to_string_lossy().to_lowercase();
    if to.exists() && !case_only {
        return Err(format!("'{new_name}' already exists"));
    }
    fs::rename(&from, &to).map_err(|e| format!("Rename failed: {e}"))?;
    Ok(to.to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn trash_path(path: String) -> Result<(), String> {
    if !Path::new(&path).exists() {
        return Err(format!("'{path}' no longer exists"));
    }
    trash::delete(&path).map_err(|e| format!("Couldn't move to Trash: {e}"))
}

#[tauri::command]
pub async fn reveal_in_finder(path: String) -> Result<(), String> {
    std::process::Command::new("open")
        .arg("-R")
        .arg(&path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("flac-tools-rename-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn item(d: &Path, from: &str, to: &str) -> RenameItem {
        RenameItem { path: d.join(from).to_string_lossy().into_owned(), new_name: to.into() }
    }

    fn names(d: &Path) -> Vec<String> {
        let mut v: Vec<_> = fs::read_dir(d).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        v.sort();
        v
    }

    #[test]
    fn reports_image_dimensions() {
        let d = dir("dims");
        image::DynamicImage::new_rgb8(500, 498).save(d.join("cover.png")).unwrap();
        fs::write(d.join("notes.txt"), "hi").unwrap();
        fs::write(d.join("broken.jpg"), "not a jpeg").unwrap();
        let c = tauri::async_runtime::block_on(dir_contents(d.to_string_lossy().into(), false)).unwrap();
        let dims = |n: &str| {
            let f = c.others.iter().find(|o| o.name == n).unwrap();
            (f.width, f.height)
        };
        assert_eq!(dims("cover.png"), (Some(500), Some(498)));
        assert_eq!(dims("notes.txt"), (None, None));
        assert_eq!(dims("broken.jpg"), (None, None));
        let url = tauri::async_runtime::block_on(read_image(d.join("cover.png").to_string_lossy().into())).unwrap();
        assert!(url.starts_with("data:image/png;base64,"));
        assert!(tauri::async_runtime::block_on(read_image(d.join("notes.txt").to_string_lossy().into())).is_err());
        fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn recursive_listing_keeps_depth_first_name_order() {
        let d = dir("walk");
        for f in ["a.flac", "b/c.flac", "b/d/e.flac", "b/f.flac", "g.flac", "h/i.txt", "h/j/k.flac"] {
            let p = d.join(f);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, "").unwrap();
        }
        let c = tauri::async_runtime::block_on(dir_contents(d.to_string_lossy().into(), true)).unwrap();
        let rel = |p: &String| p.strip_prefix(&format!("{}/", d.display())).unwrap().to_string();
        assert_eq!(c.flacs.iter().map(rel).collect::<Vec<_>>(), ["a.flac", "b/c.flac", "b/d/e.flac", "b/f.flac", "g.flac", "h/j/k.flac"]);
        assert_eq!(c.others.iter().map(|o| rel(&o.path)).collect::<Vec<_>>(), ["h/i.txt"]);
        let b = &c.dirs[0];
        assert_eq!((b.name.as_str(), b.subdirs, b.flacs, b.others), ("b", 1, 2, 0));

        let flat = tauri::async_runtime::block_on(dir_contents(d.to_string_lossy().into(), false)).unwrap();
        assert_eq!(flat.flacs.iter().map(rel).collect::<Vec<_>>(), ["a.flac", "g.flac"]);
        assert_eq!(flat.dirs.iter().map(|x| (x.subdirs, x.flacs, x.others)).collect::<Vec<_>>(), [(1, 2, 0), (1, 0, 1)]);
        fs::remove_dir_all(d).unwrap();
    }

    #[test]
    #[ignore]
    fn trashes_folders() {
        let d = dir("trash");
        let target = d.join("flac-tools test folder (safe to delete)");
        fs::create_dir_all(target.join("CD 1")).unwrap();
        fs::write(target.join("CD 1/01.flac"), "x").unwrap();
        tauri::async_runtime::block_on(trash_path(target.to_string_lossy().into())).unwrap();
        assert!(!target.exists());
        assert!(tauri::async_runtime::block_on(trash_path(target.to_string_lossy().into())).is_err());
        fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn tree_reports_folder_covers() {
        let d = dir("covers");
        fs::create_dir_all(d.join("With Cover")).unwrap();
        fs::create_dir_all(d.join("Without")).unwrap();
        image::DynamicImage::new_rgb8(300, 200).save(d.join("With Cover/Cover.JPG")).unwrap();
        fs::write(d.join("Without/back.jpg"), "x").unwrap();
        let nodes = tauri::async_runtime::block_on(list_tree(d.to_string_lossy().into(), false)).unwrap();
        let cover = |n: &str| nodes.iter().find(|x| x.name == n).unwrap().cover.clone();
        let c = cover("With Cover").unwrap();
        assert!(c.ends_with("Cover.JPG"));
        assert_eq!(cover("Without"), None);
        let thumbs = tauri::async_runtime::block_on(image_thumbnails(vec![c, "/nope.jpg".into()], 28));
        assert!(thumbs[0].as_deref().unwrap().starts_with("data:image/jpeg;base64,"));
        assert!(thumbs[1].is_none());
        fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn renames_swaps_and_chains() {
        let d = dir("swap");
        for (n, body) in [("a.flac", "A"), ("b.flac", "B"), ("c.flac", "C")] {
            fs::write(d.join(n), body).unwrap();
        }
        tauri::async_runtime::block_on(rename_batch(vec![item(&d, "a.flac", "b.flac"), item(&d, "b.flac", "a.flac"), item(&d, "c.flac", "d.flac")])).unwrap();
        assert_eq!(names(&d), ["a.flac", "b.flac", "d.flac"]);
        assert_eq!(fs::read_to_string(d.join("b.flac")).unwrap(), "A");
        assert_eq!(fs::read_to_string(d.join("a.flac")).unwrap(), "B");
        fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn refuses_conflicts_without_touching_anything() {
        let d = dir("conflict");
        for n in ["a.flac", "b.flac", "keep.jpg"] {
            fs::write(d.join(n), n).unwrap();
        }
        assert!(tauri::async_runtime::block_on(rename_batch(vec![item(&d, "a.flac", "x.flac"), item(&d, "b.flac", "X.flac")])).is_err());
        assert!(tauri::async_runtime::block_on(rename_batch(vec![item(&d, "a.flac", "keep.jpg")])).is_err());
        assert!(tauri::async_runtime::block_on(rename_batch(vec![item(&d, "a.flac", "")])).is_err());
        assert_eq!(names(&d), ["a.flac", "b.flac", "keep.jpg"]);
        fs::remove_dir_all(d).unwrap();
    }
}

#[cfg(test)]
impl DirContents {
    pub fn flacs_for_bench(&self) -> Vec<String> {
        self.flacs.clone()
    }
}
