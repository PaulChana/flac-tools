use tauri::menu::{IsMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{AppHandle, Emitter, Runtime};

type Item = (&'static str, &'static str, Option<&'static str>);

const APP_ITEMS: [Item; 2] = [("about", "About FLAC Tools", None), ("settings", "Settings…", Some("CmdOrCtrl+,"))];

const FILE_ITEMS: [Item; 2] = [("open", "Open…", Some("CmdOrCtrl+O")), ("refresh", "Refresh", Some("CmdOrCtrl+R"))];

const VIEW_GROUPS: [&[Item]; 4] = [
    &[("view-library", "Library", Some("CmdOrCtrl+1")), ("view-tools", "Tools", Some("CmdOrCtrl+2"))],
    &[
        ("zoom-in", "Zoom In", Some("CmdOrCtrl+=")),
        ("zoom-out", "Zoom Out", Some("CmdOrCtrl+-")),
        ("zoom-reset", "Actual Size", Some("CmdOrCtrl+0")),
    ],
    &[
        ("spacing-increase", "Increase Line Spacing", Some("CmdOrCtrl+Shift+=")),
        ("spacing-reduce", "Reduce Line Spacing", Some("CmdOrCtrl+Shift+-")),
        ("spacing-reset", "Reset Line Spacing", Some("CmdOrCtrl+Shift+0")),
    ],
    &[
        ("toggle-left", "Show or Hide Library", Some("CmdOrCtrl+Alt+1")),
        ("toggle-bottom", "Show or Hide Tool Output", Some("CmdOrCtrl+Alt+2")),
        ("toggle-right", "Show or Hide Tag Editor", Some("CmdOrCtrl+Alt+3")),
    ],
];

fn items<R: Runtime>(app: &AppHandle<R>, list: &[Item]) -> tauri::Result<Vec<MenuItem<R>>> {
    list.iter().map(|(id, text, keys)| MenuItem::with_id(app, *id, *text, true, *keys)).collect()
}

pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let menu = Menu::default(app)?;
    let submenus: Vec<Submenu<R>> = menu.items()?.into_iter().filter_map(|k| k.as_submenu().cloned()).collect();

    if let Some(app_menu) = submenus.first().filter(|_| cfg!(target_os = "macos")) {
        app_menu.remove_at(0)?;
        let own = items(app, &APP_ITEMS)?;
        let refs: Vec<&dyn IsMenuItem<R>> = own.iter().map(|i| i as _).collect();
        app_menu.insert_items(&refs, 0)?;
    }

    if let Some(file) = submenus.iter().find(|s| s.text().is_ok_and(|t| t == "File")) {
        let own = items(app, &FILE_ITEMS)?;
        let sep = PredefinedMenuItem::separator(app)?;
        let mut refs: Vec<&dyn IsMenuItem<R>> = own.iter().map(|i| i as _).collect();
        refs.push(&sep);
        file.insert_items(&refs, 0)?;
    }

    let view_items: Vec<Vec<MenuItem<R>>> = VIEW_GROUPS.iter().map(|g| items(app, g)).collect::<tauri::Result<_>>()?;
    let separators = (0..VIEW_GROUPS.len()).map(|_| PredefinedMenuItem::separator(app)).collect::<tauri::Result<Vec<_>>>()?;
    let mut refs: Vec<&dyn IsMenuItem<R>> = Vec::new();
    for (group, sep) in view_items.iter().zip(&separators) {
        refs.extend(group.iter().map(|i| i as &dyn IsMenuItem<R>));
        refs.push(sep);
    }
    match submenus.iter().find(|s| s.text().is_ok_and(|t| t == "View")) {
        Some(view) => view.insert_items(&refs, 0)?,
        None => {
            refs.pop();
            menu.append(&Submenu::with_items(app, "View", true, &refs)?)?
        }
    }
    Ok(menu)
}

pub fn on_event<R: Runtime>(app: &AppHandle<R>, event: MenuEvent) {
    let id = event.id().as_ref();
    let ours = APP_ITEMS
        .iter()
        .chain(&FILE_ITEMS)
        .chain(VIEW_GROUPS.iter().flat_map(|g| g.iter()))
        .any(|(i, _, _)| *i == id);
    if ours {
        let _ = app.emit("menu", id);
    }
}
