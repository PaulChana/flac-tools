import { api, type FlacInfo, type TagChange, type ToolInfo } from "./api";
import { DETECTABLE, detectTags } from "./autotag";
import { NUMBER_TAGS, renumber, tagValues } from "./tags";
import { basename, dirname, relative } from "./format";
import { tr } from "./i18n";

export interface BuiltinRun {
  folder: string;
  root: string;
  args: string[];
  out: (text: string) => void;
  err: (text: string) => void;
  stopped: () => boolean;
}

interface Builtin {
  info: ToolInfo;
  help: string;
  run: (r: BuiltinRun) => Promise<number>;
}

const COMMON_USAGE = "[--path=DIR] [--dry-run] [--verbose] [--quiet]";
const COMMON_HELP = `  --path=DIR   Operate under DIR (the folder the tool is run on).
  --dry-run    Print what would change without writing anything.
  --verbose    Also list files that need no change.
  --quiet      Only print warnings and the summary.`;

function option(args: string[], name: string): string | undefined {
  return args.find((a) => a.startsWith(`${name}=`))?.slice(name.length + 1);
}

async function readAll(folder: string): Promise<FlacInfo[]> {
  const { flacs } = await api.dirContents(folder, true);
  const infos: FlacInfo[] = [];
  for (let i = 0; i < flacs.length; i += 200) infos.push(...(await api.readFlacs(flacs.slice(i, i + 200), false)));
  return infos;
}

type Plan = { file: FlacInfo; changes: TagChange[] }[];

async function applyPlan(r: BuiltinRun, files: FlacInfo[], plan: Plan): Promise<number> {
  const dry = r.args.includes("--dry-run");
  const quiet = r.args.includes("--quiet");
  const verbose = r.args.includes("--verbose") && !quiet;
  const planned = new Set(plan.map((p) => p.file.path));
  for (const f of files) {
    if (verbose && !planned.has(f.path)) r.out(`${relative(f.path, r.folder)}  ${tr("nothing to change")}\n`);
  }
  let failed = 0;
  let written = 0;
  for (let i = 0; i < plan.length; i += 8) {
    if (r.stopped()) break;
    await Promise.all(
      plan.slice(i, i + 8).map(async ({ file, changes }) => {
        const what = changes
          .map((c) => `${c.key}: '${tagValues(file, c.key).join("; ")}' -> '${c.value ?? ""}'`)
          .join(", ");
        if (!quiet) r.out(`${relative(file.path, r.folder)}  ${what}\n`);
        if (dry) return;
        try {
          await api.applyTagChanges([file.path], changes);
          written++;
        } catch (e) {
          failed++;
          r.err(`${String(e)}\n`);
        }
      }),
    );
  }
  r.out(
    `\n${dry ? tr("(dry run — no files were changed)") + "\n" : ""}` +
      `${tr("Checked: {n}", { n: files.length })}\n${tr("Changed: {n}", { n: dry ? plan.length : written })}\n`,
  );
  return failed ? 1 : 0;
}

const autoTag: Builtin = {
  info: {
    name: "flac-auto-tag",
    path: "builtin:flac-auto-tag",
    builtin: true,
    description:
      "Fills in tags guessed from each file's name and the folders above it (artist, album, year, disc, track number and title), the same way the tag editor's Auto-detect does. Only empty tags are filled unless --overwrite is passed; --tags limits which tags are written.",
    usage: `flac-auto-tag [--overwrite] [--tags=TAGS] ${COMMON_USAGE}`,
  },
  help: `Usage: flac-auto-tag [--overwrite] [--tags=TAGS] ${COMMON_USAGE}
Fills in tags guessed from file and folder names, like the tag editor's
Auto-detect. Artist and album folders are read relative to the library
folder.

  --overwrite  Also replace tags that already have a different value.
  --tags=TAGS  Only write these (comma-separated) from:
               ${DETECTABLE.join(", ")}.
${COMMON_HELP}
`,
  async run(r) {
    const overwrite = r.args.includes("--overwrite");
    const only = option(r.args, "--tags")
      ?.split(",")
      .map((t) => t.trim().toUpperCase())
      .filter(Boolean);
    const unknown = only?.filter((t) => !(DETECTABLE as readonly string[]).includes(t)) ?? [];
    if (unknown.length) {
      r.err(tr("Can't detect {tags} — choose from {choices}", { tags: unknown.join(", "), choices: DETECTABLE.join(", ") }) + "\n");
      return 1;
    }
    const files = await readAll(r.folder);
    const siblings = new Map<string, string[]>();
    for (const f of files) siblings.set(dirname(f.path), [...(siblings.get(dirname(f.path)) ?? []), basename(f.path)]);
    const plan: Plan = files
      .map((file) => {
        const detected = detectTags(file.path, r.root, siblings.get(dirname(file.path)));
        const changes = DETECTABLE.filter((k) => !only || only.includes(k)).flatMap((key): TagChange[] => {
          const value = detected[key];
          const current = tagValues(file, key).join("; ");
          if (!value || value === current || (current && !overwrite)) return [];
          return [{ key, value }];
        });
        return { file, changes };
      })
      .filter((p) => p.changes.length);
    return applyPlan(r, files, plan);
  },
};

function numbering(mode: "strip" | "pad"): Builtin {
  const name = mode === "strip" ? "flac-unpad-numbers" : "flac-pad-numbers";
  const what =
    mode === "strip"
      ? 'Removes leading zeros from track and disc numbers ("01" → "1", "01/09" → "1/9")'
      : 'Pads track and disc numbers to two digits ("1" → "01", "1/9" → "01/09")';
  return {
    info: {
      name,
      path: `builtin:${name}`,
      builtin: true,
      description: `${what} in TRACKNUMBER, TRACKTOTAL, DISCNUMBER and DISCTOTAL, on every .flac file in the folder and below — the tag editor's Numbers menu as a tool.`,
      usage: `${name} ${COMMON_USAGE}`,
    },
    help: `Usage: ${name} ${COMMON_USAGE}
${what}
in ${NUMBER_TAGS.join(", ")}, recursively.

${COMMON_HELP}
`,
    async run(r) {
      const files = await readAll(r.folder);
      const plan: Plan = files
        .map((file) => ({
          file,
          changes: NUMBER_TAGS.flatMap((key): TagChange[] => {
            const vals = tagValues(file, key);
            if (vals.length !== 1) return [];
            const next = renumber(vals[0], mode);
            return next === vals[0] ? [] : [{ key, value: next }];
          }),
        }))
        .filter((p) => p.changes.length);
      return applyPlan(r, files, plan);
    },
  };
}

const BUILTINS: Builtin[] = [autoTag, numbering("strip"), numbering("pad")];

export const builtinTools = BUILTINS.map((b) => b.info);

export function builtin(name: string): Builtin | undefined {
  return BUILTINS.find((b) => b.info.name === name);
}

export function commandName(t: ToolInfo): string {
  return t.builtin ? t.name : `${t.name}.fish`;
}
