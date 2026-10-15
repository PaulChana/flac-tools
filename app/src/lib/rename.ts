import { msg, tr } from "./i18n";

export interface RenameOptions {
  remove: string;
  replace: string;
  with: string;
  regex: boolean;
  stripStart: number;
  stripEnd: number;
}

export const emptyRenameOptions = (): RenameOptions => ({
  remove: "",
  replace: "",
  with: "",
  regex: false,
  stripStart: 0,
  stripEnd: 0,
});

export function splitExt(name: string): [string, string] {
  const m = name.match(/^(.+?)(\.[^.]+)?$/);
  return [m?.[1] ?? name, m?.[2] ?? ""];
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function compile(o: RenameOptions): { remove: RegExp | null; replace: RegExp | null } {
  const make = (src: string, label: string) => {
    if (!src) return null;
    try {
      return new RegExp(o.regex ? src : escapeRegex(src), "g");
    } catch (e) {
      const error = (e as Error).message.replace(/^Invalid regular expression: \/.*\/\w*: /, "");
      throw new Error(tr(label, { error }));
    }
  };
  return { remove: make(o.remove, msg("Remove: {error}")), replace: make(o.replace, msg("Replace: {error}")) };
}

export type TagLookup = (key: string) => string | undefined;

export function fillPlaceholders(template: string, tags: TagLookup | undefined, missing: string[]): string {
  return template.replace(/\{([A-Za-z_]+)(?::(\d))?\}/g, (whole, key: string, pad?: string) => {
    let v = tags?.(key.toUpperCase());
    if (v === undefined || v === "") {
      missing.push(key.toUpperCase());
      return whole;
    }
    const num = v.match(/^\s*(\d+)\s*(?:\/\s*\d+)?\s*$/);
    if (num) v = num[1];
    if (pad && num) v = String(parseInt(v, 10)).padStart(Number(pad), "0");
    return v.replace(/\//g, "-");
  });
}

export function applyRename(
  name: string,
  o: RenameOptions,
  re: ReturnType<typeof compile>,
  tags?: TagLookup,
  missing: string[] = [],
): string {
  let [stem, ext] = splitExt(name);
  if (o.stripStart > 0) stem = stem.slice(o.stripStart);
  if (o.stripEnd > 0) stem = stem.slice(0, Math.max(0, stem.length - o.stripEnd));
  if (re.remove) stem = stem.replace(re.remove, "");
  if (re.replace) {
    const withText = fillPlaceholders(o.with, tags, missing);
    stem = o.regex ? stem.replace(re.replace, withText) : stem.replace(re.replace, () => withText);
  }
  return stem + ext;
}

export type PreviewStatus = "unchanged" | "ok" | "empty" | "invalid" | "duplicate" | "exists" | "notag";

export interface PreviewRow {
  path: string;
  dir: string;
  oldName: string;
  newName: string;
  status: PreviewStatus;
  missingTags: string[];
}

export function preview(
  files: { path: string; name: string; tags?: [string, string][] }[],
  o: RenameOptions,
  existing: Iterable<string>,
): PreviewRow[] {
  const re = compile(o);
  const fold = (s: string) => s.toLowerCase();
  const rows = files.map((f): PreviewRow => {
    const dir = f.path.slice(0, f.path.length - f.name.length - 1);
    const lookup: TagLookup = (k) => f.tags?.find(([key]) => key === k)?.[1];
    const missingTags: string[] = [];
    const newName = applyRename(f.name, o, re, lookup, missingTags);
    const [stem] = splitExt(newName);
    let status: PreviewStatus = newName === f.name ? "unchanged" : "ok";
    if (missingTags.length) status = "notag";
    else if (status === "ok" && (!stem || newName.startsWith("."))) status = "empty";
    else if (status === "ok" && newName.includes("/")) status = "invalid";
    return { path: f.path, dir, oldName: f.name, newName, status, missingTags };
  });
  const sources = new Set(rows.filter((r) => r.status === "ok").map((r) => fold(r.path)));
  const taken = new Map<string, number>();
  for (const r of rows) {
    const t = fold(`${r.dir}/${r.newName}`);
    taken.set(t, (taken.get(t) ?? 0) + 1);
  }
  const onDisk = new Set([...existing].map(fold));
  for (const r of rows) {
    if (r.status !== "ok") continue;
    const t = fold(`${r.dir}/${r.newName}`);
    if ((taken.get(t) ?? 0) > 1) r.status = "duplicate";
    else if (onDisk.has(t) && !sources.has(t)) r.status = "exists";
  }
  return rows;
}
