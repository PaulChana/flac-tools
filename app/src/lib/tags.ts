import type { FlacInfo } from "./api";

export const PREFERRED_TAGS = [
  "TRACKNUMBER",
  "TRACKTOTAL",
  "TOTALTRACKS",
  "DISCNUMBER",
  "DISCTOTAL",
  "TOTALDISCS",
  "TITLE",
  "ARTIST",
  "ALBUMARTIST",
  "ALBUM",
  "DATE",
  "YEAR",
  "GENRE",
  "COMPOSER",
];

export const NUMBERING_TAGS = new Set(PREFERRED_TAGS.slice(0, 6));

export const STANDARD_TAGS = [
  "TITLE",
  "ARTIST",
  "ALBUMARTIST",
  "ALBUM",
  "TRACKNUMBER",
  "TRACKTOTAL",
  "DISCNUMBER",
  "DISCTOTAL",
  "DATE",
  "YEAR",
  "GENRE",
  "COMPOSER",
];
const ALIASES: Record<string, string[]> = {
  TRACKTOTAL: ["TOTALTRACKS"],
  DISCTOTAL: ["TOTALDISCS"],
};

export function hasTag(f: FlacInfo, key: string): boolean {
  const keys = [key, ...(ALIASES[key] ?? [])];
  return f.tags.some(([k, v]) => keys.includes(k) && v !== "");
}

export function orderTagKeys(keys: Iterable<string>): string[] {
  const set = new Set(keys);
  const head = PREFERRED_TAGS.filter((k) => set.has(k));
  const rest = [...set].filter((k) => !PREFERRED_TAGS.includes(k)).sort();
  return [...head, ...rest];
}

export function tagValues(f: FlacInfo, key: string): string[] {
  return f.tags.filter(([k]) => k === key).map(([, v]) => v);
}

export function tagValue(f: FlacInfo, key: string): string {
  return tagValues(f, key).join("; ");
}

export function yearMismatch(f: FlacInfo): boolean {
  const date = tagValues(f, "DATE")[0]?.slice(0, 4) ?? "";
  const year = tagValues(f, "YEAR")[0] ?? "";
  return date !== "" && year !== date;
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
export const compareText = (a: string, b: string) => collator.compare(a, b);

export const NUMBER_TAGS = ["TRACKNUMBER", "DISCNUMBER", "TRACKTOTAL", "DISCTOTAL"];

export function renumber(value: string, mode: "strip" | "pad"): string {
  const m = value.trim().match(/^(\d+)(?:\s*\/\s*(\d+))?$/);
  if (!m) return value;
  const f = (n: string) => (mode === "strip" ? String(parseInt(n, 10)) : n.padStart(2, "0"));
  return m[2] !== undefined ? `${f(m[1])}/${f(m[2])}` : f(m[1]);
}
