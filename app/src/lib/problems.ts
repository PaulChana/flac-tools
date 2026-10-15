import type { FileSummary, FlacInfo } from "./api";
import { dirname } from "./format";
import { msg, tr } from "./i18n";
import { hasTag, tagValues, yearMismatch } from "./tags";

export type Severity = "error" | "warning" | "info";

export type ProblemKind =
  | "unreadable"
  | "decode"
  | "id3"
  | "missing-tags"
  | "year-mismatch"
  | "no-art"
  | "upper-ext"
  | "missing-tracks"
  | "duplicate-tracks"
  | "no-cover"
  | "cover-not-square"
  | "playlist";

export interface KindInfo {
  title: string;
  severity: Severity;
  fix?: { tool: string; args: string[]; label: string };
}

export const KINDS: Record<ProblemKind, KindInfo> = {
  unreadable: { title: msg("Can't read the file's metadata"), severity: "error" },
  decode: { title: msg("Audio doesn't decode cleanly"), severity: "error" },
  id3: {
    title: msg("Stray ID3 tags"),
    severity: "warning",
    fix: { tool: "flac-remove-id3", args: [], label: msg("Remove ID3 tags") },
  },
  "missing-tracks": { title: msg("Missing tracks"), severity: "warning" },
  "duplicate-tracks": { title: msg("Duplicate track numbers"), severity: "warning" },
  playlist: {
    title: msg("Playlist entries for missing files"),
    severity: "warning",
    fix: { tool: "flac-make-m3u", args: [], label: msg("Rebuild playlists") },
  },
  "missing-tags": { title: msg("Missing basic tags"), severity: "warning" },
  "year-mismatch": {
    title: msg("YEAR doesn't match DATE"),
    severity: "info",
    fix: { tool: "flac-ensure-year-and-date-match", args: [], label: msg("Make YEAR match DATE") },
  },
  "no-art": {
    title: msg("No embedded cover art"),
    severity: "info",
    fix: { tool: "flac-embed-cover-art", args: [], label: msg("Embed cover.jpg") },
  },
  "upper-ext": {
    title: msg("Uppercase file extension"),
    severity: "info",
    fix: { tool: "flac-ensure-lowercase-extensions", args: ["--flac-only"], label: msg("Lowercase extensions") },
  },
  "no-cover": {
    title: msg("No cover.jpg in the folder"),
    severity: "info",
    fix: { tool: "flac-download-album-art", args: [], label: msg("Download covers") },
  },
  "cover-not-square": { title: msg("cover.jpg isn't square"), severity: "info" },
};

export interface Problem {
  kind: ProblemKind;
  path: string;
  dir: string;
  message: string;
}

const CORE_TAGS = ["TITLE", "ARTIST", "ALBUM", "TRACKNUMBER"];

export function fileProblems(f: FlacInfo): Problem[] {
  const dir = dirname(f.path);
  const out: Problem[] = [];
  const add = (kind: ProblemKind, message: string) => out.push({ kind, path: f.path, dir, message });
  if (f.error) {
    add("unreadable", f.error);
    return out;
  }
  if (f.id3v2 || f.id3v1) {
    add(
      "id3",
      f.id3v2 && f.id3v1
        ? tr("Has ID3v2 (start) and ID3v1 (end)")
        : f.id3v2
          ? tr("Has ID3v2 (start)")
          : tr("Has ID3v1 (end)"),
    );
  }
  const missing = CORE_TAGS.filter((k) => !hasTag(f, k));
  if (missing.length) add("missing-tags", tr("No {tags}", { tags: missing.join(", ") }));
  if (yearMismatch(f)) {
    add(
      "year-mismatch",
      tr("YEAR {year} vs DATE {date}", { year: tagValues(f, "YEAR")[0] ?? tr("(none)"), date: tagValues(f, "DATE")[0] ?? "" }),
    );
  }
  if (!f.pictures) add("no-art", tr("No picture embedded"));
  const ext = f.name.match(/\.[^.]+$/)?.[0] ?? "";
  if (ext !== ext.toLowerCase()) add("upper-ext", tr("Extension is “{ext}”", { ext }));
  return out;
}

const trackNo = (f: FlacInfo) => parseInt(tagValues(f, "TRACKNUMBER")[0] ?? "", 10);

export function trackProblems(files: FlacInfo[]): Problem[] {
  const groups = new Map<string, FlacInfo[]>();
  for (const f of files) {
    const disc = parseInt(tagValues(f, "DISCNUMBER")[0] ?? "1", 10) || 1;
    const key = `${dirname(f.path)}\u0000${disc}`;
    groups.set(key, [...(groups.get(key) ?? []), f]);
  }
  const out: Problem[] = [];
  for (const [key, group] of groups) {
    const [dir, disc] = key.split("\u0000");
    const nums = group.map(trackNo).filter((n) => n > 0);
    if (nums.length < 2) continue;
    const totals = group
      .map((f) => parseInt(tagValues(f, "TRACKTOTAL")[0] ?? tagValues(f, "TOTALTRACKS")[0] ?? "", 10))
      .filter((n) => n > 0 && n < 1000);
    const max = Math.max(...nums, ...totals);
    const have = new Set(nums);
    const gaps = Array.from({ length: max }, (_, i) => i + 1).filter((n) => !have.has(n));
    if (gaps.length && gaps.length < max) {
      out.push({
        kind: "missing-tracks",
        path: dir,
        dir,
        message:
          disc !== "1"
            ? tr("{count, plural, one {Track {tracks} of {max} not here (disc {disc})} other {Tracks {tracks} of {max} not here (disc {disc})}}", { count: gaps.length, tracks: gaps.join(", "), max, disc })
            : tr("{count, plural, one {Track {tracks} of {max} not here} other {Tracks {tracks} of {max} not here}}", { count: gaps.length, tracks: gaps.join(", "), max }),
      });
    }
    const dupes = [...have].filter((n) => nums.filter((x) => x === n).length > 1);
    if (dupes.length) {
      out.push({
        kind: "duplicate-tracks",
        path: dir,
        dir,
        message:
          disc !== "1"
            ? tr("{count, plural, one {Track {tracks} appears more than once (disc {disc})} other {Tracks {tracks} appear more than once (disc {disc})}}", { count: dupes.length, tracks: dupes.join(", "), disc })
            : tr("{count, plural, one {Track {tracks} appears more than once} other {Tracks {tracks} appear more than once}}", { count: dupes.length, tracks: dupes.join(", ") }),
      });
    }
  }
  return out;
}

export function coverProblems(files: FlacInfo[], others: FileSummary[]): Problem[] {
  const covers = new Map(
    others.filter((o) => o.name.toLowerCase() === "cover.jpg").map((o) => [dirname(o.path), o]),
  );
  const out: Problem[] = [];
  for (const dir of new Set(files.map((f) => dirname(f.path)))) {
    const cover = covers.get(dir) ?? (/^(cd|disc|disk)\s*\d+/i.test(dir.split("/").pop()!) ? covers.get(dirname(dir)) : undefined);
    if (!cover) out.push({ kind: "no-cover", path: dir, dir, message: tr("No cover.jpg") });
    else if (cover.width && cover.height && cover.width !== cover.height) {
      out.push({
        kind: "cover-not-square",
        path: cover.path,
        dir,
        message: `${cover.width} × ${cover.height}`,
      });
    }
  }
  return out;
}

export const SEVERITY_ORDER: Severity[] = ["error", "warning", "info"];

export function worstSeverity(problems: Problem[]): Severity | null {
  for (const s of SEVERITY_ORDER) if (problems.some((p) => KINDS[p.kind].severity === s)) return s;
  return null;
}
