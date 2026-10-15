<script lang="ts">
  import { ArrowRight, TextCursorInput, X, TriangleAlert } from "@lucide/svelte";
  import { onMount } from "svelte";
  import { api } from "./api";
  import { app } from "./state.svelte";
  import { relative } from "./format";
  import { emptyRenameOptions, preview, type PreviewRow, type PreviewStatus } from "./rename";
  import { msg, t } from "./i18n";

  let {
    files,
    existing,
    base,
    onclose,
  }: {
    files: { path: string; name: string; tags?: [string, string][] }[];
    existing: string[];
    base: string;
    onclose: () => void;
  } = $props();

  const saved = (() => {
    try {
      return { ...emptyRenameOptions(), ...JSON.parse(localStorage.getItem("renameOptions") ?? "{}") };
    } catch {
      return emptyRenameOptions();
    }
  })();
  let opts = $state(saved);
  let applying = $state(false);
  let first = $state<HTMLInputElement>();

  $effect(() => {
    try {
      localStorage.setItem("renameOptions", JSON.stringify(opts));
    } catch {
    }
  });

  let result = $derived.by((): { rows: PreviewRow[]; error: string | null } => {
    try {
      return { rows: preview(files, opts, existing), error: null };
    } catch (e) {
      return { rows: [], error: (e as Error).message };
    }
  });
  let changes = $derived(result.rows.filter((r) => r.status === "ok"));
  let problems = $derived(result.rows.filter((r) => !["ok", "unchanged"].includes(r.status)));
  let canApply = $derived(!result.error && changes.length > 0 && problems.length === 0 && !applying);

  const statusText: Record<PreviewStatus, string> = {
    unchanged: "",
    ok: "",
    empty: msg("Name would be empty"),
    invalid: msg("Can't contain “/”"),
    duplicate: msg("Same name as another file"),
    exists: msg("A file with this name exists"),
    notag: msg("Tag not set"),
  };
  const statusLabel = (s: PreviewStatus) => (statusText[s] ? $t(statusText[s]) : "");

  onMount(() => first?.focus());

  async function apply() {
    if (!canApply) return;
    applying = true;
    try {
      await api.renameBatch(changes.map((r) => ({ path: r.path, newName: r.newName })));
      app.applyRenames(changes.map((r) => ({ from: r.path, to: `${r.dir}/${r.newName}` })));
      app.showInfo($t("Renamed {count, plural, one {# file} other {# files}}", { values: { count: changes.length } }));
      onclose();
    } catch (e) {
      app.showError(e);
    } finally {
      applying = false;
    }
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      e.preventDefault();
      onclose();
    } else if (e.key === "Enter" && !(e.target instanceof HTMLButtonElement)) {
      e.preventDefault();
      apply();
    }
  }

  const num = (v: string) => Math.max(0, Math.floor(Number(v) || 0));
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="backdrop" onclick={onclose}>
  <div class="dialog" role="dialog" aria-label={$t("Rename files")} tabindex="-1" onclick={(e) => e.stopPropagation()} {onkeydown}>
    <header>
      <TextCursorInput size={16} />
      <h2>{$t("Rename {count, plural, one {# file} other {# files}}", { values: { count: files.length } })}</h2>
      <span class="spacer"></span>
      <button class="icon-btn" onclick={onclose} aria-label={$t("Close")} title={$t("Close (Esc)")}><X size={15} /></button>
    </header>

    <div class="options">
      <label class="field">
        <span class="label">{$t("Remove")}</span>
        <input
          bind:this={first}
          bind:value={opts.remove}
          placeholder={$t("Text to take out")}
          spellcheck="false"
          title={$t("Text to delete from every name")}
        />
      </label>
      <div class="field">
        <span class="label">{$t("Replace")}</span>
        <div class="pair">
          <input
            bind:value={opts.replace}
            placeholder={$t("Find")}
            spellcheck="false"
            aria-label={$t("Find")}
            title={$t("Text to find in every name")}
          />
          <ArrowRight size={14} class="arrow" />
          <input
            bind:value={opts.with}
            placeholder={opts.regex
              ? $t("Replace with — {group} for groups, {example} for tags", {
                  values: { group: "$1", example: "{TRACKNUMBER:2}" },
                })
              : $t("Replace with — {examples}… for tags", { values: { examples: "{TRACKNUMBER:2}, {TITLE}" } })}
            spellcheck="false"
            aria-label={$t("Replace with")}
            title={$t("What to put in place of the found text; may include tag placeholders like {example}", {
              values: { example: "{TITLE}" },
            })}
          />
        </div>
      </div>
      <div class="field">
        <span class="label"></span>
        <label class="check" title={$t("Treat Remove and Find as regular expressions instead of plain text")}>
          <input type="checkbox" bind:checked={opts.regex} /> {$t("Use regular expressions for Remove and Replace")}
        </label>
      </div>
      <div class="field">
        <span class="label">{$t("Strip")}</span>
        <div class="strips">
          <label title={$t("Number of characters to cut from the start of each name")}>
            {$t("first")}
            <input
              type="number"
              min="0"
              value={opts.stripStart}
              oninput={(e) => (opts.stripStart = num(e.currentTarget.value))}
            />
            {$t("characters")}
          </label>
          <label title={$t("Number of characters to cut from the end of each name (before the extension)")}>
            {$t("last")}
            <input
              type="number"
              min="0"
              value={opts.stripEnd}
              oninput={(e) => (opts.stripEnd = num(e.currentTarget.value))}
            />
            {$t("characters")}
          </label>
        </div>
      </div>
      <p class="note muted">
        {$t("Edits apply to the name without its extension, in this order: strip, remove, replace.")}
        {@html $t("In “Replace with”, {tag} inserts a tag’s value and {pad} pads a number to two digits — e.g. {example}.", {
          values: {
            tag: "<code>{TAG}</code>",
            pad: "<code>{TAG:2}</code>",
            example: "<code>{TRACKNUMBER:2} - {TITLE}</code>",
          },
        })}
      </p>
    </div>

    <div class="preview">
      {#if result.error}
        <p class="error"><TriangleAlert size={14} /> {result.error}</p>
      {/if}
      <table class="grid">
        <thead>
          <tr><th>{$t("Current name")}</th><th>{$t("New name")}</th></tr>
        </thead>
        <tbody>
          {#each result.rows as r (r.path)}
            {@const bad = !["ok", "unchanged"].includes(r.status)}
            <tr class:bad>
              <td class="old" title={r.path}>{relative(r.path, base)}</td>
              <td class="new" class:changed={r.status === "ok"} class:same={r.status === "unchanged"} title={statusLabel(r.status)}>
                {#if bad}<TriangleAlert size={12} />{/if}
                {r.status === "unchanged" ? "—" : r.newName}
                {#if bad}<span class="why">{r.status === "notag"
                    ? $t("{count, plural, one {No {tags} tag} other {No {tags} tags}}", {
                        values: { count: new Set(r.missingTags).size, tags: [...new Set(r.missingTags)].join(", ") },
                      })
                    : statusLabel(r.status)}</span>{/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    <footer>
      <span class="muted summary">
        {#if problems.length}
          <span class="warn">
            {$t("{count, plural, one {# problem} other {# problems}} to fix", { values: { count: problems.length } })}
          </span>
        {:else}
          {$t("{count} of {total} will be renamed", { values: { count: changes.length, total: files.length } })}
        {/if}
      </span>
      <span class="spacer"></span>
      <button class="btn" onclick={() => (opts = emptyRenameOptions())} title={$t("Reset all the rename options")}>
        {$t("Clear")}
      </button>
      <button class="btn" onclick={onclose} title={$t("Close without renaming anything (Esc)")}>{$t("Cancel")}</button>
      <button class="btn primary" disabled={!canApply} onclick={apply} title={$t("Rename the files as shown (Enter)")}>
        {applying
          ? $t("Renaming…")
          : changes.length
            ? $t("Rename {count}", { values: { count: changes.length } })
            : $t("Rename")}
      </button>
    </footer>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 20;
    background: rgba(0, 0, 0, 0.35);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
  }
  .dialog {
    width: min(860px, 100%);
    max-height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--bg);
    border: 1px solid var(--border-strong);
    border-radius: 10px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
    outline: none;
    overflow: hidden;
  }
  header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 12px 12px 18px;
    border-bottom: 1px solid var(--border);
  }
  h2 {
    margin: 0;
    font-size: 15px;
  }
  .spacer {
    flex: 1;
  }
  .options {
    padding: 14px 18px 8px;
    display: flex;
    flex-direction: column;
    gap: 9px;
    border-bottom: 1px solid var(--border);
  }
  .field {
    display: grid;
    grid-template-columns: 80px 1fr;
    align-items: center;
    gap: 10px;
  }
  .field > input {
    height: 30px;
  }
  .label {
    text-align: right;
    color: var(--fg-muted);
  }
  .pair {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .pair input {
    flex: 1;
    min-width: 0;
    height: 30px;
  }
  .pair :global(.arrow) {
    color: var(--fg-muted);
    flex: none;
  }
  .check {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .strips {
    display: flex;
    gap: 22px;
  }
  .strips label {
    display: flex;
    align-items: center;
    gap: 6px;
    color: var(--fg-muted);
  }
  .strips input {
    width: 64px;
    height: 30px;
    background: var(--bg-input);
    border: 1px solid var(--border-strong);
    border-radius: 5px;
    padding: 4px 7px;
    color: var(--fg);
  }
  .note {
    margin: 2px 0 4px 90px;
    font-size: 12px;
  }
  .note :global(code) {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--fg);
  }
  .preview {
    flex: 1;
    min-height: 160px;
    overflow: auto;
  }
  .preview table {
    width: 100%;
  }
  .preview td {
    max-width: 380px;
  }
  td.old {
    color: var(--fg-muted);
  }
  td.new.changed {
    color: var(--accent);
    font-weight: 500;
  }
  td.new.same {
    color: var(--fg-faint);
  }
  tr.bad td.new {
    color: var(--danger);
  }
  .why {
    margin-left: 8px;
    font-size: 12px;
    opacity: 0.85;
  }
  .error {
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 10px 18px;
    color: var(--danger);
  }
  footer {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 18px;
    border-top: 1px solid var(--border);
  }
  .warn {
    color: var(--danger);
  }
</style>
