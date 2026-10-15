<script lang="ts">
  import { ArrowDown, ArrowUp, Image, TriangleAlert, CircleAlert, Info } from "@lucide/svelte";
  import { KINDS, fileProblems, worstSeverity } from "./problems";
  import type { FlacInfo } from "./api";
  import { app } from "./state.svelte";
  import RenameField from "./RenameField.svelte";
  import { NUMBERING_TAGS, compareText, orderTagKeys, tagValue, yearMismatch } from "./tags";
  import { formatAudio, formatDuration, formatSize, relative } from "./format";
  import { t } from "./i18n";

  let {
    files,
    selected,
    thumbs,
    base,
    onselect,
    oncontext,
  }: {
    files: FlacInfo[];
    selected: Set<string>;
    thumbs: Map<string, string | null>;
    base: string;
    onselect: (path: string, e: MouseEvent | KeyboardEvent) => void;
    oncontext: (f: FlacInfo, e: MouseEvent) => void;
  } = $props();

  type Column = {
    id: string;
    label: string;
    get: (f: FlacInfo) => string;
    sortValue?: (f: FlacInfo) => number;
    num?: boolean;
    center?: boolean;
  };

  let tagKeys = $derived(orderTagKeys(files.flatMap((f) => f.tags.map(([k]) => k))));

  let columns = $derived<Column[]>([
    ...tagKeys.map((k) => ({
      id: k,
      label: k,
      get: (f: FlacInfo) => tagValue(f, k),
      center: NUMBERING_TAGS.has(k),
    })),
    {
      id: "@length",
      label: $t("Length"),
      get: (f) => formatDuration(f.duration),
      sortValue: (f) => f.duration,
      num: true,
    },
    {
      id: "@format",
      label: $t("Format"),
      get: (f) => formatAudio(f.sampleRate, f.bitsPerSample, f.channels),
      sortValue: (f) => f.sampleRate * 100 + f.bitsPerSample,
    },
    { id: "@size", label: $t("Size"), get: (f) => formatSize(f.size), sortValue: (f) => f.size, num: true },
  ]);

  let problems = $derived(new Map(files.map((f) => [f.path, fileProblems(f)])));
  const rank = { error: 3, warning: 2, info: 1 } as const;
  const problemScore = (f: FlacInfo) => {
    const ps = problems.get(f.path) ?? [];
    const worst = worstSeverity(ps);
    return worst ? rank[worst] * 100 + ps.length : 0;
  };

  let sortBy = $state("@name");
  let sortDesc = $state(false);

  let rows = $derived.by(() => {
    const col = columns.find((c) => c.id === sortBy);
    const key = (f: FlacInfo): number | string =>
      sortBy === "@problems" ? problemScore(f) : !col ? f.path : col.sortValue ? col.sortValue(f) : col.get(f);
    const keyed = files.map((f) => ({ f, k: key(f) }));
    keyed.sort((a, b) => {
      let r: number;
      if (typeof a.k === "number" && typeof b.k === "number") r = a.k - b.k;
      else {
        const av = String(a.k);
        const bv = String(b.k);
        if (!av !== !bv) return av ? -1 : 1;
        r = compareText(av, bv);
      }
      return (sortDesc ? -r : r) || compareText(a.f.path, b.f.path);
    });
    return keyed.map((x) => x.f);
  });

  export function order(): string[] {
    return rows.map((r) => r.path);
  }

  let widths = $state<Record<string, number>>(loadWidths());
  let resizing = false;

  function loadWidths() {
    try {
      return JSON.parse(localStorage.getItem("columnWidths") ?? "{}");
    } catch {
      return {};
    }
  }
  function saveWidths() {
    try {
      localStorage.setItem("columnWidths", JSON.stringify(widths));
    } catch {
    }
  }

  let tableEl = $state<HTMLTableElement>();
  let scrollTop = $state(0);
  let viewHeight = $state(800);
  let rowHeight = $state(30);
  let headHeight = $state(30);
  const OVERSCAN = 10;

  $effect(() => {
    const pane = tableEl?.parentElement;
    if (!pane) return;
    const onScroll = () => (scrollTop = pane.scrollTop);
    const resized = new ResizeObserver(() => (viewHeight = pane.clientHeight));
    pane.addEventListener("scroll", onScroll, { passive: true });
    resized.observe(pane);
    onScroll();
    return () => {
      pane.removeEventListener("scroll", onScroll);
      resized.disconnect();
    };
  });

  let start = $derived.by(() => {
    let s = Math.max(0, Math.floor((scrollTop - headHeight) / rowHeight) - OVERSCAN);
    if (s > 0 && s % 2 === 0) s -= 1;
    return s;
  });
  let end = $derived(Math.min(rows.length, start + Math.ceil(viewHeight / rowHeight) + 2 * OVERSCAN + 1));
  let visible = $derived(rows.slice(start, end));

  $effect(() => {
    void visible;
    const tr = tableEl?.querySelector("tbody tr[data-path]");
    const h = tr?.getBoundingClientRect().height;
    if (h) rowHeight = h;
    const head = tableEl?.tHead?.getBoundingClientRect().height;
    if (head) headHeight = head;
  });

  export function scrollToPath(path: string) {
    const pane = tableEl?.parentElement;
    const i = rows.findIndex((r) => r.path === path);
    if (!pane || i < 0) return;
    const top = headHeight + i * rowHeight;
    if (top < pane.scrollTop + headHeight) pane.scrollTop = top - headHeight;
    else if (top + rowHeight > pane.scrollTop + pane.clientHeight) pane.scrollTop = top + rowHeight - pane.clientHeight;
  }

  let fitted = $derived.by(() => {
    if (!tableEl) return {} as Record<string, number>;
    const style = getComputedStyle(tableEl);
    const ctx = document.createElement("canvas").getContext("2d")!;
    const measure = (text: string, weight = "400") => {
      ctx.font = `${weight} ${style.fontSize} ${style.fontFamily}`;
      return ctx.measureText(text).width;
    };
    const fit = (label: string, values: string[], max: number) => {
      const longest = values.reduce<string[]>((top, v) => {
        if (top.length < 3 || v.length > top[2].length) top = [...top, v].sort((a, b) => b.length - a.length).slice(0, 3);
        return top;
      }, []);
      const w = Math.max(measure(label, "500") + 16, ...longest.map((v) => measure(v))) + 22;
      return Math.round(Math.min(max, Math.max(48, w)));
    };
    const out: Record<string, number> = {
      "@name": fit($t("File"), files.map((f) => relative(f.path, base)), 380),
    };
    for (const c of columns) out[c.id] = fit(c.label, files.map(c.get), 320);
    return out;
  });
  const colWidth = (id: string) => widths[id] ?? fitted[id] ?? 120;

  function startResize(e: PointerEvent, id: string) {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    const th = (e.currentTarget as HTMLElement).closest("th")!;
    const startX = e.clientX;
    const startW = th.getBoundingClientRect().width;
    resizing = true;
    document.body.classList.add("col-resizing");
    const move = (ev: PointerEvent) => {
      widths[id] = Math.round(Math.max(40, startW + ev.clientX - startX));
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      document.body.classList.remove("col-resizing");
      saveWidths();
      setTimeout(() => (resizing = false));
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  function autoWidth(e: MouseEvent, id: string) {
    e.stopPropagation();
    delete widths[id];
    saveWidths();
  }

  function sort(id: string) {
    if (resizing) return;
    if (sortBy === id) sortDesc = !sortDesc;
    else {
      sortBy = id;
      sortDesc = false;
    }
  }
</script>

{#snippet header(id: string, label: string, num = false, center = false)}
  <th
    class="sortable"
    class:num
    class:center
    onclick={() => sort(id)}
    title={$t("Sort by {column}", { values: { column: label } })}
  >
    <span class="th">
      {label}
      {#if sortBy === id}
        {#if sortDesc}<ArrowDown size={11} />{:else}<ArrowUp size={11} />{/if}
      {/if}
    </span>
    <!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
    <span
      class="grip"
      title={$t("Drag to resize · double-click to fit")}
      onpointerdown={(e) => startResize(e, id)}
      onclick={(e) => e.stopPropagation()}
      ondblclick={(e) => autoWidth(e, id)}
    ></span>
  </th>
{/snippet}

<table class="grid virtual" bind:this={tableEl}>
  <colgroup>
    <col style="width: {colWidth('@name')}px" />
    <col class="art-col" />
    <col class="art-col" />
    {#each columns as c (c.id)}
      <col style="width: {colWidth(c.id)}px" />
    {/each}
    <col />
  </colgroup>
  <thead>
    <tr>
      {@render header("@name", $t("File"))}
      <th class="art" title={$t("Embedded pictures")}><Image size={12} /></th>
      <th class="art sortable" title={$t("Problems — click to sort")} onclick={() => sort("@problems")}>
        <TriangleAlert size={12} />
      </th>
      {#each columns as c (c.id)}
        {@render header(c.id, c.label, c.num, c.center)}
      {/each}
      <th class="fill"></th>
    </tr>
  </thead>
  <tbody>
    {#if start > 0}
      <tr class="spacer" aria-hidden="true"><td colspan={columns.length + 4} style="height: {start * rowHeight}px"></td></tr>
    {/if}
    {#each visible as f (f.path)}
      {@const ps = problems.get(f.path) ?? []}
      {@const worst = worstSeverity(ps)}
      <tr
        class:selected={selected.has(f.path)}
        data-path={f.path}
        onmousedown={(e) => e.button === 0 && onselect(f.path, e)}
        oncontextmenu={(e) => oncontext(f, e)}
      >
        <td class="name" title={f.path} ondblclick={() => (app.renaming = f.path)}>
          {#if app.renaming === f.path}
            <RenameField path={f.path} name={f.name} isDir={false} />
          {:else}
            {relative(f.path, base)}
          {/if}
        </td>
        <td class="art">
          {#if thumbs.get(f.path)}
            <img class="thumb" src={thumbs.get(f.path)} alt="" title={$t("{count, plural, one {# embedded picture} other {# embedded pictures}}", { values: { count: f.pictures } })} />
          {:else if f.pictures > 0}
            <span class="cell-icon" title={$t("{count, plural, one {# embedded picture} other {# embedded pictures}}", { values: { count: f.pictures } })}><Image size={12} /></span>
          {/if}
        </td>
        <td class="art problem {worst}" title={ps.map((p) => `• ${$t(KINDS[p.kind].title)}: ${p.message}`).join("\n")}>
          {#if worst === "error"}
            <TriangleAlert size={13} />
          {:else if worst === "warning"}
            <CircleAlert size={13} />
          {:else if worst === "info"}
            <Info size={12} />
          {/if}
        </td>
        {#each columns as c (c.id)}
          {@const v = c.get(f)}
          {@const mismatch = c.id === "YEAR" && yearMismatch(f)}
          <td class:num={c.num} class:center={c.center} class:mismatch title={mismatch ? $t("YEAR doesn't match DATE") : v}>
            {v}
          </td>
        {/each}
        <td class="fill"></td>
      </tr>
    {/each}
    {#if end < rows.length}
      <tr class="spacer" aria-hidden="true">
        <td colspan={columns.length + 4} style="height: {(rows.length - end) * rowHeight}px"></td>
      </tr>
    {/if}
  </tbody>
</table>

<style>
  th.center,
  td.center {
    text-align: center;
    font-variant-numeric: tabular-nums;
  }
  th.center .th {
    justify-content: center;
  }
  .th {
    display: inline-flex;
    align-items: center;
    gap: 3px;
  }
  table.virtual {
    table-layout: fixed;
    width: 0;
    min-width: 100%;
  }
  table.virtual th,
  table.virtual td {
    max-width: none;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  col.art-col {
    width: calc(1.75em + 8px);
  }
  tr.spacer td {
    padding: 0;
    border: none;
    background: none !important;
  }
  .grip {
    position: absolute;
    top: 0;
    right: -1px;
    bottom: 0;
    width: 7px;
    cursor: col-resize;
    z-index: 2;
  }
  .grip:hover {
    background: color-mix(in srgb, var(--accent) 35%, transparent);
  }
  th.art,
  td.art {
    padding: 0 4px;
    text-align: center;
  }
  .thumb {
    display: block;
    width: 1.75em;
    height: 1.75em;
    object-fit: cover;
    border-radius: 3px;
    margin: 0 auto;
    box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.12);
  }
  .cell-icon {
    color: var(--fg-muted);
    display: inline-flex;
  }
  td.problem :global(svg) {
    display: block;
    margin: 0 auto;
  }
  td.problem.error {
    color: var(--danger);
  }
  td.problem.warning {
    color: var(--warn);
  }
  td.problem.info {
    color: var(--fg-faint);
  }
  :global(tr.selected) td.problem {
    color: var(--fg-selected);
  }
  td.mismatch {
    color: var(--warn);
    font-weight: 600;
  }
  :global(tr.selected) td.mismatch {
    color: var(--fg-selected);
    text-decoration: underline wavy;
  }
</style>
