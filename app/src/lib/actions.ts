import { ask } from "@tauri-apps/plugin-dialog";
import { api } from "./api";
import { basename } from "./format";
import { app } from "./state.svelte";

export async function renameItem(path: string, newName: string): Promise<boolean> {
  try {
    const to = await api.renamePath(path, newName);
    app.renaming = null;
    if (to !== path) app.applyRename(path, to);
    return true;
  } catch (e) {
    app.showError(e);
    return false;
  }
}

export async function trashItems(paths: string[], isDir: boolean): Promise<void> {
  paths = paths.filter((p) => p !== app.root);
  if (!paths.length) return;
  const what =
    paths.length === 1
      ? `“${basename(paths[0])}”${isDir ? " and everything in it" : ""}`
      : `these ${paths.length} ${isDir ? "folders and everything in them" : "items"}`;
  const ok = await ask(`Move ${what} to the Trash?`, {
    title: "Move to Trash",
    kind: "warning",
    okLabel: "Move to Trash",
    cancelLabel: "Cancel",
  });
  if (!ok) return;
  for (const path of paths) {
    try {
      await api.trashPath(path);
      app.applyTrash(path);
    } catch (e) {
      app.showError(e);
      return;
    }
  }
}
