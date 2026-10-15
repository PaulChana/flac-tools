import { api } from "./api";

const SIZE = 28;

const cache = new Map<string, Promise<string | null>>();
let pending: { path: string; resolve: (v: string | null) => void }[] = [];
let timer: ReturnType<typeof setTimeout> | null = null;

function flush() {
  timer = null;
  const batch = pending;
  pending = [];
  api
    .imageThumbnails(
      batch.map((b) => b.path),
      SIZE,
    )
    .then((urls) => batch.forEach((b, i) => b.resolve(urls[i] ?? null)))
    .catch(() => batch.forEach((b) => b.resolve(null)));
}

export function coverThumb(path: string, modified: number): Promise<string | null> {
  const key = `${path}@${modified}`;
  let p = cache.get(key);
  if (!p) {
    p = new Promise((resolve) => pending.push({ path, resolve }));
    cache.set(key, p);
    timer ??= setTimeout(flush, 30);
  }
  return p;
}
