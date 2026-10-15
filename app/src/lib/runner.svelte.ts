import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { api, type ToolInfo } from "./api";
import { app } from "./state.svelte";
import { parseUsage, prettyToolName } from "./args";
import { basename, relative } from "./format";
import { builtin, builtinTools, commandName } from "./builtins";
import { layout } from "./layout.svelte";
import { tr } from "./i18n";

export interface Step {
  tool: string;
  args: string[];
}

export interface Chain {
  id: string;
  name: string;
  steps: Step[];
}

export type Chunk = { stream: "stdout" | "stderr" | "info"; text: string };

export interface RunStatus {
  title: string;
  state: "running" | "ok" | "warn" | "error" | "stopped";
}

const RENAMED: Record<string, string> = {
  "flac-check-for-square-cover": "flac-test-for-square-cover",
  "flac-ensure-square-cover": "flac-test-for-square-cover",
  "flac-clean-non-cover-images": "flac-remove-non-cover-images",
  "flac-from-cue": "flac-make-tracks-from-cue",
  "flac-get-images": "flac-download-album-art",
  "flac-remove-fluff": "flac-remove-extraneous-files",
  "flac-rename-folder-to-cover": "flac-ensure-cover",
  "flac-rename-numbered-tracks": "flac-renumber-filename",
  "flac-renumber-tracks": "flac-renumber-filename",
  "flac-strip-id3": "flac-remove-id3",
  "flac-lowercase-extensions": "flac-ensure-lowercase-extensions",
  "flac-sync-year-from-date": "flac-ensure-year-and-date-match",
};

export type Selection = { kind: "tool"; name: string } | { kind: "chain"; id: string } | null;

export function quoteArg(a: string): string {
  return /[\s'"$\\]/.test(a) ? `'${a.replace(/'/g, "'\\''")}'` : a;
}

function exitLine(code: number | null): string {
  return (code === 0 ? tr("✓ Finished") : code === null ? tr("■ Stopped") : tr("✗ Exited with code {code}", { code })) + "\n";
}

class Runner {
  tools = $state<ToolInfo[]>([]);
  toolsError = $state<string | null>(null);
  chains = $state<Chain[]>([]);
  selection = $state<Selection>(null);

  output = $state<Chunk[]>([]);
  outputVersion = $state(0);
  runId = $state<number | null>(null);
  busy = $state(false);
  status = $state<RunStatus | null>(null);
  private sawStderr = false;

  private started = false;
  private stopRequested = false;
  private early = new Map<number, Chunk[]>();
  private exits = new Map<number, (code: number | null) => void>();
  private earlyExits = new Map<number, number | null>();

  async init() {
    if (this.started) return;
    this.started = true;
    listen<{ id: number; stream: "stdout" | "stderr"; text: string }>("tool-output", (e) => {
      const chunk: Chunk = { stream: e.payload.stream, text: e.payload.text };
      if (e.payload.id === this.runId) this.append(chunk);
      else this.early.set(e.payload.id, [...(this.early.get(e.payload.id) ?? []), chunk]);
    });
    listen<{ id: number; code: number | null }>("tool-exit", (e) => {
      const waiter = this.exits.get(e.payload.id);
      if (waiter) {
        waiter(e.payload.code);
        this.exits.delete(e.payload.id);
      } else {
        this.earlyExits.set(e.payload.id, e.payload.code);
      }
    });
    await Promise.all([this.loadTools(), this.loadChains()]);
  }

  async loadTools() {
    this.toolsError = null;
    try {
      const { tools, extraError } = await api.listTools(app.extraToolsDir || null);
      this.tools = [...tools, ...builtinTools].sort((a, b) => a.name.localeCompare(b.name));
      if (extraError) this.toolsError = tr("Extra scripts folder: {error}", { error: extraError });
    } catch (e) {
      this.tools = [...builtinTools];
      this.toolsError = String(e);
    }
  }

  tool(name: string): ToolInfo | undefined {
    return this.tools.find((t) => t.name === name);
  }

  requiredInputs(name: string): string[] {
    const t = this.tool(name);
    if (!t) return [];
    return parseUsage(t.usage).flatMap((u) => (u.kind === "positional" && !u.optional ? [u.name] : []));
  }

  async loadChains() {
    try {
      const parsed = JSON.parse(await invoke<string>("load_chains"));
      this.chains = Array.isArray(parsed) ? parsed : [];
      let renamed = false;
      for (const step of this.chains.flatMap((c) => c.steps)) {
        if (RENAMED[step.tool]) {
          step.tool = RENAMED[step.tool];
          renamed = true;
        }
      }
      if (renamed) this.persist();
    } catch (e) {
      app.showError(e);
    }
  }

  private async persist() {
    try {
      await invoke("save_chains", { json: JSON.stringify(this.chains, null, 2) });
    } catch (e) {
      app.showError(e);
    }
  }

  chain(id: string): Chain | undefined {
    return this.chains.find((c) => c.id === id);
  }

  changed() {
    this.persist();
  }

  newChain(steps: Step[] = []): Chain {
    let n = this.chains.length + 1;
    while (this.chains.some((c) => c.name === tr("Chain {n}", { n }))) n++;
    const chain: Chain = { id: crypto.randomUUID(), name: tr("Chain {n}", { n }), steps };
    this.chains.push(chain);
    this.persist();
    return this.chains[this.chains.length - 1];
  }

  addStep(chainId: string, step: Step) {
    const c = this.chain(chainId);
    if (!c) return;
    c.steps.push(step);
    this.persist();
  }

  duplicateChain(id: string): Chain | undefined {
    const c = this.chain(id);
    if (!c) return;
    const copy: Chain = {
      id: crypto.randomUUID(),
      name: tr("{name} copy", { name: c.name }),
      steps: c.steps.map((s) => ({ tool: s.tool, args: [...s.args] })),
    };
    this.chains.splice(this.chains.indexOf(c) + 1, 0, copy);
    this.persist();
    return this.chain(copy.id);
  }

  async confirmDeleteChain(id: string) {
    const c = this.chain(id);
    if (c && (await ask(tr("Delete the chain “{name}”?", { name: c.name }), {
        title: tr("Delete chain"),
        kind: "warning",
        okLabel: tr("Delete"),
      }))) {
      this.deleteChain(id);
    }
  }

  deleteChain(id: string) {
    this.chains = this.chains.filter((c) => c.id !== id);
    if (this.selection?.kind === "chain" && this.selection.id === id) this.selection = null;
    this.persist();
  }

  append(chunk: Chunk) {
    if (chunk.stream === "stderr") this.sawStderr = true;
    const last = this.output[this.output.length - 1];
    if (last && last.stream === chunk.stream) last.text += chunk.text;
    else this.output.push(chunk);
    this.outputVersion++;
  }

  clear() {
    this.output = [];
    this.outputVersion++;
  }

  async runSteps(steps: Step[], folders: string[], title?: string): Promise<boolean> {
    if (this.busy) {
      app.showError(tr("A tool is already running — wait for it or press Stop."));
      return false;
    }
    if (!steps.length || !folders.length) return false;
    this.busy = true;
    this.stopRequested = false;
    this.sawStderr = false;
    this.clear();
    const label = title ?? steps.map((s) => prettyToolName(s.tool)).join(" → ");
    this.status = { title: label, state: "running" };
    layout.toggle("Bottom", true);
    if (title) this.append({ stream: "info", text: tr("▶ {title}", { title }) + "\n" });
    let ok = true;
    try {
      outer: for (const folder of folders) {
        if (folders.length > 1) {
          const label = folder === app.root ? basename(folder) : relative(folder, app.root);
          this.append({ stream: "info", text: `\n━━ ${label} ━━\n` });
        }
        for (const [i, step] of steps.entries()) {
          if (steps.length > 1) {
            this.append({ stream: "info", text: `\n[${i + 1}/${steps.length}] ${prettyToolName(step.tool)}\n` });
          }
          const code = await this.runOne(step, folder);
          if (code !== 0) {
            ok = false;
            if (steps.length > 1 || folders.length > 1) {
              this.append({ stream: "info", text: tr("Stopped: that step didn't finish cleanly.") + "\n" });
            }
            break outer;
          }
          if (this.stopRequested) break outer;
        }
      }
      if (ok && (steps.length > 1 || folders.length > 1)) this.append({ stream: "info", text: "\n" + tr("✓ All done") + "\n" });
    } finally {
      this.busy = false;
      this.status = {
        title: label,
        state: this.stopRequested ? "stopped" : !ok ? "error" : this.sawStderr ? "warn" : "ok",
      };
      app.refresh();
    }
    return ok;
  }

  private async runOne(step: Step, folder: string): Promise<number | null> {
    const t = this.tool(step.tool);
    if (!t) {
      this.append({
        stream: "stderr",
        text:
          tr("No tool called {tool} — it isn't bundled with the app or in the extra scripts folder", { tool: step.tool }) +
          "\n",
      });
      return 1;
    }
    const takesPath = parseUsage(t.usage).some((u) => u.kind === "option" && u.name === "--path");
    const args = [...step.args, ...(takesPath ? [`--path=${folder}`] : [])];
    this.append({ stream: "info", text: `$ ${[commandName(t), ...args].map(quoteArg).join(" ")}\n` });
    const b = builtin(t.name);
    if (b) return this.runBuiltin(b, step.args, folder);
    let id: number;
    try {
      id = await api.runTool(t.path, args, folder);
    } catch (e) {
      this.append({ stream: "stderr", text: String(e) + "\n" });
      return 1;
    }
    const exited = new Promise<number | null>((resolve) => {
      if (this.earlyExits.has(id)) {
        resolve(this.earlyExits.get(id)!);
        this.earlyExits.delete(id);
      } else {
        this.exits.set(id, resolve);
      }
    });
    this.runId = id;
    for (const c of this.early.get(id) ?? []) this.append(c);
    this.early.clear();
    const code = await exited;
    this.runId = null;
    this.append({
      stream: "info",
      text: exitLine(code),
    });
    return code;
  }

  private async runBuiltin(b: NonNullable<ReturnType<typeof builtin>>, args: string[], folder: string) {
    let code: number | null;
    try {
      code = await b.run({
        folder,
        root: app.root,
        args,
        out: (text) => this.append({ stream: "stdout", text }),
        err: (text) => this.append({ stream: "stderr", text }),
        stopped: () => this.stopRequested,
      });
    } catch (e) {
      this.append({ stream: "stderr", text: `${String(e)}\n` });
      code = 1;
    }
    if (this.stopRequested) code = null;
    this.append({
      stream: "info",
      text: exitLine(code),
    });
    return code;
  }

  async help(t: ToolInfo): Promise<string> {
    return builtin(t.name)?.help ?? api.toolHelp(t.path);
  }

  stop() {
    this.stopRequested = true;
    const id = this.runId;
    if (id === null) return;
    api.stopTool(id).catch(() => {});
    setTimeout(() => {
      const waiter = this.exits.get(id);
      if (waiter) {
        this.exits.delete(id);
        waiter(null);
      }
    }, 1500);
  }

  async sendInput(text: string) {
    if (this.runId === null) return;
    this.append({ stream: "info", text });
    try {
      await api.toolStdin(this.runId, text);
    } catch (e) {
      app.showError(e);
    }
  }

  runInline(steps: Step[], folders: string[], title: string): Promise<boolean> {
    return this.runSteps(steps, folders, title);
  }

  runToolFromMenu(name: string, folders: string[]) {
    this.selection = { kind: "tool", name };
    if (this.requiredInputs(name).length) {
      app.view = "tools";
      app.showInfo(tr("{tool} needs some input first", { tool: prettyToolName(name) }));
      return;
    }
    this.runInline([{ tool: name, args: [] }], folders, prettyToolName(name));
  }

  runChainFromMenu(id: string, folders: string[]) {
    const c = this.chain(id);
    if (!c) return;
    this.selection = { kind: "chain", id };
    this.runInline(c.steps, folders, c.name);
  }
}

export const runner = new Runner();
