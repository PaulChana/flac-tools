<script lang="ts">
  import { Eraser, CornerDownLeft, Square, X, LoaderCircle, CircleCheck, CircleAlert, TriangleAlert, CircleStop } from "@lucide/svelte";
  import { tick } from "svelte";
  import { runner } from "./runner.svelte";
  import { layout } from "./layout.svelte";
  import { t, msg } from "./i18n";

  let consoleEl = $state<HTMLPreElement>();
  let stdinText = $state("");

  let following = true;
  $effect(() => {
    void runner.outputVersion;
    if (!following) return;
    tick().then(() => {
      if (consoleEl) consoleEl.scrollTop = consoleEl.scrollHeight;
    });
  });

  function onScroll() {
    if (consoleEl) following = consoleEl.scrollHeight - consoleEl.scrollTop - consoleEl.clientHeight < 24;
  }

  function send(e: SubmitEvent) {
    e.preventDefault();
    runner.sendInput(stdinText + "\n");
    stdinText = "";
  }

  const STATE = {
    running: msg("Running…"),
    ok: msg("Finished"),
    warn: msg("Finished with warnings"),
    error: msg("Failed"),
    stopped: msg("Stopped"),
  } as const;
</script>

<section class="output" aria-label={$t("Tool output")}>
  <div class="head">
    {#if runner.status}
      <span class="state {runner.status.state}">
        {#if runner.status.state === "running"}
          <LoaderCircle size={14} class="spin" />
        {:else if runner.status.state === "ok"}
          <CircleCheck size={14} />
        {:else if runner.status.state === "warn"}
          <CircleAlert size={14} />
        {:else if runner.status.state === "stopped"}
          <CircleStop size={14} />
        {:else}
          <TriangleAlert size={14} />
        {/if}
      </span>
      <span class="title">{runner.status.title}</span>
      <span class="state-text {runner.status.state}">{$t(STATE[runner.status.state])}</span>
    {:else}
      <span class="section-title">{$t("Output")}</span>
    {/if}
    <span class="spacer"></span>
    {#if runner.busy}
      <button class="btn danger stop" onclick={() => runner.stop()} title={$t("Stop the running tool")}>
        <Square size={11} /> {$t("Stop")}
      </button>
    {/if}
    <button class="icon-btn" title={$t("Clear the output")} onclick={() => runner.clear()} disabled={runner.busy}>
      <Eraser size={13} />
    </button>
    <button class="icon-btn" title={$t("Hide the output panel")} onclick={() => layout.toggle("Bottom", false)}>
      <X size={14} />
    </button>
  </div>
  <pre class="console" bind:this={consoleEl} onscroll={onScroll}>{#each runner.output as c}<span class={c.stream}>{c.text}</span>{/each}{#if !runner.output.length}<span class="empty">{$t("Tool output appears here when you run a tool or chain.")}</span>{/if}</pre>
  {#if runner.runId !== null}
    <form class="stdin" onsubmit={send}>
      <input bind:value={stdinText} placeholder={$t("Send input to the script…")} spellcheck="false" title={$t("Type a reply to the script and press Return")} />
      <button class="icon-btn" type="submit" title={$t("Send to the script")}><CornerDownLeft size={14} /></button>
    </form>
  {/if}
</section>

<style>
  .output {
    height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--panel-background);
  }
  .head {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
    padding: 0 6px 0 14px;
    flex: none;
    border-bottom: 1px solid var(--border-subtle);
  }
  .title {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .state {
    display: inline-flex;
    color: var(--fg-muted);
  }
  .state-text {
    font-size: 12px;
    color: var(--fg-muted);
    white-space: nowrap;
  }
  .ok {
    color: var(--success);
  }
  .warn,
  .running {
    color: var(--warn);
  }
  .error {
    color: var(--danger);
  }
  .stop {
    height: 24px;
    background: transparent;
  }
  .spacer {
    flex: 1;
  }
  .console {
    flex: 1;
    margin: 0;
    padding: 8px 14px 14px;
    overflow: auto;
    font-family: var(--mono);
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--fg-console);
    background: var(--bg-console);
    white-space: pre-wrap;
    word-break: break-all;
    user-select: text;
    -webkit-user-select: text;
  }
  .console .stderr {
    color: var(--danger);
  }
  .console .info {
    color: var(--accent-readable);
  }
  .console .empty {
    color: var(--fg-faint);
    font-family: var(--font);
  }
  .stdin {
    display: flex;
    gap: 6px;
    padding: 8px 10px;
    border-top: 1px solid var(--border-subtle);
  }
  .stdin input {
    flex: 1;
    font-family: var(--mono);
    font-size: 13px;
  }
</style>
