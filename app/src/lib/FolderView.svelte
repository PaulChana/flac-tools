<script lang="ts">
  import {
    ArrowDown,
    ArrowUp,
    ChevronDown,
    ChevronRight,
    TextCursorInput,
    File,
    Folder,
    FileAudio,
    LoaderCircle,
  } from "@lucide/svelte";
  import { SvelteMap, SvelteSet } from "svelte/reactivity";
  import { untrack } from "svelte";
  import { api, type DirContents, type FlacInfo, type FileSummary } from "./api";
  import { app } from "./state.svelte";
  import { contextMenu } from "./menu.svelte";
  import { ancestors, basename, commonAncestor, dirname, formatDate, formatSize, relative, reparent } from "./format";
  import FlacTable from "./FlacTable.svelte";
  import TagEditor from "./TagEditor.svelte";
  import RenameField from "./RenameField.svelte";
  import RenameDialog from "./RenameDialog.svelte";
  import ImageViewer from "./ImageViewer.svelte";
  import { ask } from "@tauri-apps/plugin-dialog";
  import { runner } from "./runner.svelte";
  import { compareText } from "./tags";
  import { layout, startDrag } from "./layout.svelte";
  import { t } from "./i18n";

  let contents = $state.raw<DirContents | null>(null);
  let files = $state.raw<FlacInfo[]>([]);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let showOthers = $state(false);
  let showDirs = $state(loadShowDirs());

  function loadShowDirs() {
    try {
      return localStorage.getItem("showDirs") !== "0";
    } catch {
      return true;
    }
  }
  function toggleDirs() {
    showDirs = !showDirs;
    try {
      localStorage.setItem("showDirs", showDirs ? "1" : "0");
    } catch {
    }
  }
  const IMAGE_EXT = /\.(jpe?g|png|gif|webp|bmp)$/i;
  type Sort = { by: string; desc: boolean };
  let dirSort = $state<Sort>({ by: "name", desc: false });
  let otherSort = $state<Sort>({ by: "name", desc: false });

  function sortBy(s: Sort, by: string) {
    if (s.by === by) s.desc = !s.desc;
    else {
      s.by = by;
      s.desc = false;
    }
  }

  function sorted<T extends { path: string }>(
    rows: T[],
    s: Sort,
    keys: Record<string, (r: T) => string | number | null>,
  ): T[] {
    const key = keys[s.by];
    return [...rows].sort((a, b) => {
      const av = key(a);
      const bv = key(b);
      if ((av === null) !== (bv === null)) return av === null ? 1 : -1;
      const c = typeof av === "number" && typeof bv === "number" ? av - bv : compareText(String(av), String(bv));
      return (s.desc ? -c : c) || compareText(a.path, b.path);
    });
  }

  let dirs = $derived(
    sorted(contents?.dirs ?? [], dirSort, {
      name: (d) => d.name,
      flacs: (d) => d.flacs,
      subdirs: (d) => d.subdirs,
      others: (d) => d.others,
      modified: (d) => d.modified,
    }),
  );
  let others = $derived(
    sorted(contents?.others ?? [], otherSort, {
      name: (o) => relative(o.path, base),
      dims: (o) => (o.width && o.height ? o.width * o.height : null),
      size: (o) => o.size,
      modified: (o) => o.modified,
    }),
  );

  let images = $derived(others.filter((o) => IMAGE_EXT.test(o.name)));
  let viewing = $state<number | null>(null);

  function openOther(o: FileSummary) {
    const i = images.findIndex((x) => x.path === o.path);
    if (i >= 0) viewing = i;
    else app.renaming = o.path;
  }

  let renameFiles = $state<FlacInfo[] | null>(null);

  function openRenameDialog() {
    renameFiles = selected.size ? files.filter((f) => selected.has(f.path)) : files;
  }

  const selected = new SvelteSet<string>();
  const thumbs = new SvelteMap<string, string | null>();
  let anchor: string | null = null;
  let table = $state<FlacTable>();
  let filesPane = $state<HTMLDivElement>();

  let selectedFiles = $derived(files.filter((f) => selected.has(f.path)));
  let multi = $derived(app.folders.length > 1);
  let base = $derived(multi ? commonAncestor(app.folders) : app.current);
  let crumbs = $derived(ancestors(base, app.root));

  let loadToken = 0;
  $effect(() => {
    const paths = app.folders;
    const recursive = app.recursive;
    const _ = app.contentVersion;
    if (!paths.length) return;
    untrack(() => load(paths, recursive));
  });

  function merge(parts: DirContents[]): DirContents {
    const seen = new Set<string>();
    const fresh = (p: string) => !seen.has(p) && !!seen.add(p);
    return {
      dirs: parts.flatMap((c) => c.dirs).filter((d) => fresh(d.path)),
      flacs: parts.flatMap((c) => c.flacs).filter(fresh),
      others: parts.flatMap((c) => c.others).filter((o) => fresh(o.path)),
    };
  }

  async function load(paths: string[], recursive: boolean) {
    const token = ++loadToken;
    const path = paths[0];
    loading = true;
    error = null;
    try {
      const results = await Promise.allSettled(paths.map((p) => api.dirContents(p, recursive)));
      if (token !== loadToken) return;
      const ok = results.flatMap((r) => (r.status === "fulfilled" ? [r.value] : []));
      if (!ok.length) throw (results[0] as PromiseRejectedResult).reason;
      const gone = paths.filter((_, i) => results[i].status === "rejected");
      if (gone.length) app.folders = app.folders.filter((p) => !gone.includes(p));
      const c = merge(ok);
      contents = c;
      const infos = await api.readFlacs(c.flacs);
      if (token !== loadToken) return;
      files = infos;
      syncSelection();
      loadThumbs(token, infos);
    } catch (e) {
      if (token !== loadToken) return;
      if (!multi && String(e).includes("os error 2") && path !== app.root && path.startsWith(app.root + "/")) {
        app.openFolder(dirname(path));
        return;
      }
      error = String(e);
      contents = null;
      files = [];
      selected.clear();
    } finally {
      if (token === loadToken) loading = false;
    }
  }

  async function loadThumbs(token: number, infos: FlacInfo[]) {
    const present = new Set(infos.map((f) => f.path));
    for (const p of [...thumbs.keys()]) if (!present.has(p)) thumbs.delete(p);
    const withArt = infos.filter((f) => f.pictures > 0).map((f) => f.path);
    for (let i = 0; i < withArt.length; i += 32) {
      const batch = withArt.slice(i, i + 32);
      try {
        const urls = await api.readThumbnails(batch, 64);
        if (token !== loadToken) return;
        batch.forEach((p, j) => thumbs.set(p, urls[j]));
      } catch {
        return;
      }
    }
  }

  function syncSelection() {
    const exists = new Set(files.map((f) => f.path));
    const renames = app.pendingRenames.splice(0);
    const next = [...selected]
      .map((p) => renames.reduce((acc, r) => reparent(acc, r.from, r.to), p))
      .filter((p) => exists.has(p));
    selected.clear();
    if (app.focusFile && exists.has(app.focusFile)) {
      selected.add(app.focusFile);
      anchor = app.focusFile;
      const target = app.focusFile;
      requestAnimationFrame(() => table?.scrollToPath(target));
    } else {
      for (const p of next) selected.add(p);
    }
  }

  $effect(() => {
    const f = app.focusFile;
    if (f && files.some((x) => x.path === f) && !(selected.size === 1 && selected.has(f))) {
      untrack(syncSelection);
    }
  });

  function select(path: string, e: MouseEvent | KeyboardEvent) {
    const order = table?.order() ?? [];
    let next: string[];
    if (e.shiftKey && anchor && order.includes(anchor)) {
      const a = order.indexOf(anchor);
      const b = order.indexOf(path);
      next = order.slice(Math.min(a, b), Math.max(a, b) + 1);
    } else if (e.metaKey) {
      next = selected.has(path) ? [...selected].filter((p) => p !== path) : [...selected, path];
      anchor = path;
    } else {
      if (selected.size === 1 && selected.has(path)) return;
      next = [path];
      anchor = path;
    }
    selected.clear();
    for (const p of next) selected.add(p);
    if (app.showFilesInTree) app.treeSelection = path;
    app.focusFile = null;
  }

  function selectAll() {
    for (const f of files) selected.add(f.path);
  }

  function onFilesKey(e: KeyboardEvent) {
    if (app.renaming) return;
    const order = table?.order() ?? [];
    if (e.key === "a" && e.metaKey) {
      e.preventDefault();
      selectAll();
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const cur = anchor ? order.indexOf(anchor) : -1;
      const i = Math.max(0, Math.min(order.length - 1, cur + (e.key === "ArrowDown" ? 1 : -1)));
      if (order[i]) {
        select(order[i], e);
        table?.scrollToPath(order[i]);
      }
    } else if (e.key === "Enter" && selected.size === 1) {
      e.preventDefault();
      app.renaming = [...selected][0];
    }
  }

  function siblingNames(path: string): string[] {
    const dir = dirname(path);
    return files.filter((f) => dirname(f.path) === dir).map((f) => f.name);
  }

  function onSaved(updated: FlacInfo[]) {
    const byPath = new Map(updated.map((f) => [f.path, f]));
    files = files.map((f) => byPath.get(f.path) ?? f);
  }

  function itemMenu(path: string, isDir: boolean, e: MouseEvent) {
    e.preventDefault();
    contextMenu([
      ...(isDir ? [{ text: $t("Open"), action: () => app.openFolder(path) }] : []),
      { text: $t("Rename"), action: () => (app.renaming = path) },
      ...(!isDir && selected.has(path) ? [{ text: renameWithOptions(), action: openRenameDialog }] : []),
      { text: $t("Reveal in Finder"), action: () => api.revealInFinder(path) },
    ]);
  }

  function renameWithOptions() {
    return selected.size > 1
      ? $t("Rename {count} files with options…", { values: { count: selected.size } })
      : $t("Rename with options…");
  }

  function otherMenu(o: FileSummary, e: MouseEvent) {
    e.preventDefault();
    const i = images.findIndex((x) => x.path === o.path);
    contextMenu([
      ...(i >= 0 ? [{ text: $t("View"), action: () => (viewing = i) }, "separator" as const] : []),
      { text: $t("Rename"), action: () => (app.renaming = o.path) },
      { text: $t("Reveal in Finder"), action: () => api.revealInFinder(o.path) },
    ]);
  }

  async function extractCover(f: FlacInfo) {
    const dir = dirname(f.path);
    const exists = contents?.others.some((o) => o.path.toLowerCase() === `${dir}/cover.jpg`.toLowerCase());
    if (exists && !(await ask($t("There's already a cover.jpg in “{folder}”. Replace it?", { values: { folder: basename(dir) } }), {
      title: $t("Save cover art"),
      kind: "warning",
      okLabel: $t("Replace"),
    }))) {
      return;
    }
    if (!runner.tool("flac-extract-cover")) {
      app.showError($t("The flac-extract-cover tool isn't in the scripts folder."));
      return;
    }
    await runner.runInline(
      [{ tool: "flac-extract-cover", args: [f.path, ...(exists ? ["--force"] : [])] }],
      [dir],
      $t("Save cover art from {file}", { values: { file: f.name } }),
    );
  }

  function fileMenu(f: FlacInfo, e: MouseEvent) {
    e.preventDefault();
    if (!selected.has(f.path)) select(f.path, e);
    contextMenu([
      { text: $t("Rename"), action: () => (app.renaming = f.path) },
      ...(selected.size > 1 || selected.has(f.path) ? [{ text: renameWithOptions(), action: openRenameDialog }] : []),
      "separator",
      {
        text: f.pictures ? $t("Save cover art as cover.jpg") : $t("Save cover art as cover.jpg (no embedded art)"),
        enabled: f.pictures > 0 && !runner.busy,
        action: () => extractCover(f),
      },
      "separator",
      { text: $t("Reveal in Finder"), action: () => api.revealInFinder(f.path) },
    ]);
  }
</script>

<div class="folder-view">
  <div class="main">
    <div class="bar">
      <nav class="crumbs">
        {#each crumbs as c, i (c)}
          {#if i > 0}<ChevronRight size={12} class="sep" />{/if}
          <button
            class="crumb"
            class:last={i === crumbs.length - 1}
            onclick={() => app.openFolder(c)}
            title={$t("Open {folder}", { values: { folder: basename(c) } })}
          >
            {basename(c)}
          </button>
        {/each}
        {#if multi}
          <span class="multi" title={app.folders.map((f) => relative(f, base)).join("\n")}>
            {$t("{count, plural, one {# folder} other {# folders}}", { values: { count: app.folders.length } })}
          </span>
        {/if}
      </nav>
      {#if loading}<LoaderCircle size={14} class="spin" />{/if}
      <span class="spacer"></span>
      <label class="check" title={$t("Include FLAC files in all subfolders")}>
        <input type="checkbox" checked={app.recursive} onchange={(e) => app.setRecursive(e.currentTarget.checked)} />
        {$t("Include subfolders")}
      </label>
    </div>

    {#if error}
      <div class="error">{error}</div>
    {:else if contents}
      {#if contents.dirs.length}
        <section class="dirs" class:open={showDirs}>
          <button
            class="section-title head toggle"
            onclick={toggleDirs}
            title={showDirs ? $t("Hide the subfolders") : $t("Show the subfolders")}
          >
            {#if showDirs}<ChevronDown size={12} />{:else}<ChevronRight size={12} />{/if}
            {$t("Folders")} <span class="count">{contents.dirs.length}</span>
          </button>
          {#if showDirs}
            <div class="scroll">
              <table class="grid">
                <thead>
                  <tr>
                    {@render sortHeader(dirSort, "name", $t("Name"))}
                    {@render sortHeader(dirSort, "flacs", "FLAC", true)}
                    {@render sortHeader(dirSort, "subdirs", $t("Folders"), true)}
                    {@render sortHeader(dirSort, "others", $t("Other"), true)}
                    {@render sortHeader(dirSort, "modified", $t("Modified"))}
                  </tr>
                </thead>
                <tbody>
                  {#each dirs as d (d.path)}
                    <tr
                      onclick={() => app.openFolder(d.path)}
                      oncontextmenu={(e) => itemMenu(d.path, true, e)}
                      title={$t("Open this folder")}
                    >
                      <td class="dir-name">
                        <div class="name-cell">
                          <Folder size={13} class="folder-icon" />
                          {#if app.renaming === d.path}
                            <RenameField path={d.path} name={d.name} isDir />
                          {:else}
                            <span class="label">{d.name}</span>
                          {/if}
                        </div>
                      </td>
                      <td class="num">{d.flacs || ""}</td>
                      <td class="num">{d.subdirs || ""}</td>
                      <td class="num">{d.others || ""}</td>
                      <td class="muted">{formatDate(d.modified)}</td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {/if}
        </section>
      {/if}

      <section class="files">
        <div class="section-title head">
          <FileAudio size={12} /> {$t("FLAC files")} <span class="count">{files.length}</span>
          {#if selected.size > 1}<span class="sel">{$t("{count} selected", { values: { count: selected.size } })}</span>{/if}
          <span class="head-spacer"></span>
          <button
            class="head-btn"
            disabled={!files.length}
            onclick={openRenameDialog}
            title={selected.size ? $t("Rename the selected files") : $t("Rename all files shown")}
          >
            <TextCursorInput size={13} />
            {selected.size ? $t("Rename {count}…", { values: { count: selected.size } }) : $t("Rename all…")}
          </button>
        </div>
        <div class="scroll" bind:this={filesPane} tabindex="0" role="grid" onkeydown={onFilesKey}>
          {#if files.length}
            <FlacTable bind:this={table} {files} {selected} {thumbs} {base} onselect={select} oncontext={fileMenu} />
          {:else if !loading}
            <p class="placeholder muted">
              {app.recursive ? $t("No FLAC files here.") : $t("No FLAC files here — try “Include subfolders”.")}
            </p>
          {/if}
        </div>
      </section>

      {#if contents.others.length}
        <section class="others" class:open={showOthers}>
          <button
            class="section-title head toggle"
            onclick={() => (showOthers = !showOthers)}
            title={showOthers ? $t("Hide the other files") : $t("Show the other (non-FLAC) files")}
          >
            {#if showOthers}<ChevronDown size={12} />{:else}<ChevronRight size={12} />{/if}
            {$t("Other files")} <span class="count">{contents.others.length}</span>
          </button>
          {#if showOthers}
            <div class="scroll">
              <table class="grid">
                <thead>
                  <tr>
                    {@render sortHeader(otherSort, "name", $t("Name"))}
                    {@render sortHeader(otherSort, "dims", $t("Dimensions"), true)}
                    {@render sortHeader(otherSort, "size", $t("Size"), true)}
                    {@render sortHeader(otherSort, "modified", $t("Modified"))}
                  </tr>
                </thead>
                <tbody>
                  {#each others as o (o.path)}
                    {@render otherRow(o)}
                  {/each}
                </tbody>
              </table>
            </div>
          {/if}
        </section>
      {/if}
    {/if}
  </div>

  <div class="right" style:width="{layout.showRight ? layout.rightWidth : 0}px" inert={!layout.showRight}>
    {#if layout.showRight}
      <div class="splitter" role="separator" aria-orientation="vertical" title={$t("Drag to resize the tag editor")} onpointerdown={(e) => startDrag(e, "rightWidth", -1)}></div>
    {/if}
    <TagEditor files={selectedFiles} {base} siblings={siblingNames} onsaved={onSaved} />
  </div>
</div>

{#if viewing !== null && images[viewing]}
  <ImageViewer {images} start={viewing} onclose={() => (viewing = null)} />
{/if}

{#if renameFiles}
  <RenameDialog
    files={renameFiles}
    existing={[...files.map((f) => f.path), ...(contents?.others.map((o) => o.path) ?? [])]}
    {base}
    onclose={() => (renameFiles = null)}
  />
{/if}

{#snippet sortHeader(s: Sort, by: string, label: string, num = false)}
  <th class="sortable" class:num onclick={() => sortBy(s, by)} title={$t("Sort by {column}", { values: { column: label } })}>
    <span class="th">
      {label}
      {#if s.by === by}
        {#if s.desc}<ArrowDown size={11} />{:else}<ArrowUp size={11} />{/if}
      {/if}
    </span>
  </th>
{/snippet}

{#snippet otherRow(o: FileSummary)}
  <tr
    class:image={IMAGE_EXT.test(o.name)}
    oncontextmenu={(e) => otherMenu(o, e)}
    ondblclick={() => openOther(o)}
    title={IMAGE_EXT.test(o.name) ? $t("Double-click to view") : $t("Double-click to rename")}
  >
    <td class="dir-name" title={o.path}>
      <div class="name-cell">
        <File size={13} class="cell-icon" />
        {#if app.renaming === o.path}
          <RenameField path={o.path} name={o.name} isDir={false} />
        {:else}
          <span class="label">{relative(o.path, base)}</span>
        {/if}
      </div>
    </td>
    <td class="num dims" class:notsquare={o.width !== null && o.width !== o.height}>
      {o.width && o.height ? `${o.width} × ${o.height}` : ""}
    </td>
    <td class="num">{formatSize(o.size)}</td>
    <td class="muted">{formatDate(o.modified)}</td>
  </tr>
{/snippet}

<style>
  .folder-view {
    display: flex;
    height: 100%;
    min-width: 0;
  }
  .main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
    padding: 0 var(--pane-pad) 0 calc(var(--pane-pad) - 4px);
    border-bottom: 1px solid var(--border);
    flex: none;
  }
  .crumbs {
    display: flex;
    align-items: center;
    gap: 2px;
    min-width: 0;
    overflow: hidden;
    color: var(--fg-muted);
  }
  .crumbs :global(.sep) {
    flex: none;
    opacity: 0.6;
  }
  .crumb {
    border: none;
    background: none;
    padding: 2px 4px;
    border-radius: 4px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: inherit;
  }
  .multi {
    margin-left: 6px;
    padding: 1px 8px;
    border-radius: 10px;
    background: var(--bg-selected-muted);
    color: var(--fg);
    font-size: 12px;
    white-space: nowrap;
  }
  .crumb:hover {
    background: var(--bg-hover);
    color: var(--fg);
  }
  .crumb.last {
    color: var(--fg);
    font-weight: 600;
  }
  .spacer {
    flex: 1;
  }
  .check {
    display: flex;
    align-items: center;
    gap: 5px;
    white-space: nowrap;
    color: var(--fg-muted);
  }
  :global(.spin) {
    animation: spin 0.9s linear infinite;
    color: var(--fg-muted);
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  section {
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-bottom: 1px solid var(--border);
  }
  section.dirs {
    flex: none;
  }
  section.dirs.open {
    flex: 0 1 auto;
    max-height: 32%;
  }
  section.files {
    flex: 1 1 0;
    min-height: 140px;
  }
  section.others {
    flex: none;
  }
  section.others.open {
    max-height: 28%;
    flex: 0 1 auto;
  }
  .head {
    padding: 8px var(--pane-pad) 4px;
    flex: none;
  }
  .toggle {
    border: none;
    background: none;
    text-align: left;
    width: 100%;
    padding-bottom: 8px;
  }
  .head-spacer {
    flex: 1;
  }
  .head-btn {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    height: 24px;
    padding: 0 9px;
    border: 1px solid var(--border-strong);
    border-radius: var(--radius);
    background: var(--bg-input);
    color: var(--fg);
    font-size: 12px;
    font-weight: 500;
    text-transform: none;
    letter-spacing: 0;
  }
  .head-btn:hover:not(:disabled) {
    background: var(--bg-hover);
  }
  .head-btn:disabled {
    opacity: 0.45;
  }
  .count {
    font-weight: 500;
    color: var(--fg-faint);
  }
  .sel {
    margin-left: 6px;
    text-transform: none;
    letter-spacing: 0;
    color: var(--accent);
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow: auto;
    outline: none;
  }
  .dirs tbody tr {
    cursor: default;
  }
  td.dir-name {
    width: 100%;
    max-width: 0;
  }
  .name-cell {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  .name-cell .label {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  td.dir-name :global(.folder-icon) {
    color: var(--folder);
    flex: none;
  }
  td.dir-name :global(.cell-icon) {
    color: var(--fg-muted);
    flex: none;
  }
  td.dims {
    color: var(--fg-muted);
  }
  td.dims.notsquare {
    color: var(--warn);
  }
  .th {
    display: inline-flex;
    align-items: center;
    gap: 3px;
  }
  th.num .th {
    justify-content: flex-end;
  }
  .right {
    flex: none;
    position: relative;
    display: flex;
    justify-content: flex-start;
    overflow: hidden;
    transition: width 0.25s cubic-bezier(0.45, 0.05, 0.55, 0.95);
  }
  :global(body.col-resizing) .right {
    transition: none;
  }
  .splitter {
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    width: 0;
    z-index: 2;
  }
  .splitter::after {
    content: "";
    position: absolute;
    inset: 0 -3px;
    cursor: col-resize;
  }
  .placeholder {
    padding: 16px 12px;
    margin: 0;
  }
  .error {
    margin: 16px;
    padding: 10px 12px;
    border-radius: var(--radius);
    background: var(--warn-bg);
    color: var(--warn);
  }
</style>
