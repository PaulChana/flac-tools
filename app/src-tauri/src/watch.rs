use notify_debouncer_mini::notify::{RecommendedWatcher, RecursiveMode};
use notify_debouncer_mini::{new_debouncer, DebounceEventResult, Debouncer};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, Emitter, State};

#[derive(Default)]
pub struct LibraryWatcher(Mutex<Option<Debouncer<RecommendedWatcher>>>);

fn is_hidden(path: &Path) -> bool {
    path.file_name()
        .map(|n| n.to_string_lossy().starts_with('.'))
        .unwrap_or(false)
}

fn changed_dirs<'a>(
    paths: impl Iterator<Item = &'a Path>,
    canonical: &Path,
    root: &Path,
) -> Vec<String> {
    let mut dirs = BTreeSet::new();
    for path in paths.filter(|p| !is_hidden(p)) {
        let path = match path.strip_prefix(canonical) {
            Ok(rel) if rel.as_os_str().is_empty() => root.to_path_buf(),
            Ok(rel) => root.join(rel),
            Err(_) => path.to_path_buf(),
        };
        if let Some(parent) = path.parent() {
            dirs.insert(parent.to_string_lossy().into_owned());
        }
        dirs.insert(path.to_string_lossy().into_owned());
    }
    dirs.into_iter().collect()
}

#[tauri::command]
pub async fn watch_root(
    app: AppHandle,
    watcher: State<'_, LibraryWatcher>,
    path: String,
) -> Result<(), String> {
    let mut slot = watcher.0.lock().unwrap();
    *slot = None;
    let root = PathBuf::from(&path);
    let canonical = std::fs::canonicalize(&root).map_err(|e| format!("Can't watch {path}: {e}"))?;
    let mut debouncer = new_debouncer(Duration::from_millis(500), move |res: DebounceEventResult| {
        let Ok(events) = res else { return };
        let dirs = changed_dirs(events.iter().map(|e| e.path.as_path()), &canonical, &root);
        if !dirs.is_empty() {
            let _ = app.emit("fs-changed", dirs);
        }
    })
    .map_err(|e| e.to_string())?;
    debouncer
        .watcher()
        .watch(Path::new(&path), RecursiveMode::Recursive)
        .map_err(|e| format!("Can't watch {path}: {e}"))?;
    *slot = Some(debouncer);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::mpsc;

    #[test]
    fn maps_resolved_paths_back_to_the_root_as_given() {
        let dirs = changed_dirs(
            [
                Path::new("/private/var/lib/A/Album/02.flac"),
                Path::new("/private/var/lib/A/.DS_Store"),
            ]
            .into_iter(),
            Path::new("/private/var/lib"),
            Path::new("/var/lib"),
        );
        assert_eq!(dirs, vec!["/var/lib/A/Album", "/var/lib/A/Album/02.flac"]);
    }

    #[test]
    fn merge_through_symlinked_root_reports_both_folders() {
        let root = std::env::temp_dir().join(format!("flac-watch-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("A/Album")).unwrap();
        fs::create_dir_all(root.join("A/Album (2)")).unwrap();
        fs::write(root.join("A/Album (2)/02.flac"), b"x").unwrap();
        std::thread::sleep(Duration::from_millis(600));

        let canonical = fs::canonicalize(&root).unwrap();
        let (tx, rx) = mpsc::channel();
        let mut d = new_debouncer(Duration::from_millis(300), tx).unwrap();
        d.watcher().watch(&root, RecursiveMode::Recursive).unwrap();
        std::thread::sleep(Duration::from_millis(300));
        fs::rename(root.join("A/Album (2)/02.flac"), root.join("A/Album/02.flac")).unwrap();
        fs::remove_dir(root.join("A/Album (2)")).unwrap();

        let mut seen = BTreeSet::new();
        while let Ok(Ok(events)) = rx.recv_timeout(Duration::from_secs(2)) {
            seen.extend(changed_dirs(events.iter().map(|e| e.path.as_path()), &canonical, &root));
        }
        let s = |p: &str| root.join(p).to_string_lossy().into_owned();
        for want in [s("A"), s("A/Album"), s("A/Album (2)")] {
            assert!(seen.contains(&want), "missing {want} in {seen:?}");
        }
        fs::remove_dir_all(root).unwrap();
    }
}
