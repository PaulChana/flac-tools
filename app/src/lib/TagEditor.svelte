<script lang="ts">
  import { Plus, X, Tags, ImageOff, CornerDownLeft, WandSparkles, ListOrdered } from "@lucide/svelte";
  import { contextMenu } from "./menu.svelte";
  import AutoTagDialog from "./AutoTagDialog.svelte";
  import { untrack } from "svelte";
  import { ask } from "@tauri-apps/plugin-dialog";
  import { api, type FlacInfo, type PictureInfo, type TagChange, type TagPair } from "./api";
  import { app } from "./state.svelte";
  import { runner } from "./runner.svelte";
  import { layout } from "./layout.svelte";
  import { NUMBER_TAGS, PREFERRED_TAGS, STANDARD_TAGS, hasTag, orderTagKeys, renumber, tagValues } from "./tags";
  import { dirname, formatAudio, formatDuration, formatSize } from "./format";
  import { t } from "./i18n";

  let {
    files,
    base,
    siblings,
    onsaved,
  }: {
    files: FlacInfo[];
    base: string;
    siblings: (path: string) => string[];
    onsaved: (updated: FlacInfo[]) => void;
  } = $props();

  let autoOpen = $state(false);

  const CONFIRM_OVER = 20;

  type Row = {
    id: number;
    key: string;
    value: string;
    original: string | null;
    originalKey: string | null;
  };

  let rows = $state<Row[]>([]);
  let saving = $state(false);
  let progress = $state<{ rowId: number | null; done: number; total: number } | null>(null);

  async function applyInBatches(paths: string[], changes: TagChange[], rowId: number | null): Promise<FlacInfo[]> {
    const size = Math.min(8, Math.max(1, Math.ceil(paths.length / 50)));
    const batches: string[][] = [];
    for (let i = 0; i < paths.length; i += size) batches.push(paths.slice(i, i + size));
    progress = { rowId, done: 0, total: paths.length };
    const results: FlacInfo[][] = [];
    const errors: string[] = [];
    let next = 0;
    const worker = async () => {
      while (next < batches.length) {
        const i = next++;
        try {
          results[i] = await api.applyTagChanges(batches[i], changes);
        } catch (e) {
          errors.push(String(e));
        }
        if (progress) progress.done += batches[i].length;
      }
    };
    await Promise.all(Array.from({ length: Math.min(4, batches.length) }, worker));
    const done = results.flat();
    if (errors.length) {
      if (done.length) onsaved(done);
      throw new Error(errors.join("\n"));
    }
    return done;
  }
  let picture = $state<PictureInfo | null>(null);
  let nextId = 0;

  let single = $derived(files.length === 1 ? files[0] : null);
  let identity = $derived(
    files.map((f) => f.path + "\0" + f.tags.map((t) => t.join("=")).join("\0")).join("\n"),
  );
  let folderCount = $derived(new Set(files.map((f) => dirname(f.path))).size);

  $effect(() => {
    const _ = identity;
    untrack(reset);
  });

  $effect(() => {
    const path = single?.path;
    const hasPic = (single?.pictures ?? 0) > 0;
    picture = null;
    if (!path || !hasPic) return;
    api
      .readPicture(path)
      .then((p) => {
        if (single?.path === path) picture = p;
      })
      .catch(() => {});
  });

  function loadedRows(): Row[] {
    if (files.length === 1) {
      const f = files[0];
      return orderTagKeys(f.tags.map(([k]) => k)).flatMap((k) =>
        tagValues(f, k).map((v) => ({ id: nextId++, key: k, value: v, original: v, originalKey: k })),
      );
    }
    const keys = orderTagKeys(files.flatMap((f) => f.tags.map(([k]) => k)));
    return keys.map((k) => {
      const vals = files.map((f) => tagValues(f, k).join("; "));
      const same = vals.every((v) => v === vals[0]);
      const original = same ? vals[0] : null;
      return { id: nextId++, key: k, value: original ?? "", original, originalKey: k };
    });
  }

  let loadedPaths = "";
  function reset() {
    const paths = files.map((f) => f.path).join("\n");
    const keep = paths === loadedPaths;
    loadedPaths = paths;
    const fresh = loadedRows();
    if (keep) {
      const slot = (list: Row[]) => {
        const seen = new Map<string, number>();
        return list.map((r) => {
          const n = seen.get(r.originalKey!) ?? 0;
          seen.set(r.originalKey!, n + 1);
          return `${r.originalKey}#${n}`;
        });
      };
      const oldExisting = rows.filter((r) => r.originalKey !== null);
      const pending = new Map<string, Row>();
      slot(oldExisting).forEach((s, i) => rowChanged(oldExisting[i]) && pending.set(s, oldExisting[i]));
      slot(fresh).forEach((s, i) => {
        const p = pending.get(s);
        if (p) Object.assign(fresh[i], { key: p.key, value: p.value });
      });
      fresh.push(...rows.filter((r) => r.originalKey === null));
    }
    rows = fresh;
  }

  function rowChanged(r: Row): boolean {
    if (r.originalKey === null) return r.key.trim() !== "";
    if (r.key.trim().toUpperCase() !== r.originalKey) return true;
    if (r.original === null) return r.value !== "";
    return r.value !== r.original;
  }

  function revertRow(r: Row) {
    if (r.originalKey === null) rows = rows.filter((x) => x !== r);
    else {
      r.key = r.originalKey;
      r.value = r.original ?? "";
    }
  }

  function addRow(key = "") {
    rows.push({ id: nextId++, key, value: "", original: null, originalKey: null });
    const id = rows[rows.length - 1].id;
    requestAnimationFrame(() => {
      const sel = key ? `[data-row="${id}"] .value` : `[data-row="${id}"] .key`;
      document.querySelector<HTMLInputElement>(sel)?.focus();
    });
  }

  const quote = (v: string | null) => (v === null ? $t("(multiple values)") : `“${v}”`);

  async function confirmEdit(message: (scope: { count: number; folders: number }) => string): Promise<boolean> {
    if (files.length <= CONFIRM_OVER && folderCount <= 1) return true;
    return ask(message({ count: files.length, folders: folderCount }), {
      title: $t("Change tags"),
      kind: "warning",
      okLabel: $t("Change"),
      cancelLabel: $t("Cancel"),
    });
  }

  async function commit(r: Row, remove = false) {
    if (saving) return;
    const key = r.key.trim().toUpperCase();
    if (!remove && !rowChanged(r)) return;
    if (!remove && !key) return app.showError($t("Tag name can't be empty"));

    const renamed = r.originalKey !== null && key !== r.originalKey;
    const message = (scope: { count: number; folders: number }) =>
      remove
        ? $t(
            "Are you sure you want to remove {tag} {value} on {count, plural, one {# file} other {# files}}{folders, plural, one {} other { in # folders}}?",
            { values: { ...scope, tag: r.originalKey!, value: quote(r.original) } },
          )
        : r.originalKey === null
          ? $t(
              "Are you sure you want to set {tag} to {value} on {count, plural, one {# file} other {# files}}{folders, plural, one {} other { in # folders}}?",
              { values: { ...scope, tag: key, value: quote(r.value) } },
            )
          : renamed && r.value === (r.original ?? "")
            ? $t(
                "Are you sure you want to rename {tag} to {newTag} on {count, plural, one {# file} other {# files}}{folders, plural, one {} other { in # folders}}?",
                { values: { ...scope, tag: r.originalKey, newTag: key } },
              )
            : $t(
                "Are you sure you want to change {tag} from {old} to {value} on {count, plural, one {# file} other {# files}}{folders, plural, one {} other { in # folders}}?",
                { values: { ...scope, tag: r.originalKey, old: quote(r.original), value: quote(r.value) } },
              );
    if (!(await confirmEdit(message))) return;

    saving = true;
    try {
      if (single) {
        const tags: TagPair[] = [];
        for (const x of rows) {
          if (x === r) {
            if (!remove) tags.push([key, r.value]);
          } else if (x.originalKey !== null) {
            tags.push([x.originalKey, x.original ?? ""]);
          }
        }
        progress = { rowId: r.id, done: 0, total: 1 };
        onsaved([await api.saveTags(single.path, tags)]);
      } else {
        const changes: TagChange[] = [];
        if (r.originalKey && (remove || renamed)) changes.push({ key: r.originalKey, value: null });
        if (!remove) changes.push({ key, value: r.value });
        onsaved(await applyInBatches(files.map((f) => f.path), changes, r.id));
      }
      if (r.originalKey === null) rows = rows.filter((x) => x !== r);
      app.showInfo(
        single
          ? $t("Saved {tag} on {name}", { values: { tag: key || r.originalKey!, name: single.name } })
          : $t("Saved {tag} on {count, plural, one {# file} other {# files}}", {
              values: { tag: key || r.originalKey!, count: files.length },
            }),
      );
    } catch (e) {
      app.showError(e);
    } finally {
      saving = false;
      progress = null;
    }
  }

  function onKey(r: Row, e: KeyboardEvent, field: "key" | "value") {
    if (e.key === "Escape") {
      e.preventDefault();
      revertRow(r);
      (e.currentTarget as HTMLElement).blur();
    } else if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      if (field === "key" && r.originalKey === null) {
        document.querySelector<HTMLInputElement>(`[data-row="${r.id}"] .value`)?.focus();
      } else {
        commit(r);
      }
    }
  }

  let missing = $derived(
    STANDARD_TAGS.map((k) => ({ key: k, count: files.filter((f) => !hasTag(f, k)).length })).filter(
      (m) => m.count > 0,
    ),
  );

  async function renumberFiles(mode: "strip" | "pad") {
    let example = "";
    const plan = files
      .map((f) => ({
        path: f.path,
        changes: NUMBER_TAGS.flatMap((key): TagChange[] => {
          const vals = tagValues(f, key);
          if (vals.length !== 1) return [];
          const next = renumber(vals[0], mode);
          if (next === vals[0]) return [];
          example ||= `${key} “${vals[0]}” → “${next}”`;
          return [{ key, value: next }];
        }),
      }))
      .filter((p) => p.changes.length);
    if (!plan.length) {
      app.showInfo(mode === "strip" ? $t("No leading zeros to remove") : $t("Numbers are already two digits"));
      return;
    }
    const values = { count: plan.length, example };
    const ok = await ask(
      mode === "strip"
        ? $t(
            "Remove leading zeros from track and disc numbers on {count, plural, one {# file} other {# files}}?\n\nFor example: {example}",
            { values },
          )
        : $t("Pad track and disc numbers on {count, plural, one {# file} other {# files}}?\n\nFor example: {example}", {
            values,
          }),
      { title: $t("Track numbers"), kind: "info", okLabel: $t("Change"), cancelLabel: $t("Cancel") },
    );
    if (!ok) return;
    saving = true;
    progress = { rowId: null, done: 0, total: plan.length };
    const updated: FlacInfo[] = [];
    try {
      for (const p of plan) {
        updated.push(...(await api.applyTagChanges([p.path], p.changes)));
        if (progress) progress.done++;
      }
      app.showInfo($t("Updated numbers on {count, plural, one {# file} other {# files}}", { values: { count: plan.length } }));
    } catch (e) {
      app.showError(e);
    } finally {
      if (updated.length) onsaved(updated);
      saving = false;
      progress = null;
    }
  }

  function numbersMenu() {
    contextMenu([
      { text: $t("Remove leading zeros (01 → 1)"), action: () => renumberFiles("strip") },
      { text: $t("Pad to two digits (1 → 01)"), action: () => renumberFiles("pad") },
    ]);
  }

  function addMissing(key: string) {
    const r = rows.find((x) => x.key.trim().toUpperCase() === key);
    if (r) document.querySelector<HTMLInputElement>(`[data-row="${r.id}"] .value`)?.focus();
    else addRow(key);
  }
</script>

{#snippet bar(p: { done: number; total: number })}
  <div
    class="progress"
    role="progressbar"
    aria-valuemin={0}
    aria-valuemax={p.total}
    aria-valuenow={p.done}
    title={$t("Writing… {done} of {total}", { values: { done: p.done, total: p.total } })}
  >
    <div class="fill" style:width="{p.total ? (p.done / p.total) * 100 : 0}%"></div>
  </div>
{/snippet}

<aside class="editor" style:width="{layout.rightWidth}px">
  {#if files.length === 0}
    <div class="empty muted">
      <Tags size={28} strokeWidth={1.5} />
      <p>{$t("Select one or more FLAC files to edit their tags.")}</p>
      <p class="hint">{$t("⌘-click or ⇧-click to select several and edit them together.")}</p>
    </div>
  {:else}
    <div class="info">
      {#if single}
        <div class="art">
          {#if picture}
            <img src={picture.dataUrl} alt={$t("Cover")} />
          {:else}
            <div class="noart"><ImageOff size={22} strokeWidth={1.5} /></div>
          {/if}
        </div>
        <div class="meta">
          <div class="title" title={single.name}>{single.name}</div>
          <div class="muted">
            {formatAudio(single.sampleRate, single.bitsPerSample, single.channels)}
            · {formatDuration(single.duration)} · {formatSize(single.size)}
          </div>
          {#if picture}
            <div class="muted small">
              {picture.width}×{picture.height}{picture.width !== picture.height ? ` ${$t("(not square)")}` : ""} ·
              {formatSize(picture.bytes)}
            </div>
          {/if}
          {#if single.error}<div class="err small">{single.error}</div>{/if}
        </div>
      {:else}
        <div class="meta">
          <div class="title">{$t("{count, plural, one {# file selected} other {# files selected}}", { values: { count: files.length } })}</div>
          <div class="muted small">
            {folderCount > 1
              ? $t(
                  "Fields that differ show “Multiple values”. Only the field you press Enter in is written (files are in {count} folders).",
                  { values: { count: folderCount } },
                )
              : $t("Fields that differ show “Multiple values”. Only the field you press Enter in is written.")}
          </div>
        </div>
      {/if}
    </div>

    <fieldset class="lock" disabled={saving}>
    {#if progress && progress.rowId === null}
      {@render bar(progress)}
    {/if}
    <div class="rows">
      {#each rows as r (r.id)}
        {@const mixedKey = r.originalKey !== null && r.original === null && files.length > 1}
        <div class="row" class:changed={rowChanged(r)} data-row={r.id}>
          <input
            class="key"
            bind:value={r.key}
            list="tag-names"
            placeholder={$t("TAG")}
            spellcheck="false"
            readonly={mixedKey}
            title={mixedKey
              ? $t("Can't rename a tag whose values differ between files")
              : $t("Tag name — type a new one to rename it (Enter writes, Esc reverts)")}
            onkeydown={(e) => onKey(r, e, "key")}
          />
          {#if r.value.includes("\n")}
            <textarea
              class="value"
              rows="4"
              bind:value={r.value}
              title={$t("Tag value (Enter writes, Shift-Enter for a new line, Esc reverts)")}
              onkeydown={(e) => onKey(r, e, "value")}
            ></textarea>
          {:else}
            <input
              class="value"
              bind:value={r.value}
              placeholder={r.original === null && r.originalKey ? $t("Multiple values") : ""}
              spellcheck="false"
              title={$t("Tag value (Enter writes, Shift-Enter for a new line, Esc reverts)")}
              onkeydown={(e) => onKey(r, e, "value")}
            />
          {/if}
          {#if rowChanged(r)}
            <button class="icon-btn enter" title={$t("Write this tag to the file(s) (Enter)")} onclick={() => commit(r)}>
              <CornerDownLeft size={13} />
            </button>
          {:else}
            <button
              class="icon-btn"
              title={r.originalKey === null ? $t("Discard this new tag") : $t("Remove this tag from the file(s)")}
              onclick={() => (r.originalKey === null ? revertRow(r) : commit(r, true))}
            >
              <X size={13} />
            </button>
          {/if}
        </div>
        {#if progress && progress.rowId === r.id}
          {@render bar(progress)}
        {/if}
      {/each}

      <div class="add">
        <button class="btn" onclick={() => addRow()} title={$t("Add a new tag row")}><Plus size={13} /> {$t("Add tag")}</button>
      </div>
    </div>

    <div class="missing">
      <div class="missing-head">
        <span class="section-title">{$t("Missing")}</span>
        <span class="spacer"></span>
        <button
          class="btn"
          onclick={numbersMenu}
          disabled={saving || runner.busy}
          title={runner.busy ? $t("Wait for the running tool to finish") : $t("Change how track and disc numbers are written")}
        >
          <ListOrdered size={13} /> {$t("Numbers")}
        </button>
        <button
          class="btn"
          onclick={() => (autoOpen = true)}
          disabled={saving || runner.busy}
          title={runner.busy ? $t("Wait for the running tool to finish") : $t("Guess tags from file and folder names")}
        >
          <WandSparkles size={13} /> {$t("Auto-detect…")}
        </button>
      </div>
      {#if missing.length}
        <div class="chips">
          {#each missing as m (m.key)}
            <button
              class="chip"
              onclick={() => addMissing(m.key)}
              title={files.length > 1
                ? $t("Missing from {count} of {total} files — click to add {tag}", {
                    values: { count: m.count, total: files.length, tag: m.key },
                  })
                : $t("Add {tag}", { values: { tag: m.key } })}
            >
              + {m.key}{#if files.length > 1 && m.count < files.length}<span class="of">{m.count}/{files.length}</span>{/if}
            </button>
          {/each}
        </div>
      {:else}
        <p class="complete muted">{$t("All the standard tags are set.")}</p>
      {/if}
    </div>
    </fieldset>

    <div class="footer muted">
      {single
        ? $t("Enter writes the field to the file · Esc reverts · Shift-Enter for a new line")
        : $t("Enter writes the field to all {count} files · Esc reverts · Shift-Enter for a new line", {
            values: { count: files.length },
          })}
    </div>
  {/if}
</aside>

{#if autoOpen}
  <AutoTagDialog {files} root={app.root} {base} {siblings} {onsaved} onclose={() => (autoOpen = false)} />
{/if}

<datalist id="tag-names">
  {#each [...PREFERRED_TAGS, "COMMENT", "DESCRIPTION", "LABEL", "ISRC", "LYRICS", "PERFORMER", "CATALOGNUMBER", "MUSICBRAINZ_ALBUMID"] as k}
    <option value={k}></option>
  {/each}
</datalist>

<style>
  .editor {
    flex: none;
    display: flex;
    flex-direction: column;
    border-left: 1px solid var(--border);
    background: var(--bg-sidebar);
    min-height: 0;
  }
  .empty {
    margin: auto;
    padding: 24px;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
  }
  .empty p {
    margin: 6px 0 0;
    max-width: 240px;
  }
  .hint {
    font-size: 12px;
    color: var(--fg-faint);
  }
  .info {
    display: flex;
    gap: 12px;
    padding: 14px;
    border-bottom: 1px solid var(--border);
    flex: none;
  }
  .art {
    flex: none;
    width: 84px;
    height: 84px;
    border-radius: 6px;
    overflow: hidden;
    background: var(--bg-hover);
  }
  .art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .noart {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--fg-faint);
  }
  .meta {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .title {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    user-select: text;
    -webkit-user-select: text;
  }
  .small {
    font-size: 12px;
  }
  .err {
    color: var(--danger);
  }
  .lock {
    flex: 1;
    min-height: 0;
    min-width: 0;
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    border: 0;
  }
  .lock:disabled {
    cursor: progress;
  }
  .lock:disabled input,
  .lock:disabled textarea,
  .lock:disabled .chip {
    opacity: 0.55;
  }
  .progress {
    flex: none;
    height: 4px;
    margin: 2px 0 6px;
    border-radius: 2px;
    background: var(--overlay-2);
    overflow: hidden;
  }
  .lock > .progress {
    margin: 10px 10px 0 14px;
  }
  .fill {
    height: 100%;
    background: var(--accent);
    border-radius: 2px;
    transition: width 0.15s ease-out;
  }
  .rows {
    flex: 1;
    overflow: auto;
    padding: 10px 10px 14px 14px;
    display: flex;
    flex-direction: column;
    gap: 5px;
  }
  .row {
    display: grid;
    grid-template-columns: 124px 1fr 26px;
    gap: 5px;
    align-items: start;
  }
  .row input,
  .row textarea {
    min-width: 0;
    height: 30px;
  }
  .row textarea {
    height: auto;
    resize: vertical;
  }
  .key {
    font-family: var(--mono);
    font-size: 12px;
    text-transform: uppercase;
    color: var(--fg-muted);
  }
  .row.changed .value,
  .row.changed .key {
    border-color: var(--accent);
  }
  .add {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
    margin-top: 6px;
  }
  .chip {
    border: 1px dashed var(--border-strong);
    background: none;
    border-radius: 13px;
    height: 26px;
    padding: 0 9px;
    font-size: 12px;
    color: var(--fg-muted);
  }
  .spacer {
    flex: 1;
  }
  .missing {
    flex: none;
    border-top: 1px solid var(--border);
    padding: 10px 14px 12px;
    max-height: 40%;
    overflow: auto;
  }
  .missing-head {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 8px;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
  }
  .of {
    margin-left: 5px;
    color: var(--fg-faint);
    font-variant-numeric: tabular-nums;
  }
  .complete {
    margin: 0;
    font-size: 12px;
  }
  .chip:hover {
    color: var(--fg);
    border-style: solid;
  }
  .footer {
    padding: 8px 14px;
    border-top: 1px solid var(--border);
    font-size: 12px;
    flex: none;
  }
  .enter {
    color: var(--accent);
  }
</style>
