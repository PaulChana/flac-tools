use std::io::Write;
use std::process::{Command, Stdio};

#[tauri::command]
pub async fn open_url(url: String) -> Result<(), String> {
    if !url.starts_with("https://") {
        return Err(format!("Not a web link: {url}"));
    }
    Command::new("/usr/bin/open").arg(&url).status().map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn copy_text(text: String) -> Result<(), String> {
    let mut child = Command::new("/usr/bin/pbcopy")
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    child
        .stdin
        .take()
        .ok_or("No clipboard input")?
        .write_all(text.as_bytes())
        .map_err(|e| e.to_string())?;
    child.wait().map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_non_web_links() {
        assert!(tauri::async_runtime::block_on(open_url("file:///etc/passwd".into())).is_err());
        assert!(tauri::async_runtime::block_on(open_url("/Applications/Calculator.app".into())).is_err());
    }
}
