use tauri::{AppHandle, Manager, Runtime, WebviewWindow};

#[cfg(target_os = "macos")]
pub fn install<R: Runtime>(app: &AppHandle<R>) {
    use block2::RcBlock;
    use objc2_app_kit::{NSWorkspace, NSWorkspaceDidWakeNotification};
    use objc2_foundation::{NSNotification, NSOperationQueue};
    use std::ptr::NonNull;

    let app = app.clone();
    let block = RcBlock::new(move |_: NonNull<NSNotification>| {
        for window in app.webview_windows().values() {
            redraw_window(window);
        }
    });
    unsafe {
        let center = NSWorkspace::sharedWorkspace().notificationCenter();
        let token = center.addObserverForName_object_queue_usingBlock(
            Some(NSWorkspaceDidWakeNotification),
            None,
            Some(&NSOperationQueue::mainQueue()),
            &block,
        );
        std::mem::forget(token);
    }
}

#[cfg(not(target_os = "macos"))]
pub fn install<R: Runtime>(_app: &AppHandle<R>) {}

pub fn redraw_window<R: Runtime>(window: &WebviewWindow<R>) {
    #[cfg(target_os = "macos")]
    let _ = window.with_webview(|webview| unsafe {
        use objc2::msg_send;
        use objc2::runtime::AnyObject;
        let view = webview.inner() as *mut AnyObject;
        if let Some(view) = view.as_ref() {
            let layer: *mut AnyObject = msg_send![view, layer];
            if let Some(layer) = layer.as_ref() {
                let _: () = msg_send![layer, setNeedsDisplay];
            }
            let _: () = msg_send![view, setNeedsDisplay: true];
            let _: () = msg_send![view, setHidden: true];
            let _: () = msg_send![view, setHidden: false];
        }
    });
    if let Ok(size) = window.inner_size() {
        let mut nudged = size;
        nudged.width += 1;
        let _ = window.set_size(nudged);
        let _ = window.set_size(size);
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowButtons {
    center_y: f64,
    right: f64,
}

#[tauri::command]
pub fn window_buttons<R: Runtime>(window: WebviewWindow<R>) -> Result<WindowButtons, String> {
    #[cfg(target_os = "macos")]
    unsafe {
        use objc2::msg_send;
        use objc2::runtime::AnyObject;
        use objc2_foundation::NSRect;
        let ns_window = window.ns_window().map_err(|e| e.to_string())? as *mut AnyObject;
        let ns_window = ns_window.as_ref().ok_or("No window")?;
        let frame_of = |kind: usize| -> Option<NSRect> {
            let button: *mut AnyObject = msg_send![ns_window, standardWindowButton: kind];
            let button = button.as_ref()?;
            let frame: NSRect = msg_send![button, frame];
            let nil: *mut AnyObject = std::ptr::null_mut();
            let superview: *mut AnyObject = msg_send![button, superview];
            let in_window: NSRect = msg_send![superview.as_ref()?, convertRect: frame, toView: nil];
            Some(in_window)
        };
        let close = frame_of(0).ok_or("No close button")?;
        let zoom = frame_of(2).ok_or("No zoom button")?;
        let window_frame: NSRect = msg_send![ns_window, frame];
        let center_y = window_frame.size.height - (close.origin.y + close.size.height / 2.0);
        return Ok(WindowButtons { center_y, right: zoom.origin.x + zoom.size.width });
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = window;
        Err("Only on macOS".into())
    }
}
