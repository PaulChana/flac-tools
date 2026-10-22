<script lang="ts">
  import { ArrowUp, ArrowDown, X, Plus, Play, Trash2, Link, TriangleAlert } from "@lucide/svelte";
  import { runner, quoteArg, type Chain, type Step } from "./runner.svelte";
  import { app } from "./state.svelte";
  import { contextMenu } from "./menu.svelte";
  import { parseUsage, prettyToolName, shellSplit, unwrap } from "./args";
  import { t } from "./i18n";

  let { chain, targetLabel }: { chain: Chain; targetLabel: string } = $props();

  let dryRun = $state(false);

  function move(i: number, d: number) {
    const j = i + d;
    if (j < 0 || j >= chain.steps.length) return;
    [chain.steps[i], chain.steps[j]] = [chain.steps[j], chain.steps[i]];
    runner.changed();
  }

  function remove(i: number) {
    chain.steps.splice(i, 1);
    runner.changed();
  }

  function setArgs(step: Step, text: string) {
    step.args = shellSplit(text);
    runner.changed();
  }

  function addStepMenu() {
    contextMenu(
      runner.tools.map((tl) => ({
        text: prettyToolName(tl.name),
        tip: unwrap(tl.description),
        action: () => runner.addStep(chain.id, { tool: tl.name, args: [] }),
      })),
    );
  }

  const supportsDryRun = (tool: string) =>
    parseUsage(runner.tool(tool)?.usage ?? "").some((u) => u.kind === "flag" && u.name === "--dry-run");

  function run() {
    const steps = chain.steps.map((s) =>
      dryRun && supportsDryRun(s.tool) && !s.args.includes("--dry-run") ? { ...s, args: [...s.args, "--dry-run"] } : s,
    );
    runner.runSteps(steps, app.folders, dryRun ? $t("{chain} (dry run)", { values: { chain: chain.name } }) : chain.name);
  }

  function problem(step: Step): string | null {
    if (!runner.tool(step.tool)) return $t("This tool isn't in the scripts folder any more");
    const need = runner.requiredInputs(step.tool);
    const given = step.args.filter((a) => !a.startsWith("--")).length;
    if (given < need.length) return $t("Needs {inputs} — add them to its arguments", { values: { inputs: need.join(", ") } });
    return null;
  }
</script>

<div class="form">
  <div class="title-row">
    <Link size={16} />
    <input
      class="name"
      bind:value={chain.name}
      onchange={() => runner.changed()}
      spellcheck="false"
      aria-label={$t("Chain name")}
      data-chain-name
      title={$t("Chain name — click to rename")}
    />
    <span class="spacer"></span>
    <button class="btn danger" onclick={() => runner.confirmDeleteChain(chain.id)} title={$t("Delete this chain")}>
      <Trash2 size={13} /> {$t("Delete")}
    </button>
  </div>
  <p class="desc">{$t("Runs each step in order on {target}, stopping if one fails.", { values: { target: targetLabel } })}</p>

  <ol class="steps">
    {#each chain.steps as step, i (i + step.tool)}
      {@const why = problem(step)}
      <li class="step">
        <span class="num">{i + 1}</span>
        <div class="body">
          <div class="step-name">
            {prettyToolName(step.tool)}
            {#if why}<span class="warn" title={why}><TriangleAlert size={12} /> {why}</span>{/if}
          </div>
          <input
            class="args"
            value={step.args.map(quoteArg).join(" ")}
            onchange={(e) => setArgs(step, e.currentTarget.value)}
            placeholder={$t("No extra arguments")}
            spellcheck="false"
            aria-label={$t("Arguments")}
            title={$t("Arguments for this step, like a shell command line")}
          />
        </div>
        <div class="step-btns">
          <button class="icon-btn" title={$t("Move up")} disabled={i === 0} onclick={() => move(i, -1)}><ArrowUp size={13} /></button>
          <button class="icon-btn" title={$t("Move down")} disabled={i === chain.steps.length - 1} onclick={() => move(i, 1)}>
            <ArrowDown size={13} />
          </button>
          <button class="icon-btn" title={$t("Remove step")} onclick={() => remove(i)}><X size={13} /></button>
        </div>
      </li>
    {:else}
      <li class="empty muted">{$t("No steps yet. Add one below, or use “Add to chain” on any tool.")}</li>
    {/each}
  </ol>

  <div class="run-row">
    <button class="btn" onclick={addStepMenu} title={$t("Add a tool to the end of this chain")}>
      <Plus size={13} /> {$t("Add step")}
    </button>
    <span class="spacer"></span>
    <label class="flag" class:dry={dryRun} title={$t("Run every step that supports it as a dry run, changing nothing")}><input type="checkbox" bind:checked={dryRun} /> --dry-run</label>
    <button
      class="btn primary"
      disabled={!chain.steps.length || runner.busy}
      title={runner.busy ? $t("Wait for the running tool to finish") : $t("Run each step in order on the selected folders")}
      onclick={run}
    >
      <Play size={13} /> {dryRun ? $t("Dry run chain") : $t("Run chain")}
    </button>
  </div>
</div>

<style>
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
  .name {
    font-size: 16px;
    font-weight: 600;
    min-width: 0;
    width: 340px;
    height: 32px;
  }
  .spacer {
    flex: 1;
  }
  .desc {
    color: var(--fg-muted);
    margin: 8px 0 12px;
  }
  .steps {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .step {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 8px 8px 10px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--bg-sidebar);
  }
  .num {
    flex: none;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--bg-selected-muted);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 600;
  }
  .body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 5px;
  }
  .step-name {
    font-weight: 500;
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .warn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--warn);
    font-weight: 400;
    font-size: 12px;
  }
  .args {
    font-family: var(--mono);
    font-size: 12px;
    height: 28px;
  }
  .step-btns {
    display: flex;
    flex: none;
  }
  .empty {
    padding: 10px 0;
  }
  .run-row {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 12px;
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
</style>
