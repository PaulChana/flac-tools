<script lang="ts">
  import { ChevronRight, Folder, FolderOpen, FileAudio } from "@lucide/svelte";
  import TreeItem from "./TreeItem.svelte";
  import RenameField from "./RenameField.svelte";
  import { api, type TreeNode } from "./api";
  import { app } from "./state.svelte";
  import { contextMenu } from "./menu.svelte";
  import { trashItems } from "./actions";
  import { runner } from "./runner.svelte";
  import { prettyToolName } from "./args";
  import type { MenuEntry } from "./menu.svelte";
  import { coverThumb } from "./coverThumbs";
  import { t } from "./i18n";

  let { node, depth }: { node: TreeNode; depth: number } = $props();

  let children = $state<TreeNode[] | null>(null);
  let cover = $state<string | null>(null);

  $effect(() => {
    const path = node.cover;
    cover = null;
    if (!path) return;
    coverThumb(path, node.coverModified).then((url) => {
      if (node.cover === path) cover = url;
    });
  });
  let expanded = $derived(app.expanded.has(node.path));
  let fileFocused = $derived(!app.folders.includes(app.treeSelection));
  let selected = $derived(
    node.isDir ? !fileFocused && app.folders.includes(node.path) : app.treeSelection === node.path,
  );

  $effect(() => {
    if (!expanded) return;
    const _ = [app.treeVersion, app.showFilesInTree];
    const path = node.path;
    api
      .listTree(path, app.showFilesInTree)
      .then((c) => {
        if (node.path === path) children = c;
      })
      .catch((e) => {
        children = [];
        if (!String(e).includes("os error 2")) app.showError(e);
      });
  });

  function toggle(e?: MouseEvent) {
    e?.stopPropagation();
    if (expanded) app.expanded.delete(node.path);
    else app.expanded.add(node.path);
  }

  function visibleFolders(): string[] {
    return [...document.querySelectorAll<HTMLElement>(".tree [data-dir='1']")].map((r) => r.dataset.path!);
  }

  function select(e?: MouseEvent) {
    if (!node.isDir) app.openFile(node.path);
    else if (e?.metaKey) app.toggleFolder(node.path);
    else if (e?.shiftKey) app.selectFolderRange(node.path, visibleFolders());
    else app.openFolder(node.path);
  }

  function showMenu(e: MouseEvent) {
    e.preventDefault();
    const multi = node.isDir && app.folders.length > 1 && app.folders.includes(node.path);
    if (!multi) select();
    const targets = multi ? [...app.folders] : [node.path];
    const runMenus: MenuEntry[] = [
      {
        text: multi ? $t("Run tool on {count} folders", { values: { count: targets.length } }) : $t("Run tool"),
        items: runner.tools.map((t) => ({
          text: prettyToolName(t.name) + (runner.requiredInputs(t.name).length ? "…" : ""),
          action: () => runner.runToolFromMenu(t.name, targets),
        })),
        enabled: runner.tools.length > 0 && !runner.busy,
      },
      {
        text: multi ? $t("Run chain on {count} folders", { values: { count: targets.length } }) : $t("Run chain"),
        items: runner.chains.length
          ? runner.chains.map((c) => ({
              text: c.name,
              enabled: c.steps.length > 0,
              action: () => runner.runChainFromMenu(c.id, targets),
            }))
          : [{ text: $t("No chains yet — make one in Tools"), enabled: false, action: () => {} }],
        enabled: !runner.busy,
      },
      { text: $t("Open in Tools…"), action: () => (app.view = "tools") },
      "separator",
      {
        text: multi ? $t("Fast check on {count} folders", { values: { count: targets.length } }) : $t("Fast check"),
        action: () => app.startCheck("fast", targets),
      },
      {
        text: multi ? $t("Full check on {count} folders", { values: { count: targets.length } }) : $t("Full check"),
        action: () => app.startCheck("full", targets),
      },
    ];
    if (multi) {
      contextMenu([
        ...runMenus,
        "separator",
        {
          text: $t("Move {count} folders to Trash", { values: { count: app.folders.length } }),
          enabled: !app.folders.includes(app.root),
          action: () => trashItems([...app.folders], true),
        },
      ]);
      return;
    }
    contextMenu([
      { text: $t("Rename"), action: () => (app.renaming = node.path) },
      { text: $t("Reveal in Finder"), action: () => api.revealInFinder(node.path) },
      ...(node.isDir ? ["separator" as const, ...runMenus] : []),
      "separator",
      {
        text: $t("Move to Trash"),
        enabled: node.path !== app.root,
        action: () => trashItems([node.path], node.isDir),
      },
    ]);
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div
  class="row"
  class:selected
  data-path={node.path}
  data-dir={node.isDir ? "1" : "0"}
  style:padding-left="{6 + depth * 14}px"
  onclick={(e) => select(e)}
  ondblclick={() => (app.renaming = node.path)}
  oncontextmenu={showMenu}
  role="treeitem"
  aria-selected={selected}
  aria-expanded={node.isDir ? expanded : undefined}
  tabindex="-1"
>
  {#if node.isDir && node.hasChildren}
    <button
      class="chevron"
      class:open={expanded}
      onclick={toggle}
      tabindex="-1"
      title={expanded ? $t("Collapse folder (←)") : $t("Expand folder (→)")}
      aria-label={expanded ? $t("Collapse folder") : $t("Expand folder")}
    >
      <ChevronRight size={12} strokeWidth={2.5} />
    </button>
  {:else}
    <span class="chevron-space"></span>
  {/if}
  <span class="icon" class:file={!node.isDir}>
    {#if !node.isDir}
      <FileAudio size={14} />
    {:else if expanded && node.hasChildren}
      <FolderOpen size={14} />
    {:else}
      <Folder size={14} />
    {/if}
  </span>
  {#if cover}
    <img class="cover" src={cover} alt="" />
  {/if}
  {#if app.renaming === node.path}
    <RenameField path={node.path} name={node.name} isDir={node.isDir} />
  {:else}
    <span class="name" title={node.name}>{node.name}</span>
  {/if}
</div>

{#if expanded && children}
  {#each children as child (child.path)}
    <TreeItem node={child} depth={depth + 1} />
  {/each}
{/if}

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 4px;
    height: calc(1.5em + 2 * var(--row-padding));
    padding-right: 8px;
    margin: 0 6px;
    border-radius: 5px;
    outline: none;
  }
  .row:hover {
    background: var(--bg-hover);
  }
  .row.selected {
    background: var(--bg-selected-muted);
  }
  :global(.tree:focus-within) .row.selected {
    background: var(--bg-selected);
    color: var(--fg-selected);
  }
  :global(.tree:focus-within) .row.selected .icon {
    color: var(--fg-selected);
  }
  .chevron,
  .chevron-space {
    flex: none;
    width: 14px;
    height: 14px;
  }
  .chevron {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: none;
    padding: 0;
    color: inherit;
    opacity: 0.6;
    transition: transform 0.12s;
  }
  .chevron.open {
    transform: rotate(90deg);
  }
  .icon {
    flex: none;
    display: inline-flex;
    color: var(--folder);
  }
  .icon.file {
    color: var(--fg-muted);
  }
  .cover {
    flex: none;
    width: 14px;
    height: 14px;
    border-radius: 2px;
    object-fit: cover;
    box-shadow: 0 0 0 0.5px rgba(0, 0, 0, 0.25);
  }
  .name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
