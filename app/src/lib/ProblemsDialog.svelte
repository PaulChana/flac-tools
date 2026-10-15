<script lang="ts">
  import {
    ShieldCheck,
    X,
    LoaderCircle,
    TriangleAlert,
    CircleAlert,
    Info,
    ChevronDown,
    ChevronRight,
    Wrench,
    RefreshCw,
    CircleCheck,
    Zap,
  } from "@lucide/svelte";
  import { listen } from "@tauri-apps/api/event";
  import { onMount } from "svelte";
  import { SvelteSet } from "svelte/reactivity";
  import { api, type DirContents, type FlacInfo } from "./api";
  import { app } from "./state.svelte";
  import { runner } from "./runner.svelte";
  import { basename, commonAncestor, relative } from "./format";
  import { t } from "./i18n";
  import {
    KINDS,
    SEVERITY_ORDER,
    coverProblems,
    fileProblems,
    trackProblems,
    type Problem,
    type ProblemKind,
  } from "./problems";

  let {
    folders,
    mode,
    onclose,
  }: {
    folders: string[];
    mode: "fast" | "full";
    onclose: () => void;
  } = $props();

  const FAST_SKIPS = new Set<ProblemKind>(["id3", "decode"]);

  let verify = $state(loadVerify());
  let phase = $state<"idle" | "scanning" | "done">("idle");
  let status = $state("");
  let problems = $state<Problem[]>([]);
  let fileCount = $state(0);
  let folderCount = $state(0);
  let fixing = $state<ProblemKind | null>(null);
  const open = new SvelteSet<ProblemKind>();

  let base = $derived(folders.length > 1 ? commonAncestor(folders) : folders[0]);

  function loadVerify() {
    try {
      return localStorage.getItem("checkVerify") === "1";
    } catch {
      return false;
    }
  }
  $effect(() => {
    try {
      localStorage.setItem("checkVerify", verify ? "1" : "0");
    } catch {
    }
  });

  let groups = $derived(
    (Object.keys(KINDS) as ProblemKind[])
      .map((kind) => ({ kind, info: KINDS[kind], items: problems.filter((p) => p.kind === kind) }))
      .filter((g) => g.items.length)
      .sort((a, b) => SEVERITY_ORDER.indexOf(a.info.severity) - SEVERITY_ORDER.indexOf(b.info.severity)),
  );

  async function scan(redecode?: Set<string>) {
    phase = "scanning";
    const again = !!redecode;
    problems = [];
    open.clear();
    try {
      status = again ? $t("Re-checking after fix — listing files…") : $t("listing files…");
      const parts = await Promise.all(folders.map((f) => api.dirContents(f, true)));
      const seen = new Set<string>();
      const flacs: string[] = [];
      const others: DirContents["others"] = [];
      for (const p of parts) {
        for (const f of p.flacs) if (!seen.has(f) && seen.add(f)) flacs.push(f);
        for (const o of p.others) if (!seen.has(o.path) && seen.add(o.path)) others.push(o);
      }

      const infos: FlacInfo[] = [];
      for (let i = 0; i < flacs.length; i += 200) {
        status = again
          ? $t("Re-checking after fix — reading tags… {done} of {total}", { values: { done: i, total: flacs.length } })
          : $t("reading tags… {done} of {total}", { values: { done: i, total: flacs.length } });
        infos.push(...(await api.readFlacs(flacs.slice(i, i + 200), mode === "full")));
      }
      fileCount = infos.length;
      folderCount = new Set(infos.map((f) => f.path.slice(0, f.path.lastIndexOf("/")))).size;

      const found: Problem[] = [
        ...infos.flatMap(fileProblems),
        ...trackProblems(infos),
        ...coverProblems(infos, others),
      ].filter((p) => mode === "full" || !FAST_SKIPS.has(p.kind));

      status = again ? $t("Re-checking after fix — checking playlists…") : $t("checking playlists…");
      const playlists = others.filter((o) => /\.m3u8?$/i.test(o.name)).map((o) => o.path);
      for (const pl of await api.checkPlaylists(playlists)) {
        if (pl.missing.length) {
          found.push({
            kind: "playlist",
            path: pl.playlist,
            dir: pl.playlist.slice(0, pl.playlist.lastIndexOf("/")),
            message: $t("{count} missing: {names}", {
              values: {
                count: pl.missing.length,
                names: pl.missing.slice(0, 3).join(", ") + (pl.missing.length > 3 ? "…" : ""),
              },
            }),
          });
        }
      }

      const toDecode = verify && mode === "full"
        ? infos.filter((f) => !f.error && (!redecode || redecode.has(f.path))).map((f) => f.path)
        : [];
      if (toDecode.length) {
        const decoding = (done: number, total: number) =>
          again
            ? $t("Re-checking after fix — decoding audio… {done} of {total}", { values: { done, total } })
            : $t("decoding audio… {done} of {total}", { values: { done, total } });
        status = decoding(0, toDecode.length);
        const un = await listen<{ done: number; total: number }>("verify-progress", (e) => {
          status = decoding(e.payload.done, e.payload.total);
        });
        try {
          for (const r of await api.verifyFlacs(toDecode)) {
            if (!r.ok) {
              found.push({
                kind: "decode",
                path: r.path,
                dir: r.path.slice(0, r.path.lastIndexOf("/")),
                message: r.message ?? $t("Decoder error"),
              });
            }
          }
        } finally {
          un();
        }
      }
      problems = found;
      for (const g of groups) if (g.info.severity !== "info") open.add(g.kind);
      phase = "done";
    } catch (e) {
      app.showError(e);
      phase = "idle";
    }
  }

  async function fix(kind: ProblemKind) {
    const f = KINDS[kind].fix;
    if (!f) return;
    const dirs = [...new Set(problems.filter((p) => p.kind === kind).map((p) => p.dir))];
    const failedDecode = new Set(problems.filter((p) => p.kind === "decode").map((p) => p.path));
    fixing = kind;
    try {
      await runner.runInline([{ tool: f.tool, args: f.args }], dirs, $t(f.label));
    } finally {
      fixing = null;
    }
    await scan(failedDecode);
  }

  function go(p: Problem) {
    if (p.path === p.dir) app.openFolder(p.dir);
    else if (/\.flac$/i.test(p.path)) app.openFile(p.path);
    else app.openFolder(p.dir);
    app.view = "library";
    onclose();
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape") onclose();
  }

  onMount(() => scan());

  const icon = { error: TriangleAlert, warning: CircleAlert, info: Info };
</script>

<svelte:window {onkeydown} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="backdrop" onclick={onclose}>
  <div class="dialog" role="dialog" aria-label={$t("Check for problems")} tabindex="-1" onclick={(e) => e.stopPropagation()}>
    <header>
      {#if mode === "fast"}<Zap size={16} />{:else}<ShieldCheck size={16} />{/if}
      <h2>{mode === "fast" ? $t("Fast check") : $t("Full check")}</h2>
      <span class="scope muted" title={folders.join("\n")}>
        {folders.length > 1
          ? $t("in {count} folders and subfolders", { values: { count: folders.length } })
          : $t("in {folder} and subfolders", { values: { folder: relative(folders[0], app.root) || folders[0] } })}
      </span>
      <span class="spacer"></span>
      <button class="icon-btn" onclick={onclose} title={$t("Close (Esc)")} aria-label={$t("Close")}><X size={15} /></button>
    </header>

    <div class="bar">
      {#if mode === "full"}
        <label class="check" title={$t("Runs flac -t on every file — finds damaged audio, but takes a while")}>
          <input type="checkbox" bind:checked={verify} disabled={phase === "scanning"} />
          {$t("Also decode the audio (slow)")}
        </label>
      {:else}
        <span class="muted">{$t("Skips ID3 tags and audio decoding.")}</span>
        <button
          class="link"
          title={$t("Check these folders again, including ID3 tags and audio decoding")}
          onclick={() => app.startCheck("full", folders)}>{$t("Run a full check")}</button
        >
      {/if}
      <span class="spacer"></span>
      {#if phase === "scanning"}
        <span class="status"><LoaderCircle size={14} class="spin" /> {status}</span>
      {:else}
        {#if phase === "done"}
          <span class="muted"
            >{$t(
              "{files, plural, one {# file} other {# files}} in {folders, plural, one {# folder} other {# folders}} · {problems, plural, one {# problem} other {# problems}}",
              { values: { files: fileCount, folders: folderCount, problems: problems.length } },
            )}</span
          >
        {/if}
        <button class="btn" title={$t("Scan the folders again")} onclick={() => scan()} disabled={runner.busy}
          ><RefreshCw size={13} /> {$t("Check again")}</button
        >
      {/if}
    </div>

    <div class="results">
      {#if phase === "done" && !problems.length}
        <div class="clean">
          <CircleCheck size={30} strokeWidth={1.5} />
          <p>{$t("No problems found.")}</p>
        </div>
      {/if}
      {#each groups as g (g.kind)}
        {@const Icon = icon[g.info.severity]}
        <section class={g.info.severity}>
          <div class="group-head">
            <button
              class="toggle"
              title={open.has(g.kind) ? $t("Hide these problems") : $t("Show these problems")}
              onclick={() => (open.has(g.kind) ? open.delete(g.kind) : open.add(g.kind))}
            >
              {#if open.has(g.kind)}<ChevronDown size={13} />{:else}<ChevronRight size={13} />{/if}
              <span class="sev"><Icon size={14} /></span>
              <span class="title">{$t(g.info.title)}</span>
              <span class="count">{g.items.length}</span>
            </button>
            {#if g.info.fix}
              <button
                class="btn"
                disabled={runner.busy || phase === "scanning"}
                onclick={() => fix(g.kind)}
                title={$t("{count, plural, one {Runs {tool} on the # affected folder} other {Runs {tool} on the # affected folders}}", { values: { tool: g.info.fix.tool, count: new Set(g.items.map((i) => i.dir)).size } })}
              >
                {#if fixing === g.kind}<LoaderCircle size={13} class="spin" />{:else}<Wrench size={13} />{/if}
                {$t(g.info.fix.label)}
              </button>
            {/if}
          </div>
          {#if open.has(g.kind)}
            <ul>
              {#each g.items as p (p.path + p.message)}
                <li>
                  <button class="item" onclick={() => go(p)} title={$t("Show {path}", { values: { path: p.path } })}>
                    <span class="where">{p.path === base ? $t("{name} (this folder)", { values: { name: basename(base) } }) : relative(p.path, base)}</span>
                    <span class="what">{p.message}</span>
                  </button>
                </li>
              {/each}
            </ul>
          {/if}
        </section>
      {/each}
    </div>
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
    width: min(920px, 100%);
    height: min(720px, 100%);
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
  .scope {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .spacer {
    flex: 1;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 18px;
    border-bottom: 1px solid var(--border);
    min-height: 48px;
  }
  .check {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .link {
    border: none;
    background: none;
    padding: 0;
    color: var(--accent);
  }
  .link:hover {
    text-decoration: underline;
  }
  .status {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--fg-muted);
  }
  .results {
    flex: 1;
    overflow: auto;
    padding: 8px 0 16px;
  }
  .clean {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    color: var(--success);
  }
  .clean p {
    margin: 8px 0 0;
    color: var(--fg);
  }
  section {
    padding: 2px 12px;
  }
  .group-head {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .toggle {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 7px;
    height: 34px;
    padding: 0 6px;
    border: none;
    border-radius: 6px;
    background: none;
    text-align: left;
  }
  .toggle:hover {
    background: var(--bg-hover);
  }
  .sev {
    display: inline-flex;
  }
  section.error .sev {
    color: var(--danger);
  }
  section.warning .sev {
    color: var(--warn);
  }
  section.info .sev {
    color: var(--fg-muted);
  }
  .title {
    font-weight: 600;
  }
  .count {
    min-width: 22px;
    padding: 0 7px;
    border-radius: 10px;
    background: var(--bg-hover);
    color: var(--fg-muted);
    font-size: 12px;
    text-align: center;
  }
  ul {
    list-style: none;
    margin: 0 0 6px;
    padding: 0 0 0 34px;
  }
  .item {
    display: flex;
    gap: 14px;
    width: 100%;
    padding: 4px 8px;
    border: none;
    border-radius: 5px;
    background: none;
    text-align: left;
  }
  .item:hover {
    background: var(--bg-hover);
  }
  .where {
    flex: 1 1 55%;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .what {
    flex: 1 1 45%;
    min-width: 0;
    color: var(--fg-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
