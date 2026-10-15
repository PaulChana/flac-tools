// Writes src/lib/generated/licenses.ts: the open source software shipped in
// the app, for the About page — the Rust crates the app depends on directly,
// the npm packages that end up in the bundle, and the fonts.
// Usage: node scripts/generate-licenses.mjs (run by `npm run build`). Fails if
// a licence is missing, so the list can't quietly go stale.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = join(dirname(fileURLToPath(import.meta.url)), "..");
const problems = [];

const SHIPPED_DEV = ["svelte"];

const FONTS = [
  { name: "Outfit", version: "variable", url: "https://github.com/Outfitio/Outfit-Fonts", license: "OFL-1.1" },
  { name: "Momo Trust Display", version: "1.0", url: "https://fonts.google.com/specimen/Momo+Trust+Display", license: "OFL-1.1" },
];

function rust() {
  const meta = JSON.parse(
    execFileSync("cargo", ["metadata", "--format-version", "1"], {
      cwd: join(app, "src-tauri"),
      maxBuffer: 64 * 1024 * 1024,
    }).toString(),
  );
  const root = meta.packages.find((p) => p.id === meta.resolve.root);
  const byName = new Map(meta.packages.map((p) => [p.name, p]));
  return root.dependencies
    .filter((d) => d.kind === null || d.kind === "normal")
    .map((d) => {
      const p = byName.get(d.name);
      if (!p?.license) problems.push(`Rust crate ${d.name} has no licence`);
      return {
        name: d.name,
        version: p?.version ?? "",
        url: p?.repository ?? `https://crates.io/crates/${d.name}`,
        license: (p?.license ?? "").replace(/ OR /g, " / "),
        category: "Rust",
      };
    });
}

function repoUrl(repository) {
  const raw = typeof repository === "string" ? repository : repository?.url;
  if (!raw) return null;
  return raw
    .replace(/^git\+/, "")
    .replace(/\.git$/, "")
    .replace(/^git:\/\//, "https://")
    .replace(/^git@github\.com:/, "https://github.com/")
    .replace(/^github:/, "https://github.com/");
}

function npm() {
  const pkg = JSON.parse(readFileSync(join(app, "package.json"), "utf8"));
  const names = [...Object.keys(pkg.dependencies ?? {}), ...SHIPPED_DEV];
  return names.map((name) => {
    const p = JSON.parse(readFileSync(join(app, "node_modules", name, "package.json"), "utf8"));
    if (!p.license) problems.push(`npm package ${name} has no licence`);
    return {
      name,
      version: p.version,
      url: repoUrl(p.repository) ?? p.homepage ?? `https://www.npmjs.com/package/${name}`,
      license: (p.license ?? "").replace(/ OR /g, " / "),
      category: "Frontend",
    };
  });
}

const entries = [
  ...rust(),
  ...npm(),
  ...FONTS.map((f) => ({ ...f, category: "Fonts" })),
];
if (problems.length) {
  console.error("Licence list is incomplete:\n" + problems.map((p) => `  - ${p}`).join("\n"));
  process.exit(1);
}
const ORDER = ["Rust", "Frontend", "Fonts"];
entries.sort((a, b) => ORDER.indexOf(a.category) - ORDER.indexOf(b.category) || a.name.localeCompare(b.name, undefined, { sensitivity: "base" }));

const out = join(app, "src", "lib", "generated", "licenses.ts");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(
  out,
  `export interface LicenseEntry {
  name: string;
  version: string;
  url: string;
  license: string;
  category: "Rust" | "Frontend" | "Fonts";
}

export const licenses: LicenseEntry[] = ${JSON.stringify(entries, null, 2)};
`,
);
console.log(`Wrote ${entries.length} licence entries to ${out}`);
