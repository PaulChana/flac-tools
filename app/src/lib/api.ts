import { invoke } from "@tauri-apps/api/core";

export interface TreeNode {
  name: string;
  path: string;
  isDir: boolean;
  hasChildren: boolean;
  cover: string | null;
  coverModified: number;
}

export interface DirSummary {
  name: string;
  path: string;
  subdirs: number;
  flacs: number;
  others: number;
  modified: number;
}

export interface FileSummary {
  name: string;
  path: string;
  size: number;
  modified: number;
  width: number | null;
  height: number | null;
}

export interface DirContents {
  dirs: DirSummary[];
  flacs: string[];
  others: FileSummary[];
}

export type TagPair = [string, string];

export interface FlacInfo {
  path: string;
  name: string;
  size: number;
  modified: number;
  tags: TagPair[];
  vendor: string;
  duration: number;
  sampleRate: number;
  bitsPerSample: number;
  channels: number;
  pictures: number;
  id3v2: boolean;
  id3v1: boolean;
  error: string | null;
}

export interface VerifyResult {
  path: string;
  ok: boolean;
  message: string | null;
}

export interface PlaylistCheck {
  playlist: string;
  missing: string[];
}

export interface PictureInfo {
  dataUrl: string;
  mimeType: string;
  width: number;
  height: number;
  kind: string;
  bytes: number;
}

export interface TagChange {
  key: string;
  value: string | null;
}

export interface ToolInfo {
  name: string;
  path: string;
  description: string;
  usage: string;
  builtin?: boolean;
  source?: "bundled" | "extra";
}

export interface ToolList {
  tools: ToolInfo[];
  extraError: string | null;
}

export const api = {
  listTree: (path: string, includeFiles: boolean) =>
    invoke<TreeNode[]>("list_tree", { path, includeFiles }),
  dirContents: (path: string, recursive: boolean) =>
    invoke<DirContents>("dir_contents", { path, recursive }),
  renamePath: (path: string, newName: string) =>
    invoke<string>("rename_path", { path, newName }),
  renameBatch: (items: { path: string; newName: string }[]) =>
    invoke<string[]>("rename_batch", { items }),
  imageThumbnails: (paths: string[], size: number) =>
    invoke<(string | null)[]>("image_thumbnails", { paths, size }),
  readImage: (path: string) => invoke<string>("read_image", { path }),
  trashPath: (path: string) => invoke<void>("trash_path", { path }),
  revealInFinder: (path: string) => invoke<void>("reveal_in_finder", { path }),

  readFlacs: (paths: string[], id3v1 = true) => invoke<FlacInfo[]>("read_flacs", { paths, id3v1 }),
  verifyFlacs: (paths: string[]) => invoke<VerifyResult[]>("verify_flacs", { paths }),
  checkPlaylists: (paths: string[]) => invoke<PlaylistCheck[]>("check_playlists", { paths }),
  readPicture: (path: string) => invoke<PictureInfo | null>("read_picture", { path }),
  readThumbnails: (paths: string[], size: number) =>
    invoke<(string | null)[]>("read_thumbnails", { paths, size }),
  saveTags: (path: string, tags: TagPair[]) => invoke<FlacInfo>("save_tags", { path, tags }),
  applyTagChanges: (paths: string[], changes: TagChange[]) =>
    invoke<FlacInfo[]>("apply_tag_changes", { paths, changes }),

  watchRoot: (path: string) => invoke<void>("watch_root", { path }),
  openUrl: (url: string) => invoke<void>("open_url", { url }),
  windowButtons: () => invoke<{ centerY: number; right: number }>("window_buttons"),
  copyText: (text: string) => invoke<void>("copy_text", { text }),

  bundledToolsDir: () => invoke<string>("bundled_tools_dir"),
  listTools: (extraDir: string | null) => invoke<ToolList>("list_tools", { extraDir }),
  toolHelp: (path: string) => invoke<string>("tool_help", { path }),
  runTool: (path: string, args: string[], cwd: string) =>
    invoke<number>("run_tool", { path, args, cwd }),
  toolStdin: (id: number, text: string) => invoke<void>("tool_stdin", { id, text }),
  stopTool: (id: number) => invoke<void>("stop_tool", { id }),
};
