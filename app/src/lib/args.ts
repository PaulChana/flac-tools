export type UsageItem =
  | { kind: "flag"; name: string }
  | { kind: "option"; name: string; meta: string }
  | { kind: "positional"; name: string; optional: boolean; variadic: boolean };

export const COMMON_FLAGS = ["--dry-run", "--verbose", "--quiet"];

export function parseUsage(usage: string): UsageItem[] {
  const items: UsageItem[] = [];
  const body = usage.replace(/^\S+\.fish\s*/, "");
  for (const m of body.matchAll(/\[([^\]]+)\]|(\S+)/g)) {
    const optional = m[1] !== undefined;
    const tok = (m[1] ?? m[2]).trim();
    const opt = tok.match(/^(--[\w-]+)=(\S+)$/);
    if (opt) {
      items.push({ kind: "option", name: opt[1], meta: opt[2] });
    } else if (tok.startsWith("--")) {
      items.push({ kind: "flag", name: tok });
    } else if (/^[A-Z][A-Z_]*( \.\.\.)?$/.test(tok)) {
      items.push({
        kind: "positional",
        name: tok.replace(" ...", ""),
        optional,
        variadic: tok.endsWith("..."),
      });
    }
  }
  return items;
}

export function shellSplit(input: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quote: string | null = null;
  let has = false;
  for (let i = 0; i < input.length; i++) {
    const c = input[i];
    if (quote) {
      if (c === quote) quote = null;
      else if (c === "\\" && quote === '"' && i + 1 < input.length) cur += input[++i];
      else cur += c;
    } else if (c === "'" || c === '"') {
      quote = c;
      has = true;
    } else if (c === "\\" && i + 1 < input.length) {
      cur += input[++i];
      has = true;
    } else if (/\s/.test(c)) {
      if (has) out.push(cur);
      cur = "";
      has = false;
    } else {
      cur += c;
      has = true;
    }
  }
  if (has) out.push(cur);
  return out;
}

export function prettyToolName(name: string): string {
  const s = name
    .replace(/^flac-/, "")
    .replace(/-/g, " ")
    .replace(/\b(id3|m3u|cue|flac|mp3)\b/gi, (w) => w.toUpperCase());
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function unwrap(description: string): string {
  return description.replace(/([^\n])\n(?![\n\s\-*•])/g, "$1 ");
}

export function summary(description: string): string {
  const flat = description.replace(/\s+/g, " ").trim();
  const m = flat.match(/^.*?[.!?](\s|$)/);
  return (m ? m[0] : flat).trim();
}
