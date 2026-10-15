<script lang="ts">
  import { FileAudio, FolderSearch, Zap, ShieldCheck } from "@lucide/svelte";
  import TreeItem from "./TreeItem.svelte";
  import { app } from "./state.svelte";
  import { basename } from "./format";
  import { trashItems } from "./actions";
  import { t } from "./i18n";

  let { onChooseFolder }: { onChooseFolder: () => void } = $props();

  let tree = $state<HTMLDivElement>();

  let rootNode = $derived({
    name: basename(app.root),
    path: app.root,
    isDir: true,
    hasChildren: true,
    cover: null,
    coverModified: 0,
  });

  function onkeydown(e: KeyboardEvent) {
    if (app.renaming || !tree) return;
    const rows = [...tree.querySelectorAll<HTMLElement>("[data-path]")];
    const i = rows.findIndex((r) => r.dataset.path === app.treeSelection);
    const row = rows[i];
    const path = row?.dataset.path;
    const isDir = row?.dataset.dir === "1";
    const go = (r: HTMLElement | undefined) => {
      if (!r) return;
      e.preventDefault();
      r.click();
      r.scrollIntoView({ block: "nearest" });
    };
    switch (e.key) {
      case "ArrowDown":
        go(rows[i + 1]);
        break;
      case "ArrowUp":
        go(rows[Math.max(0, i - 1)]);
        break;
      case "ArrowRight":
        if (path && isDir) {
          e.preventDefault();
          app.expanded.add(path);
        }
        break;
      case "ArrowLeft":
        if (path && isDir && app.expanded.has(path) && path !== app.root) {
          e.preventDefault();
          app.expanded.delete(path);
        } else if (path) {
          const parent = path.slice(0, path.lastIndexOf("/"));
          go(rows.find((r) => r.dataset.path === parent));
        }
        break;
      case "Backspace":
        if (e.metaKey && path) {
          e.preventDefault();
          const many = isDir && app.folders.length > 1 && app.folders.includes(path);
          trashItems(many ? [...app.folders] : [path], isDir);
        }
        break;
      case "Enter":
        if (path) {
          e.preventDefault();
          app.renaming = path;
        }
        break;
    }
  }
</script>

<aside class="sidebar">
  <div class="header">
    <span class="section-title">{$t("Library")}</span>
    <span class="spacer"></span>
    <button
      class="icon-btn"
      title={$t("Fast check of the selected folders (no ID3 or audio checks)")}
      disabled={!app.root}
      onclick={() => app.startCheck("fast")}
    >
      <Zap size={15} />
    </button>
    <button
      class="icon-btn"
      title={$t("Full check of the selected folders")}
      disabled={!app.root}
      onclick={() => app.startCheck("full")}
    >
      <ShieldCheck size={15} />
    </button>
    <button
      class="icon-btn"
      class:active={app.showFilesInTree}
      title={app.showFilesInTree ? $t("Hide files in sidebar") : $t("Show files in sidebar")}
      onclick={() => app.setShowFilesInTree(!app.showFilesInTree)}
    >
      <FileAudio size={15} />
    </button>
  </div>

  {#if app.root}
    <div class="tree" bind:this={tree} tabindex="0" role="tree" {onkeydown}>
      {#key app.root}
        <TreeItem node={rootNode} depth={0} />
      {/key}
    </div>
  {:else}
    <div class="empty">
      <p class="muted">{$t("No folder chosen.")}</p>
      <button class="btn" title={$t("Choose the music folder to show in the sidebar")} onclick={onChooseFolder}
        ><FolderSearch size={14} /> {$t("Choose folder…")}</button
      >
    </div>
  {/if}
</aside>

<style>
  .sidebar {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--bg-sidebar);
    border-right: 1px solid var(--border);
    min-width: 0;
    min-height: 0;
  }
  .header {
    display: flex;
    align-items: center;
    height: 34px;
    padding: 0 8px 0 var(--pane-pad);
    flex: none;
  }
  .spacer {
    flex: 1;
  }
  .tree {
    flex: 1;
    overflow: auto;
    padding-bottom: 12px;
    outline: none;
  }
  .empty {
    padding: 20px 14px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }
  .empty p {
    margin: 0;
  }
</style>
