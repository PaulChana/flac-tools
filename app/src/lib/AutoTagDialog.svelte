<script lang="ts">
  import { WandSparkles, X } from "@lucide/svelte";
  import { api, type FlacInfo, type TagChange } from "./api";
  import { app } from "./state.svelte";
  import { relative } from "./format";
  import { tagValues } from "./tags";
  import { DETECTABLE, detectTags, type DetectedKey } from "./autotag";
  import { msg, t } from "./i18n";

  let {
    files,
    root,
    base,
    siblings,
    onclose,
    onsaved,
  }: {
    files: FlacInfo[];
    root: string;
    base: string;
    siblings: (path: string) => string[];
    onclose: () => void;
    onsaved: (updated: FlacInfo[]) => void;
  } = $props();

  const LABELS: Record<DetectedKey, string> = {
    TRACKNUMBER: msg("Track"),
    TITLE: msg("Title"),
    ARTIST: msg("Artist"),
    ALBUMARTIST: msg("Album artist"),
    ALBUM: msg("Album"),
    DISCNUMBER: msg("Disc"),
    DATE: msg("Date"),
    YEAR: msg("Year"),
    TRACKTOTAL: msg("Total tracks"),
  };

  let onlyMissing = $state(true);
  let applying = $state(false);
  let progress = $state(0);

  let rows = $derived(
    files.map((f) => ({ file: f, detected: detectTags(f.path, root, siblings(f.path)) })),
  );
  let columns = $derived(DETECTABLE.filter((k) => rows.some((r) => r.detected[k])));
  let enabled = $state<Record<string, boolean>>(Object.fromEntries(DETECTABLE.map((k) => [k, true])));

  type Cell = { value: string; current: string; kind: "none" | "same" | "fill" | "change" | "skip" };

  function cell(f: FlacInfo, value: string | undefined, key: DetectedKey): Cell {
    const current = tagValues(f, key).join("; ");
    if (!value) return { value: "", current, kind: "none" };
    if (value === current) return { value, current, kind: "same" };
    if (!current) return { value, current, kind: "fill" };
    return { value, current, kind: onlyMissing ? "skip" : "change" };
  }

  let plan = $derived(
    rows
      .map((r) => ({
        file: r.file,
        changes: columns
          .filter((k) => enabled[k])
          .map((k) => ({ key: k, c: cell(r.file, r.detected[k], k) }))
          .filter(({ c }) => c.kind === "fill" || c.kind === "change")
          .map(({ key, c }): TagChange => ({ key, value: c.value })),
      }))
      .filter((p) => p.changes.length),
  );
  let tagCount = $derived(plan.reduce((n, p) => n + p.changes.length, 0));

  async function apply() {
    if (!plan.length || applying) return;
    applying = true;
    progress = 0;
    const updated: FlacInfo[] = [];
    try {
      for (const p of plan) {
        updated.push(...(await api.applyTagChanges([p.file.path], p.changes)));
        progress++;
      }
      app.showInfo(
        $t("Wrote {tags, plural, one {# tag} other {# tags}} to {count, plural, one {# file} other {# files}}", {
          values: { tags: tagCount, count: plan.length },
        }),
      );
      onsaved(updated);
      onclose();
    } catch (e) {
      if (updated.length) onsaved(updated);
      app.showError(e);
    } finally {
      applying = false;
    }
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      e.preventDefault();
      onclose();
    } else if (e.key === "Enter" && !(e.target instanceof HTMLButtonElement) && !(e.target instanceof HTMLInputElement)) {
      e.preventDefault();
      apply();
    }
  }
</script>

<svelte:window {onkeydown} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="backdrop" onclick={onclose}>
  <div class="dialog" role="dialog" aria-label={$t("Auto-detect tags")} tabindex="-1" onclick={(e) => e.stopPropagation()}>
    <header>
      <WandSparkles size={16} />
      <h2>{$t("Auto-detect tags for {count, plural, one {# file} other {# files}}", { values: { count: files.length } })}</h2>
      <span class="spacer"></span>
      <button class="icon-btn" onclick={onclose} aria-label={$t("Close")} title={$t("Close (Esc)")}><X size={15} /></button>
    </header>

    <div class="options">
      <p class="muted">
        {$t("Guessed from the file name and folders (Artist / Album / Disc). Tick the columns to write.")}
      </p>
      <label class="check" title={$t("Only write tags that are empty; untick to also replace existing values")}>
        <input type="checkbox" bind:checked={onlyMissing} />
        {$t("Only fill missing tags (leave existing values alone)")}
      </label>
    </div>

    <div class="preview">
      {#if !columns.length}
        <p class="none muted">{$t("Nothing could be worked out from these file names.")}</p>
      {:else}
        <table class="grid">
          <thead>
            <tr>
              <th>{$t("File")}</th>
              {#each columns as k (k)}
                <th>
                  <label class="col" title={$t("Write the detected {tag} values", { values: { tag: k } })}>
                    <input type="checkbox" bind:checked={enabled[k]} />
                    {$t(LABELS[k])}
                  </label>
                </th>
              {/each}
            </tr>
          </thead>
          <tbody>
            {#each rows as r (r.file.path)}
              <tr>
                <td class="file" title={r.file.path}>{relative(r.file.path, base)}</td>
                {#each columns as k (k)}
                  {@const c = cell(r.file, r.detected[k], k)}
                  <td
                    class="v {c.kind}"
                    class:off={!enabled[k]}
                    title={c.kind === "change" || c.kind === "skip"
                      ? $t("Currently: {value}", { values: { value: c.current } })
                      : c.kind === "same"
                        ? $t("Already set")
                        : ""}
                  >
                    {c.value}
                  </td>
                {/each}
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}
    </div>

    <footer>
      <span class="legend">
        <span class="fill">■</span> {$t("fills an empty tag")}
        <span class="change">■</span> {$t("replaces a value")}
        <span class="same">■</span> {$t("already set")}
        {#if onlyMissing}<span class="skip">■</span> {$t("kept (only filling missing)")}{/if}
      </span>
      <span class="spacer"></span>
      <button class="btn" onclick={onclose} title={$t("Close without writing anything (Esc)")}>{$t("Cancel")}</button>
      <button class="btn primary" disabled={!tagCount || applying} onclick={apply} title={$t("Write the ticked tags to the files (Enter)")}>
        {applying
          ? $t("Writing {done}/{total}…", { values: { done: progress, total: plan.length } })
          : tagCount
            ? $t("Write {tags, plural, one {# tag} other {# tags}} to {count, plural, one {# file} other {# files}}", {
                values: { tags: tagCount, count: plan.length },
              })
            : $t("Nothing to write")}
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
    width: min(1200px, 100%);
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
    padding: 10px 18px 12px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .options p {
    margin: 0;
  }
  .check,
  .col {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .col {
    color: var(--fg);
  }
  .preview {
    flex: 1;
    min-height: 160px;
    overflow: auto;
  }
  .none {
    padding: 20px 18px;
  }
  td.file {
    color: var(--fg-muted);
    max-width: 300px;
  }
  td.v {
    max-width: 260px;
  }
  .fill {
    color: var(--accent);
    font-weight: 500;
  }
  .change {
    color: var(--warn);
    font-weight: 500;
  }
  .same {
    color: var(--fg-faint);
  }
  .skip {
    color: var(--fg-faint);
    text-decoration: line-through;
  }
  td.off {
    opacity: 0.3;
  }
  footer {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 18px;
    border-top: 1px solid var(--border);
  }
  .legend {
    display: flex;
    gap: 6px 12px;
    flex-wrap: wrap;
    font-size: 12px;
    color: var(--fg-muted);
  }
  .legend span {
    text-decoration: none;
    margin-left: 6px;
  }
</style>
