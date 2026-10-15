import { SvelteSet } from "svelte/reactivity";
import { ancestors, dirname, reparent } from "./format";

function load(key: string): string {
  try {
    return localStorage.getItem(key) ?? "";
  } catch {
    return "";
  }
}

function save(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
  }
}

class AppState {
  root = $state(load("root"));
  current = $state(load("root"));
  folders = $state<string[]>(load("root") ? [load("root")] : []);
  treeSelection = $state(load("root"));
  focusFile = $state<string | null>(null);
  expanded = new SvelteSet<string>();
  renaming = $state<string | null>(null);

  showFilesInTree = $state(load("showFilesInTree") === "1");
  recursive = $state(load("recursive") === "1");
  view = $state<"library" | "tools">("library");
  extraToolsDir = $state(load("extraToolsDir"));

  treeVersion = $state(0);
  contentVersion = $state(0);

  pendingRenames: { from: string; to: string }[] = [];

  check = $state<{ mode: "fast" | "full"; folders: string[] } | null>(null);

  startCheck(mode: "fast" | "full", folders: string[] = this.folders) {
    this.view = "library";
    this.check = { mode, folders: [...folders] };
  }

  toast = $state<{ kind: "error" | "info"; text: string } | null>(null);
  dialog = $state<"settings" | "about" | null>(null);

  constructor() {
    if (this.root) this.expanded.add(this.root);
  }

  setRoot(path: string) {
    this.root = path;
    this.current = path;
    this.folders = [path];
    this.treeSelection = path;
    this.expanded.clear();
    this.expanded.add(path);
    save("root", path);
    this.refresh();
  }

  setShowFilesInTree(v: boolean) {
    this.showFilesInTree = v;
    save("showFilesInTree", v ? "1" : "0");
  }

  setRecursive(v: boolean) {
    this.recursive = v;
    save("recursive", v ? "1" : "0");
  }

  setExtraToolsDir(v: string) {
    this.extraToolsDir = v;
    save("extraToolsDir", v);
  }

  refresh() {
    this.treeVersion++;
    this.contentVersion++;
  }

  openFolder(path: string) {
    if (path === this.current && this.treeSelection === path && this.folders.length === 1) return;
    this.current = path;
    this.folders = [path];
    this.treeSelection = path;
    this.focusFile = null;
    for (const a of ancestors(dirname(path), this.root)) this.expanded.add(a);
  }

  toggleFolder(path: string) {
    if (this.folders.includes(path)) {
      if (this.folders.length === 1) return;
      this.folders = this.folders.filter((p) => p !== path);
      if (this.current === path) this.current = this.folders[this.folders.length - 1];
      this.treeSelection = this.current;
    } else {
      this.folders = [...this.folders, path];
      this.current = path;
      this.treeSelection = path;
    }
    this.focusFile = null;
  }

  selectFolderRange(path: string, visible: string[]) {
    const a = visible.indexOf(this.current);
    const b = visible.indexOf(path);
    if (a < 0 || b < 0) return this.openFolder(path);
    this.folders = visible.slice(Math.min(a, b), Math.max(a, b) + 1);
    this.treeSelection = path;
    this.focusFile = null;
  }

  openFile(path: string) {
    this.current = dirname(path);
    this.folders = [this.current];
    this.treeSelection = path;
    this.focusFile = path;
    for (const a of ancestors(dirname(path), this.root)) this.expanded.add(a);
  }

  applyRename(from: string, to: string) {
    this.applyRenames([{ from, to }]);
  }

  applyRenames(renames: { from: string; to: string }[]) {
    for (const { from, to } of renames) this.reparentAll(from, to);
    this.pendingRenames.push(...renames);
    this.refresh();
  }

  applyTrash(path: string) {
    const inside = (p: string) => p === path || p.startsWith(path + "/");
    const parent = dirname(path);
    this.folders = this.folders.filter((p) => !inside(p));
    if (inside(this.current)) this.current = this.folders[0] ?? parent;
    if (!this.folders.length) this.folders = [this.current];
    if (inside(this.treeSelection)) this.treeSelection = parent;
    if (this.focusFile && inside(this.focusFile)) this.focusFile = null;
    for (const p of [...this.expanded]) if (inside(p)) this.expanded.delete(p);
    this.refresh();
  }

  private reparentAll(from: string, to: string) {
    if (this.root === from) {
      this.root = to;
      save("root", to);
    }
    this.current = reparent(this.current, from, to);
    this.folders = this.folders.map((p) => reparent(p, from, to));
    this.treeSelection = reparent(this.treeSelection, from, to);
    if (this.focusFile) this.focusFile = reparent(this.focusFile, from, to);
    const moved = [...this.expanded].filter((p) => reparent(p, from, to) !== p);
    for (const p of moved) {
      this.expanded.delete(p);
      this.expanded.add(reparent(p, from, to));
    }
  }

  handleFsChange(dirs: string[]) {
    if (dirs.some((d) => this.expanded.has(d) || this.expanded.has(dirname(d)))) this.treeVersion++;
    const affectsTables = dirs.some((d) =>
      this.folders.some(
        (cur) =>
          d === cur ||
          dirname(d) === cur ||
          (this.recursive && d.startsWith(cur + "/")),
      ),
    );
    if (affectsTables) this.contentVersion++;
  }

  showError(e: unknown) {
    this.toast = { kind: "error", text: String(e) };
  }

  showInfo(text: string) {
    this.toast = { kind: "info", text };
  }
}

export const app = new AppState();
