mod cache;
mod files;
mod flac;
mod menu;
mod par;
mod repaint;
mod system;
mod tools;
mod watch;

use std::sync::Arc;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            cache::init(app.path().app_cache_dir()?);
            repaint::install(app.handle());
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(3));
                if let Some(w) = handle.get_webview_window("main") {
                    let _ = w.show();
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Focused(true) = event {
                if let Some(w) = window.app_handle().get_webview_window(window.label()) {
                    repaint::redraw_window(&w);
                }
            }
        })
        .menu(menu::build)
        .on_menu_event(menu::on_event)
        .manage(Arc::new(tools::ToolRuns::default()))
        .manage(watch::LibraryWatcher::default())
        .invoke_handler(tauri::generate_handler![
            files::list_tree,
            files::dir_contents,
            files::rename_path,
            files::rename_batch,
            files::reveal_in_finder,
            files::read_image,
            files::image_thumbnails,
            files::trash_path,
            flac::read_flacs,
            flac::read_picture,
            flac::read_thumbnails,
            flac::save_tags,
            flac::apply_tag_changes,
            flac::verify_flacs,
            flac::check_playlists,
            tools::bundled_tools_dir,
            tools::list_tools,
            tools::tool_help,
            tools::run_tool,
            tools::tool_stdin,
            tools::stop_tool,
            tools::load_chains,
            tools::save_chains,
            watch::watch_root,
            system::open_url,
            system::copy_text,
            repaint::window_buttons,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
