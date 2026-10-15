import { tr } from "./i18n";

export function formatDuration(secs: number): string {
  if (!secs) return "";
  const s = Math.round(secs);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = bytes / 1024;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(v < 10 ? 1 : 0)} ${units[i]}`;
}

export function formatDate(secs: number): string {
  if (!secs) return "";
  return new Date(secs * 1000).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export function formatAudio(sampleRate: number, bits: number, channels: number): string {
  if (!sampleRate) return "";
  const khz = (sampleRate / 1000).toFixed(sampleRate % 1000 ? 1 : 0);
  const ch = channels === 1 ? tr("mono") : channels === 2 ? "" : ` ${channels}ch`;
  return `${bits}/${khz}${ch ? " " + ch.trim() : ""}`;
}

export function basename(path: string): string {
  return path.split("/").filter(Boolean).pop() ?? path;
}

export function dirname(path: string): string {
  const i = path.replace(/\/+$/, "").lastIndexOf("/");
  return i <= 0 ? "/" : path.slice(0, i);
}

export function relative(path: string, root: string): string {
  const r = root.endsWith("/") ? root : root + "/";
  return path.startsWith(r) ? path.slice(r.length) : path;
}

export function reparent(path: string, from: string, to: string): string {
  if (path === from) return to;
  if (path.startsWith(from + "/")) return to + path.slice(from.length);
  return path;
}

export function ancestors(path: string, root: string): string[] {
  const out = [root];
  if (!path.startsWith(root + "/")) return out;
  let cur = root;
  for (const part of path.slice(root.length + 1).split("/")) {
    cur = `${cur}/${part}`;
    out.push(cur);
  }
  return out;
}

export function commonAncestor(paths: string[]): string {
  if (!paths.length) return "/";
  let parts = paths[0].split("/");
  for (const p of paths.slice(1)) {
    const q = p.split("/");
    let i = 0;
    while (i < parts.length && i < q.length && parts[i] === q[i]) i++;
    parts = parts.slice(0, i);
  }
  return parts.join("/") || "/";
}
