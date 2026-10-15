export const DETECTABLE = [
  "TRACKNUMBER",
  "TITLE",
  "ARTIST",
  "ALBUMARTIST",
  "ALBUM",
  "DISCNUMBER",
  "DATE",
  "YEAR",
  "TRACKTOTAL",
] as const;

export type DetectedKey = (typeof DETECTABLE)[number];
export type Detected = Partial<Record<DetectedKey, string>>;

const YEAR = /\b(19[3-9]\d|20[0-4]\d)\b/;
const DISC_DIR = /(?:^|[\s_\-\]])(?:cd|disc|disk)\s*[-_.]?\s*(\d{1,2})(?!\d)/i;
const COLLECTION = /\s+(studio\s+albums?|albums?|discography|collection|complete\s+works)$/i;
const NOISE =
  /\b(flac|lossless|mp3|aac|alac|wav|vinyl|web|eac|cue|log|\d+\s*-?\s*bits?|\d+(\.\d+)?\s*khz|24bit|16-44|hi-?res|remaster(ed)?|tracks)\b/i;

const same = (a: string, b: string) => a.localeCompare(b, undefined, { sensitivity: "base" }) === 0;

function tidy(s: string): string {
  return s
    .replace(/_/g, " ")
    .replace(/\s{2,}/g, " ")
    .replace(/^[\s\-–]+|[\s\-–]+$/g, "")
    .trim();
}

function stripNoise(s: string): string {
  let out = s
    .replace(/([\]})])\s*by\s+\S+\s*$/i, "$1")
    .replace(/\[[^\]]*\]|\{[^}]*\}/g, " ")
    .replace(/\(([^)]*)\)/g, (m, inner: string) => (YEAR.test(inner) || NOISE.test(inner) ? " " : m));
  let prev;
  do {
    prev = out;
    out = out.replace(new RegExp(`\\s+${NOISE.source}\\s*$`, "i"), "");
  } while (out !== prev);
  return tidy(out);
}

interface Folder {
  artist?: string;
  album?: string;
  year?: string;
}

function parseAlbumFolder(name: string, artistHint?: string): Folder {
  const year = name.match(YEAR)?.[1];
  let s = stripNoise(name);
  s = tidy(s.replace(new RegExp(`(^|\\s-\\s)${YEAR.source}(\\s-\\s|$)`), (_, a, _y, b) => (a && b ? " - " : "")));
  const dash = s.indexOf(" - ");
  if (dash > 0) {
    const left = tidy(s.slice(0, dash));
    const right = tidy(s.slice(dash + 3));
    if (right && (!artistHint || same(left, artistHint))) return { artist: left, album: right, year };
  }
  return { album: s || undefined, year };
}

const VINYL = /^([A-H]\d{1,2})\s*[-.]\s*(.+)$/;

interface FileName {
  side?: string;
  disc?: string;
  track?: string;
  artist?: string;
  title?: string;
}

function parseFileName(stem: string, knownArtist?: string, knownAlbum?: string): FileName {
  let s = tidy(stem);
  const out: FileName = {};
  let m: RegExpMatchArray | null;
  if ((m = s.match(/^(.+?)\s+-\s+(\d{1,3})\s+-\s+(.+)$/))) {
    out.artist = tidy(m[1]);
    out.track = m[2];
    s = m[3];
  } else if ((m = s.match(/^(\d)[-.](\d{2})(?:\s*[-.]\s*|\s+)(.+)$/))) {
    out.disc = m[1];
    out.track = m[2];
    s = m[3];
  } else if ((m = s.match(/^(\d{1,3})(?:\s*[-.)_]\s*|\s+)(.+)$/))) {
    out.track = m[1];
    s = m[2];
  }
  s = tidy(s);
  if (!out.track && (m = s.match(/^\((\d{1,3})\)\s*(.+)$/))) {
    out.track = m[1];
    s = m[2];
  }
  if ((m = s.match(/^\[([^\]]+)\]\s*(.+)$/))) {
    out.artist ??= tidy(m[1]);
    s = m[2];
  }
  if (!out.track && (m = s.match(VINYL))) {
    out.side = m[1];
    s = m[2];
  }
  if ((m = s.match(/^\(([^)]+)\)\s*(.+)$/))) {
    out.artist ??= tidy(m[1]);
    s = m[2];
  }
  const dash = s.indexOf(" - ");
  if (dash > 0 && !out.artist) {
    const left = tidy(s.slice(0, dash));
    const right = tidy(s.slice(dash + 3));
    if (knownAlbum && same(left, knownAlbum)) s = right;
    else {
      out.artist = left;
      s = right;
    }
  }
  if (out.artist && knownArtist && same(out.artist, knownArtist)) out.artist = knownArtist;
  s = s.replace(new RegExp(`^${YEAR.source}\\s+-\\s+`), "");
  out.title = tidy(s) || undefined;
  return out;
}

const num = (s?: string) => (s ? String(parseInt(s, 10)) : undefined);

export function detectTags(path: string, root: string, siblings: string[] = []): Detected {
  const trackTotal = siblings.length || undefined;
  const rel = path.startsWith(root + "/") ? path.slice(root.length + 1) : path.split("/").slice(-3).join("/");
  const parts = rel.split("/");
  const fileName = parts.pop()!;
  const stem = fileName.replace(/\.[^.]+$/, "");

  let disc: string | undefined;
  const last = parts[parts.length - 1];
  const dm = last?.match(DISC_DIR);
  if (dm) {
    disc = dm[1];
    parts.pop();
  }

  const albumDir = parts.pop();
  const artistDir = [...parts].reverse().find((p) => !new RegExp(`^${YEAR.source}\\s*-`).test(p));
  const artistFromDir = artistDir
    ? stripNoise(artistDir).split(" - ")[0].replace(COLLECTION, "").trim() || undefined
    : undefined;
  const folder = albumDir ? parseAlbumFolder(albumDir, artistFromDir) : {};
  const albumArtist = folder.artist ?? artistFromDir;

  const file = parseFileName(stem, albumArtist, folder.album);
  if (file.side) {
    const sides = siblings.filter((n) => VINYL.test(n)).sort();
    const i = sides.indexOf(fileName);
    if (i >= 0) file.track = String(i + 1);
  }

  const d: Detected = {
    TRACKNUMBER: num(file.track),
    TITLE: file.title,
    ARTIST: file.artist ?? albumArtist,
    ALBUMARTIST: albumArtist,
    ALBUM: folder.album,
    DISCNUMBER: num(file.disc ?? disc),
    DATE: folder.year,
    YEAR: folder.year,
    TRACKTOTAL: trackTotal && file.track ? String(trackTotal) : undefined,
  };
  for (const k of DETECTABLE) if (!d[k]) delete d[k];
  return d;
}
