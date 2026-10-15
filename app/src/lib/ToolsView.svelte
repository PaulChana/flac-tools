<script lang="ts">
  import { tick } from "svelte";
  import { Play, Wrench, FolderCog, FolderOpen, CircleHelp, RefreshCw, Plus, Link, ListPlus } from "@lucide/svelte";
  import { open } from "@tauri-apps/plugin-dialog";
  import { api } from "./api";
  import { app } from "./state.svelte";
  import { runner, quoteArg } from "./runner.svelte";
  import { contextMenu } from "./menu.svelte";
  import { COMMON_FLAGS, parseUsage, prettyToolName, shellSplit, summary } from "./args";
  import { basename, relative } from "./format";
  import { commandName } from "./builtins";
  import { t, msg } from "./i18n";
  import ChainEditor from "./ChainEditor.svelte";

  let flags = $state<Record<string, boolean>>({});
  let values = $state<Record<string, string>>({});
  let extra = $state("");

  let sel = $derived(runner.selection);
  let tool = $derived(sel?.kind === "tool" ? (runner.tool(sel.name) ?? null) : null);
  let chain = $derived(sel?.kind === "chain" ? (runner.chain(sel.id) ?? null) : null);

  let usage = $derived(tool ? parseUsage(tool.usage) : []);
  let toolFlags = $derived(usage.filter((u) => u.kind === "flag" && !COMMON_FLAGS.includes(u.name)));
  let commonFlags = $derived(usage.filter((u) => u.kind === "flag" && COMMON_FLAGS.includes(u.name)));
  let options = $derived(usage.filter((u) => u.kind === "option" && u.name !== "--path"));
  let positionals = $derived(usage.filter((u) => u.kind === "positional"));
  let takesPath = $derived(usage.some((u) => u.kind === "option" && u.name === "--path"));

  let args = $derived.by(() => {
    const out: string[] = [];
    for (const p of positionals) {
      if (p.kind !== "positional") continue;
      const v = values[p.name]?.trim() ?? "";
      if (!v) continue;
      out.push(...(p.variadic ? shellSplit(v) : [v]));
    }
    for (const u of usage) {
      if (u.kind === "flag" && flags[u.name]) out.push(u.name);
      if (u.kind === "option" && u.name !== "--path" && values[u.name]?.trim()) {
        out.push(`${u.name}=${values[u.name].trim()}`);
      }
    }
    out.push(...shellSplit(extra));
    return out;
  });

  let missing = $derived(
    positionals.filter((p) => p.kind === "positional" && !p.optional && !values[p.name]?.trim()).map((p) => p.name),
  );

  let targetLabel = $derived(
    app.folders.length > 1
      ? $t("{count, plural, one {# folder} other {# folders}}", { values: { count: app.folders.length } })
      : app.current === app.root
        ? app.root
        : relative(app.current, app.root),
  );

  let commandPreview = $derived(
    tool
      ? [commandName(tool), ...args, ...(takesPath ? [`--path=${app.folders.length > 1 ? "…" : app.current}`] : [])]
          .map(quoteArg)
          .join(" ")
      : "",
  );

  let formFor = "";
  $effect(() => {
    const name = tool?.name ?? "";
    if (name === formFor) return;
    formFor = name;
    flags = {};
    values = {};
    extra = "";
  });

  const MODE_TIPS: Record<string, string> = {
    "--dry-run": msg("Show what would change without changing anything"),
    "--verbose": msg("Also list files that need no change"),
    "--quiet": msg("Only print warnings and the summary"),
  };
  const modeTip = (flag: string) => MODE_TIPS[flag] ?? msg("Pass this flag to the tool");

  function pickTool(name: string) {
    runner.selection = { kind: "tool", name };
  }

  async function reload() {
    await runner.loadTools();
    if (!runner.selection && runner.tools[0]) pickTool(runner.tools[0].name);
  }

  function scriptsMenu() {
    contextMenu([
      {
        text: app.extraToolsDir ? $t("Change extra scripts folder…") : $t("Add a folder of extra scripts…"),
        action: async () => {
          const dir = await open({ directory: true, defaultPath: app.extraToolsDir || undefined });
          if (typeof dir === "string") {
            app.setExtraToolsDir(dir);
            reload();
          }
        },
      },
      {
        text: app.extraToolsDir
          ? $t("Stop using “{folder}”", { values: { folder: basename(app.extraToolsDir) } })
          : $t("No extra scripts folder"),
        enabled: !!app.extraToolsDir,
        action: () => {
          app.setExtraToolsDir("");
          reload();
        },
      },
      "separator",
      {
        text: $t("Show bundled scripts in Finder"),
        action: async () => {
          try {
            await api.revealInFinder(await api.bundledToolsDir());
          } catch (e) {
            app.showError(e);
          }
        },
      },
    ]);
  }

  function run() {
    if (!tool || missing.length) return;
    runner.runSteps([{ tool: tool.name, args }], app.folders, prettyToolName(tool.name));
  }

  function addToChainMenu() {
    if (!tool) return;
    const step = { tool: tool.name, args: [...args] };
    contextMenu([
      ...runner.chains.map((c) => ({
        text: $t("Add to “{chain}”", { values: { chain: c.name } }),
        action: () => {
          runner.addStep(c.id, step);
          app.showInfo($t("Added {tool} to {chain}", { values: { tool: prettyToolName(step.tool), chain: c.name } }));
        },
      })),
      ...(runner.chains.length ? ["separator" as const] : []),
      {
        text: $t("New chain…"),
        action: () => {
          const c = runner.newChain([step]);
          runner.selection = { kind: "chain", id: c.id };
        },
      },
    ]);
  }

  function chainMenu(e: MouseEvent, id: string) {
    e.preventDefault();
    const select = () => (runner.selection = { kind: "chain", id });
    contextMenu([
      { text: $t("Edit"), action: select },
      {
        text: $t("Rename"),
        action: async () => {
          select();
          await tick();
          document.querySelector<HTMLInputElement>('input[data-chain-name]')?.select();
        },
      },
      {
        text: $t("Duplicate"),
        action: () => {
          const copy = runner.duplicateChain(id);
          if (copy) runner.selection = { kind: "chain", id: copy.id };
        },
      },
      "separator",
      { text: $t("Delete…"), action: () => runner.confirmDeleteChain(id) },
    ]);
  }

  function newChain() {
    const c = runner.newChain();
    runner.selection = { kind: "chain", id: c.id };
  }

  async function showHelp() {
    if (!tool || runner.busy) return;
    runner.clear();
    runner.append({ stream: "info", text: `$ ${commandName(tool)} --help\n\n` });
    try {
      runner.append({ stream: "stdout", text: await runner.help(tool) });
    } catch (e) {
      runner.append({ stream: "stderr", text: String(e) });
    }
  }

  $effect(() => {
    if (!runner.selection && runner.tools.length) pickTool(runner.tools[0].name);
  });
</script>

<div class="tools">
  <div class="list">
    <div class="list-head">
      <span class="section-title">{$t("Tools")}</span>
      <span class="spacer"></span>
      <button class="icon-btn" title={$t("Reload scripts")} onclick={reload}><RefreshCw size={14} /></button>
      <button
        class="icon-btn"
        title={app.extraToolsDir
          ? $t("Extra scripts: {folder}", { values: { folder: app.extraToolsDir } })
          : $t("Add a folder of extra scripts")}
        onclick={scriptsMenu}
      >
        <FolderCog size={14} />
      </button>
    </div>
    {#if runner.toolsError}
      <p class="list-error">{runner.toolsError}</p>
    {/if}
    {#each runner.tools as tl (tl.name)}
      <button
        class="tool"
        class:selected={sel?.kind === "tool" && sel.name === tl.name}
        onclick={() => pickTool(tl.name)}
        title={summary(tl.description)}
      >
        <span class="tool-name">
          {prettyToolName(tl.name)}
          {#if tl.source === "extra"}<span class="extra" title={$t("From {folder}", { values: { folder: app.extraToolsDir } })}><FolderOpen size={11} /></span>{/if}
        </span>
        <span class="tool-summary">{summary(tl.description)}</span>
      </button>
    {/each}

    <div class="group">
      <span class="section-title">{$t("Chains")}</span>
      <span class="spacer"></span>
      <button class="icon-btn" title={$t("New chain")} onclick={newChain}><Plus size={14} /></button>
    </div>
    {#each runner.chains as c (c.id)}
      <button
        class="tool"
        class:selected={sel?.kind === "chain" && sel.id === c.id}
        onclick={() => (runner.selection = { kind: "chain", id: c.id })}
        oncontextmenu={(e) => chainMenu(e, c.id)}
        title={$t("Click to edit · right-click for more")}
      >
        <span class="tool-name"><Link size={12} /> {c.name}</span>
        <span class="chain-steps">
          {c.steps.length ? c.steps.map((s) => prettyToolName(s.tool)).join(" → ") : $t("No steps yet")}
        </span>
      </button>
    {:else}
      <p class="list-empty muted">{$t("Use “Add to chain” on a tool to start one.")}</p>
    {/each}
  </div>

  <div class="detail">
    {#if chain}
      <ChainEditor {chain} {targetLabel} />
    {:else if tool}
      <div class="form">
        <div class="title-row">
          <Wrench size={16} />
          <h2>{prettyToolName(tool.name)}</h2>
          <code class="muted" title={tool.builtin ? $t("Built into the app") : tool.path}>{commandName(tool)}</code>
          <span class="spacer"></span>
          <button class="btn" onclick={showHelp} disabled={runner.busy} title={runner.busy ? $t("Wait for the running tool to finish") : $t("Show the tool's full help in the output panel")}>
            <CircleHelp size={13} /> {$t("Help")}
          </button>
        </div>
        <p class="desc">{tool.description}</p>

        <div class="fields">
          {#if takesPath}
            <div class="field">
              <span class="label">{$t("Folder")}</span>
              <span class="path" title={app.folders.join("\n")}>{targetLabel}</span>
              <span class="hint">{$t("Pick folders in the sidebar to change it (⌘-click for several).")}</span>
            </div>
          {/if}

          {#each positionals as p}
            {#if p.kind === "positional"}
              <label class="field">
                <span class="label">{p.name}{p.optional ? "" : " *"}</span>
                <input
                  bind:value={values[p.name]}
                  placeholder={p.variadic ? $t("One or more, space separated") : ""}
                  spellcheck="false"
                  title={p.optional ? $t("Optional input for the tool") : $t("Required input for the tool")}
                />
              </label>
            {/if}
          {/each}

          {#each options as o}
            {#if o.kind === "option"}
              <label class="field">
                <span class="label">{o.name}</span>
                <input bind:value={values[o.name]} placeholder={o.meta} spellcheck="false" title={$t("Passed as {option}=…", { values: { option: o.name } })} />
              </label>
            {/if}
          {/each}

          {#if toolFlags.length}
            <div class="field">
              <span class="label">{$t("Options")}</span>
              <div class="flags">
                {#each toolFlags as f}
                  <label class="flag" title={$t("Pass {flag} to the tool", { values: { flag: f.name } })}>
                    <input type="checkbox" bind:checked={flags[f.name]} /> {f.name}
                  </label>
                {/each}
              </div>
            </div>
          {/if}

          {#if commonFlags.length}
            <div class="field">
              <span class="label">{$t("Mode")}</span>
              <div class="flags">
                {#each commonFlags as f}
                  <label class="flag" class:dry={f.name === "--dry-run" && flags[f.name]} title={$t(modeTip(f.name))}>
                    <input type="checkbox" bind:checked={flags[f.name]} /> {f.name}
                  </label>
                {/each}
              </div>
            </div>
          {/if}

          <label class="field">
            <span class="label">{$t("Extra args")}</span>
            <input
              bind:value={extra}
              placeholder={$t("Anything else to pass through")}
              spellcheck="false"
              title={$t("More arguments for the tool, split like a shell command line")}
            />
          </label>
        </div>

        <div class="run-row">
          <code class="preview" title={commandPreview}>{commandPreview}</code>
          <button class="btn" onclick={addToChainMenu} title={$t("Save this tool and its options as a step in a chain")}>
            <ListPlus size={13} /> {$t("Add to chain")}
          </button>
          <button
            class="btn primary"
            onclick={run}
            disabled={missing.length > 0 || runner.busy}
            title={runner.busy
              ? $t("Wait for the running tool to finish")
              : missing.length
                ? $t("Fill in {fields}", { values: { fields: missing.join(", ") } })
                : $t("Run the tool on the selected folders")}
          >
            <Play size={13} /> {flags["--dry-run"] ? $t("Dry run") : $t("Run")}
          </button>
        </div>
      </div>
    {:else}
      <div class="none muted">{$t("No tools found")}</div>
    {/if}
  </div>
</div>

<style>
  .tools {
    display: flex;
    height: 100%;
    min-width: 0;
  }
  .list {
    width: 250px;
    flex: none;
    border-right: 1px solid var(--border);
    overflow: auto;
    padding-bottom: 10px;
  }
  .list-head {
    display: flex;
    align-items: center;
    height: 34px;
    padding: 0 6px 0 var(--pane-pad);
    position: sticky;
    top: 0;
    background: var(--bg);
  }
  .group {
    display: flex;
    align-items: center;
    height: 30px;
    margin-top: 10px;
    padding: 0 6px 0 14px;
  }
  .chain-steps {
    font-size: 12px;
    color: var(--fg-muted);
  }
  .tool.selected .chain-steps {
    color: color-mix(in srgb, var(--fg-selected) 80%, transparent);
  }
  .list-empty {
    padding: 2px 14px 6px;
    margin: 0;
    font-size: 12px;
  }
  .list-error {
    color: var(--danger);
    padding: 0 14px;
    font-size: 13px;
  }
  .spacer {
    flex: 1;
  }
  .tool {
    display: flex;
    flex-direction: column;
    gap: 2px;
    width: calc(100% - 12px);
    margin: 0 6px 2px;
    padding: calc(4px + var(--row-padding)) 9px;
    border: none;
    border-radius: 6px;
    background: none;
    text-align: left;
  }
  .tool:hover {
    background: var(--bg-hover);
  }
  .tool.selected {
    background: var(--bg-selected);
    color: var(--fg-selected);
  }
  .tool-name {
    font-weight: 500;
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }
  .extra {
    display: inline-flex;
    color: var(--accent);
  }
  .tool.selected .extra {
    color: inherit;
  }
  .tool-summary {
    font-size: 12px;
    color: var(--fg-muted);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .tool.selected .tool-summary {
    color: color-mix(in srgb, var(--fg-selected) 80%, transparent);
  }
  .detail {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .form {
    padding: 14px var(--pane-pad);
    flex: 1;
    min-height: 0;
    overflow: auto;
  }
  .title-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  h2 {
    margin: 0;
    font-size: 16px;
  }
  .desc {
    white-space: pre-wrap;
    color: var(--fg-muted);
    margin: 8px 0 14px;
    line-height: 1.45;
    user-select: text;
    -webkit-user-select: text;
  }
  .fields {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .field {
    display: grid;
    grid-template-columns: 110px 1fr;
    align-items: center;
    gap: 4px 10px;
  }
  .field .hint {
    grid-column: 2;
    font-size: 12px;
    color: var(--fg-faint);
  }
  .label {
    color: var(--fg-muted);
    text-align: right;
    font-size: 13px;
  }
  .path {
    font-family: var(--mono);
    font-size: 13px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .flags {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 14px;
  }
  .flag {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-family: var(--mono);
    font-size: 13px;
  }
  .flag.dry {
    color: var(--warn);
  }
  .run-row {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 14px;
  }
  .preview {
    flex: 1;
    min-width: 0;
    font-family: var(--mono);
    font-size: 12px;
    color: var(--fg-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    user-select: text;
    -webkit-user-select: text;
  }
  .none {
    margin: auto;
  }
</style>
