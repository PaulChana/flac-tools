// Collects every translatable string from src/ — the literals passed to
// $t("…"), tr("…") and msg("…") — and writes src/lib/locales/en.json
// (English keys map to themselves). Then checks the other languages:
// lists keys they're missing, keys nothing uses any more, and translations
// that don't parse or whose {placeholders} differ from the English.
// `node scripts/i18n-extract.mjs` (add --check to fail instead of write).
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { parse } from "@formatjs/icu-messageformat-parser";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = join(app, "src");
const locales = join(src, "lib", "locales");
const check = process.argv.includes("--check");

function files(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return name === "generated" ? [] : files(p);
    return /\.(svelte|ts)$/.test(name) ? [p] : [];
  });
}

const CALL = /(?:\$t|\btr|\bmsg)\(\s*"((?:[^"\\]|\\.)*)"/g;
const keys = new Set();
for (const file of files(src)) {
  for (const m of readFileSync(file, "utf8").matchAll(CALL)) keys.add(JSON.parse(`"${m[1]}"`));
}
const sorted = [...keys].sort((a, b) => a.localeCompare(b));

const en = { meta: { language: "English" } };
for (const k of sorted) en[k] = k;
const enText = JSON.stringify(en, null, 2) + "\n";
let failed = false;
if (check) {
  if (readFileSync(join(locales, "en.json"), "utf8") !== enText) {
    console.error("en.json is out of date — run node scripts/i18n-extract.mjs");
    failed = true;
  }
} else {
  writeFileSync(join(locales, "en.json"), enText);
  console.log(`en.json: ${sorted.length} strings`);
}

function argumentsOf(message) {
  const names = new Set();
  const walk = (nodes) => {
    for (const n of nodes) {
      if (n.value !== undefined && typeof n.value === "string" && n.type !== 0) names.add(n.value);
      for (const option of Object.values(n.options ?? {})) walk(option.value);
    }
  };
  try {
    walk(parse(message, { ignoreTag: true }));
  } catch {
    return null;
  }
  return [...names].sort().join(",");
}

for (const name of readdirSync(locales).filter((n) => n.endsWith(".json") && n !== "en.json")) {
  const data = JSON.parse(readFileSync(join(locales, name), "utf8"));
  const missing = sorted.filter((k) => !(k in data));
  const unused = Object.keys(data).filter((k) => k !== "meta" && !keys.has(k));
  const broken = sorted.filter((k) => k in data && argumentsOf(data[k]) !== argumentsOf(k));
  if (missing.length || unused.length || broken.length) {
    console.log(`${name}: ${missing.length} missing, ${unused.length} unused, ${broken.length} broken`);
    for (const k of broken) console.log(`  broken: ${JSON.stringify(k)} → ${JSON.stringify(data[k])}`);
    if (check && (missing.length || broken.length)) failed = true;
  }
}
process.exit(failed ? 1 : 0);
