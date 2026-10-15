use serde::Serialize;
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager, State};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolInfo {
    name: String,
    path: String,
    description: String,
    usage: String,
    source: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolList {
    tools: Vec<ToolInfo>,
    extra_error: Option<String>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct OutputEvent {
    id: u32,
    stream: &'static str,
    text: String,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ExitEvent {
    id: u32,
    code: Option<i32>,
}

struct Running {
    child: Arc<Mutex<Child>>,
    stdin: Option<ChildStdin>,
}

#[derive(Default)]
pub struct ToolRuns {
    next_id: AtomicU32,
    runs: Mutex<HashMap<u32, Running>>,
}

fn tool_path_env() -> String {
    let current = std::env::var("PATH").unwrap_or_default();
    format!("/opt/homebrew/bin:/usr/local/bin:{current}:/usr/bin:/bin")
}

fn find_fish() -> PathBuf {
    for p in ["/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/usr/bin/fish"] {
        if Path::new(p).exists() {
            return PathBuf::from(p);
        }
    }
    PathBuf::from("fish")
}

fn bundled_dir(app: &AppHandle) -> Result<PathBuf, String> {
    if cfg!(debug_assertions) {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        return Ok(fs::canonicalize(&repo).unwrap_or(repo));
    }
    Ok(app.path().resource_dir().map_err(|e| e.to_string())?.join("scripts"))
}

#[tauri::command]
pub async fn bundled_tools_dir(app: AppHandle) -> Result<String, String> {
    Ok(bundled_dir(&app)?.to_string_lossy().into_owned())
}

fn parse_header(text: &str) -> (String, String) {
    let mut desc = Vec::new();
    let mut usage = Vec::new();
    let mut in_usage = false;
    for line in text.lines().skip(1) {
        let Some(rest) = line.strip_prefix('#') else { break };
        let rest = rest.strip_prefix(' ').unwrap_or(rest);
        if let Some(u) = rest.strip_prefix("Usage:") {
            in_usage = true;
            usage.push(u.trim().trim_start_matches("./").to_string());
        } else if in_usage && rest.starts_with(char::is_whitespace) && !rest.trim().is_empty() {
            usage.push(rest.trim().to_string());
        } else {
            in_usage = false;
            desc.push(rest.to_string());
        }
    }
    let description = desc.join("\n").trim().to_string();
    (description, usage.join(" "))
}

fn chains_file(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    Ok(dir.join("chains.json"))
}

#[tauri::command]
pub async fn load_chains(app: AppHandle) -> Result<String, String> {
    match fs::read_to_string(chains_file(&app)?) {
        Ok(s) => Ok(s),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok("[]".into()),
        Err(e) => Err(format!("Couldn't read saved chains: {e}")),
    }
}

#[tauri::command]
pub async fn save_chains(app: AppHandle, json: String) -> Result<(), String> {
    serde_json::from_str::<serde_json::Value>(&json).map_err(|e| format!("Bad chains data: {e}"))?;
    let path = chains_file(&app)?;
    fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, json)
        .and_then(|_| fs::rename(&tmp, &path))
        .map_err(|e| format!("Couldn't save chains: {e}"))
}

#[tauri::command]
pub async fn list_tools(app: AppHandle, extra_dir: Option<String>) -> Result<ToolList, String> {
    let bundled = bundled_dir(&app)?;
    let mut tools = scan_dir(&bundled, "bundled").map_err(|e| format!("Bundled scripts missing: {e}"))?;
    tools.retain(|t| t.name.starts_with("flac-"));
    let mut extra_error = None;
    if let Some(dir) = extra_dir.filter(|d| !d.is_empty()) {
        match scan_dir(Path::new(&dir), "extra") {
            Ok(extra) => {
                tools.retain(|t| !extra.iter().any(|e| e.name == t.name));
                tools.extend(extra);
            }
            Err(e) => extra_error = Some(e),
        }
    }
    tools.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(ToolList { tools, extra_error })
}

fn scan_dir(dir: &Path, source: &'static str) -> Result<Vec<ToolInfo>, String> {
    let mut tools = Vec::new();
    for entry in fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))? {
        let path = entry.map_err(|e| e.to_string())?.path();
        if path.extension().and_then(|e| e.to_str()) != Some("fish") {
            continue;
        }
        let Ok(text) = fs::read_to_string(&path) else { continue };
        if !text.starts_with("#!") {
            continue;
        }
        let (description, usage) = parse_header(&text);
        tools.push(ToolInfo {
            name: path.file_stem().unwrap().to_string_lossy().into_owned(),
            path: path.to_string_lossy().into_owned(),
            description,
            usage,
            source,
        });
    }
    Ok(tools)
}

#[tauri::command]
pub async fn tool_help(path: String) -> Result<String, String> {
    let out = Command::new(find_fish())
        .arg(&path)
        .arg("--help")
        .env("PATH", tool_path_env())
        .output()
        .map_err(|e| e.to_string())?;
    Ok(String::from_utf8_lossy(&out.stdout).into_owned()
        + &String::from_utf8_lossy(&out.stderr))
}

fn pump(
    app: AppHandle,
    id: u32,
    stream: &'static str,
    mut pipe: impl Read + Send + 'static,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        let mut pending: Vec<u8> = Vec::new();
        loop {
            let n = match pipe.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => n,
            };
            pending.extend_from_slice(&buf[..n]);
            let valid = match std::str::from_utf8(&pending) {
                Ok(_) => pending.len(),
                Err(e) if e.error_len().is_none() => e.valid_up_to(),
                Err(_) => pending.len(),
            };
            let text = String::from_utf8_lossy(&pending[..valid]).into_owned();
            pending.drain(..valid);
            if !text.is_empty() {
                let _ = app.emit("tool-output", OutputEvent { id, stream, text });
            }
        }
        if !pending.is_empty() {
            let text = String::from_utf8_lossy(&pending).into_owned();
            let _ = app.emit("tool-output", OutputEvent { id, stream, text });
        }
    })
}

#[tauri::command]
pub fn run_tool(
    app: AppHandle,
    runs: State<'_, Arc<ToolRuns>>,
    path: String,
    args: Vec<String>,
    cwd: String,
) -> Result<u32, String> {
    let lib = bundled_dir(&app)?.join("flac-lib.fish");
    let mut child = Command::new(find_fish())
        .arg(&path)
        .args(&args)
        .current_dir(&cwd)
        .env("PATH", tool_path_env())
        .env("FLAC_TOOLS_LIB", lib)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()
        .map_err(|e| format!("Couldn't start fish: {e}"))?;

    let id = runs.next_id.fetch_add(1, Ordering::SeqCst) + 1;
    let pumps = [
        pump(app.clone(), id, "stdout", child.stdout.take().unwrap()),
        pump(app.clone(), id, "stderr", child.stderr.take().unwrap()),
    ];
    let stdin = child.stdin.take();
    let child = Arc::new(Mutex::new(child));
    runs.runs.lock().unwrap().insert(
        id,
        Running {
            child: child.clone(),
            stdin,
        },
    );

    let runs = runs.inner().clone();
    thread::spawn(move || {
        let code = loop {
            match child.lock().unwrap().try_wait() {
                Ok(Some(status)) => break status.code(),
                Ok(None) => {}
                Err(_) => break None,
            }
            thread::sleep(Duration::from_millis(100));
        };
        runs.runs.lock().unwrap().remove(&id);
        for _ in 0..50 {
            if pumps.iter().all(|p| p.is_finished()) {
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        let _ = app.emit("tool-exit", ExitEvent { id, code });
    });
    Ok(id)
}

#[tauri::command]
pub fn tool_stdin(runs: State<'_, Arc<ToolRuns>>, id: u32, text: String) -> Result<(), String> {
    let mut map = runs.runs.lock().unwrap();
    let run = map.get_mut(&id).ok_or("Tool is no longer running")?;
    let stdin = run.stdin.as_mut().ok_or("Tool has no input")?;
    stdin
        .write_all(text.as_bytes())
        .and_then(|_| stdin.flush())
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn stop_tool(runs: State<'_, Arc<ToolRuns>>, id: u32) -> Result<(), String> {
    let map = runs.runs.lock().unwrap();
    let run = map.get(&id).ok_or("Tool is no longer running")?;
    let pid = run.child.lock().unwrap().id();
    Command::new("/bin/kill")
        .args(["-TERM", "--", &format!("-{pid}")])
        .status()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_multiline_usage() {
        let text = "#!/usr/bin/env fish\n# Does a thing.\n#\n# Usage: ./x.fish [--a] [--b]\n#                [--path=DIR]\n\nset x 1\n";
        let (desc, usage) = parse_header(text);
        assert_eq!(desc, "Does a thing.");
        assert_eq!(usage, "x.fish [--a] [--b] [--path=DIR]");
    }

    #[test]
    fn lists_repo_scripts_without_the_library() {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let tools = scan_dir(&repo, "bundled").unwrap();
        assert!(tools.iter().any(|t| t.name == "flac-ensure-year-and-date-match"));
        assert!(!tools.iter().any(|t| t.name == "flac-lib"));
        assert!(tools.iter().all(|t| !t.usage.is_empty()), "every script should have a Usage line");
    }
}
