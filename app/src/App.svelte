<script lang="ts">
  import {
    FolderOpen,
    X,
    FolderSearch,
    PanelLeft,
    PanelRight,
    PanelBottom,
    LoaderCircle,
    CircleCheck,
    CircleAlert,
    TriangleAlert,
    CircleStop,
  } from "@lucide/svelte";
  import { open } from "@tauri-apps/plugin-dialog";
  import { listen } from "@tauri-apps/api/event";
  import { onMount } from "svelte";
  import { api } from "./lib/api";
  import { runner } from "./lib/runner.svelte";
  import Sidebar from "./lib/Sidebar.svelte";
  import FolderView from "./lib/FolderView.svelte";
  import ToolsView from "./lib/ToolsView.svelte";
  import OutputPanel from "./lib/OutputPanel.svelte";
  import ProblemsDialog from "./lib/ProblemsDialog.svelte";
  import SettingsDialog from "./lib/SettingsDialog.svelte";
  import AboutDialog from "./lib/AboutDialog.svelte";
  import ContextMenu from "./lib/ContextMenu.svelte";
  import { app } from "./lib/state.svelte";
  import { layout, startDrag } from "./lib/layout.svelte";
  import { spacing } from "./lib/spacing.svelte";
  import { zoom } from "./lib/zoom";
  import { t, msg } from "./lib/i18n";

  $effect(() => {
    if (app.root) api.watchRoot(app.root).catch((e) => app.showError(e));
  });

  const MENU_ACTIONS: Record<string, () => unknown> = {
    "zoom-in": zoom.in,
    "zoom-out": zoom.out,
    "zoom-reset": zoom.reset,
    "spacing-increase": spacing.increase,
    "spacing-reduce": spacing.reduce,
    "spacing-reset": spacing.reset,
    open: chooseFolder,
    refresh: () => app.root && app.refresh(),
    "view-library": () => (app.view = "library"),
    "view-tools": () => (app.view = "tools"),
    settings: () => (app.dialog = "settings"),
    about: () => (app.dialog = "about"),
    "toggle-left": () => layout.toggle("Left"),
    "toggle-right": () => layout.toggle("Right"),
    "toggle-bottom": () => layout.toggle("Bottom"),
  };

  onMount(() => {
    runner.init();
    api
      .windowButtons()
      .then(({ centerY, right }) => {
        const root = document.documentElement.style;
        root.setProperty("--lights-center", `${centerY}px`);
        root.setProperty("--lights-right", `${right}px`);
      })
      .catch(() => {});
    zoom.restore().catch((e) => app.showError(e));
    const un = listen<string[]>("fs-changed", (e) => app.handleFsChange(e.payload));
    const unMenu = listen<string>("menu", (e) => {
      Promise.resolve(MENU_ACTIONS[e.payload]?.()).catch((err) => app.showError(err));
    });
    return () => {
      un.then((f) => f());
      unMenu.then((f) => f());
    };
  });

  async function chooseFolder() {
    const dir = await open({ directory: true, defaultPath: app.root || undefined });
    if (typeof dir === "string") app.setRoot(dir);
  }

  $effect(() => {
    const t = app.toast;
    if (t?.kind !== "info") return;
    const timer = setTimeout(() => {
      if (app.toast === t) app.toast = null;
    }, 2500);
    return () => clearTimeout(timer);
  });

  const RUN_STATE = {
    running: msg("Running…"),
    ok: msg("Finished"),
    warn: msg("Finished with warnings"),
    error: msg("Failed"),
    stopped: msg("Stopped"),
  } as const;
</script>

<svelte:window onfocus={() => app.root && app.refresh()} oncontextmenu={(e) => e.preventDefault()} />

<div class="shell">
  <header class="titlebar" data-tauri-drag-region>
    <span class="title" title={app.root} data-tauri-drag-region>
      <span dir="ltr" data-tauri-drag-region>{app.root || $t("No folder chosen")}</span>
    </span>
  </header>

  <div class="content" style:grid-template-rows="minmax(0, 1fr) {layout.showBottom ? `${layout.bottomHeight}px` : '0'}">
    <div class="main-row" style:grid-template-columns="{layout.showLeft ? `${layout.leftWidth}px` : '0'} 0 minmax(0, 1fr)">
      <div class="left" class:hidden={!layout.showLeft}>
        <Sidebar onChooseFolder={chooseFolder} />
      </div>
      {#if layout.showLeft}
        <div class="splitter v" role="separator" aria-orientation="vertical" title={$t("Drag to resize the library")} onpointerdown={(e) => startDrag(e, "leftWidth", 1)}></div>
      {:else}
        <div></div>
      {/if}
      <main>
        {#if !app.root}
          <div class="welcome">
            <FolderSearch size={40} strokeWidth={1.25} />
            <h1>FLAC Tools</h1>
            <p class="muted">{$t("Point the app at your music folder to browse and edit FLAC tags.")}</p>
            <button class="btn primary" onclick={chooseFolder} title={$t("Choose your music folder (⌘O)")}>
              <FolderOpen size={14} /> {$t("Choose folder…")}
            </button>
          </div>
        {:else}
          <div class="view" class:hidden={app.view !== "library"}>
            <FolderView />
            {#if app.check}
              {#key app.check}
                <ProblemsDialog folders={app.check.folders} mode={app.check.mode} onclose={() => (app.check = null)} />
              {/key}
            {/if}
          </div>
        {/if}
        <div class="view" class:hidden={app.view !== "tools" || !app.root}><ToolsView /></div>
      </main>
    </div>
    <div class="bottom">
      {#if layout.showBottom}
        <div class="splitter h" role="separator" aria-orientation="horizontal" title={$t("Drag to resize the output")} onpointerdown={(e) => startDrag(e, "bottomHeight", -1)}></div>
        <OutputPanel />
      {/if}
    </div>
  </div>

  <footer class="footer">
    <div class="footer-side">
      <button class="foot-btn" class:active={layout.showLeft} onclick={() => layout.toggle("Left")} title={layout.showLeft ? $t("Hide the library (⌥⌘1)") : $t("Show the library (⌥⌘1)")}>
        <PanelLeft size={16} />
      </button>
      {#if runner.status}
        <button class="run-status" onclick={() => layout.toggle("Bottom", true)} title={$t("Show the tool output")}>
          {#if runner.status.state === "running"}
            <LoaderCircle size={13} class="spin" />
          {:else if runner.status.state === "ok"}
            <CircleCheck size={13} />
          {:else if runner.status.state === "warn"}
            <CircleAlert size={13} />
          {:else if runner.status.state === "stopped"}
            <CircleStop size={13} />
          {:else}
            <TriangleAlert size={13} />
          {/if}
          <span class="run-title">{runner.status.title}</span>
          <span class="run-state">— {$t(RUN_STATE[runner.status.state])}</span>
        </button>
      {/if}
    </div>
    <button class="foot-btn" class:active={layout.showBottom} onclick={() => layout.toggle("Bottom")} title={layout.showBottom ? $t("Hide the tool output (⌥⌘2)") : $t("Show the tool output (⌥⌘2)")}>
      <PanelBottom size={16} />
    </button>
    <div class="footer-side right">
      <button class="foot-btn" class:active={layout.showRight} onclick={() => layout.toggle("Right")} title={layout.showRight ? $t("Hide the tag editor (⌥⌘3)") : $t("Show the tag editor (⌥⌘3)")}>
        <PanelRight size={16} />
      </button>
    </div>
  </footer>

  {#if app.toast}
    <div class="toast {app.toast.kind}">
      <span>{app.toast.text}</span>
      <button class="icon-btn" onclick={() => (app.toast = null)} aria-label={$t("Dismiss")} title={$t("Dismiss")}><X size={13} /></button>
    </div>
  {/if}

  {#if app.dialog === "settings"}
    <SettingsDialog onclose={() => (app.dialog = null)} />
  {:else if app.dialog === "about"}
    <AboutDialog onclose={() => (app.dialog = null)} />
  {/if}
  <ContextMenu />
</div>

<style>
  .shell {
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .titlebar {
    display: flex;
    align-items: center;
    justify-content: center;
    height: calc(2 * var(--lights-center, 14px) / var(--zoom, 1));
    padding: 0 calc((var(--lights-right, 68px) + 12px) / var(--zoom, 1));
    background: color-mix(in srgb, var(--panel-background) 88%, #000);
    flex: none;
  }
  .title {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    direction: rtl;
    font-size: calc(13px / var(--zoom, 1));
    color: var(--text-secondary);
  }
  .content {
    flex: 1;
    min-height: 0;
    display: grid;
    transition: grid-template-rows 0.25s cubic-bezier(0.45, 0.05, 0.55, 0.95);
  }
  .main-row {
    display: grid;
    min-height: 0;
    transition: grid-template-columns 0.25s cubic-bezier(0.45, 0.05, 0.55, 0.95);
    grid-template-rows: minmax(0, 1fr);
  }
  :global(body.col-resizing) .main-row,
  :global(body.row-resizing) .content {
    transition: none;
  }
  .left {
    min-width: 0;
    overflow: hidden;
    background: var(--panel-background);
    border-right: 1px solid var(--border);
  }
  .left.hidden {
    border-right: none;
  }
  .splitter {
    position: relative;
    z-index: 3;
  }
  .splitter::after {
    content: "";
    position: absolute;
  }
  .splitter.v::after {
    inset: 0 -3px;
    cursor: col-resize;
  }
  .splitter.h {
    height: 0;
  }
  .splitter.h::after {
    inset: -3px 0;
    cursor: row-resize;
  }
  .bottom {
    min-height: 0;
    display: flex;
    flex-direction: column;
    border-top: 1px solid var(--border);
    overflow: hidden;
  }
  .bottom :global(.output) {
    flex: 1;
    min-height: 0;
  }
  main {
    min-width: 0;
    min-height: 0;
    position: relative;
    background: var(--background);
  }
  .view {
    position: absolute;
    inset: 0;
  }
  .view.hidden {
    display: none;
  }
  .welcome {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    color: var(--fg-muted);
  }
  .welcome h1 {
    margin: 4px 0 0;
    font-size: 20px;
    font-weight: 600;
    color: var(--fg);
  }
  .welcome p {
    margin: 0 0 8px;
  }
  .footer {
    flex: none;
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    height: 34px;
    padding: 0 10px;
    background: var(--accent);
    color: var(--accent-contrast);
  }
  .footer-side {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  .footer-side.right {
    justify-content: flex-end;
  }
  .foot-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 26px;
    padding: 0;
    border: none;
    border-radius: 5px;
    background: none;
    color: var(--accent-contrast);
    opacity: 0.55;
  }
  .foot-btn.active {
    opacity: 1;
  }
  .foot-btn:hover {
    background: color-mix(in srgb, var(--accent-contrast) 14%, transparent);
  }
  .run-status {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    height: 24px;
    padding: 0 8px;
    border: none;
    border-radius: 5px;
    background: none;
    color: var(--accent-contrast);
    font-size: 12.5px;
  }
  .run-status:hover {
    background: color-mix(in srgb, var(--accent-contrast) 14%, transparent);
  }
  .run-title {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .run-state {
    white-space: nowrap;
    opacity: 0.85;
  }
  .toast {
    position: fixed;
    bottom: 48px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 8px;
    max-width: min(640px, calc(100vw - 32px));
    padding: 6px 6px 6px 14px;
    border-radius: 8px;
    background: var(--panel-background);
    border: 1px solid var(--border-strong);
    box-shadow: 0 6px 24px rgba(0, 0, 0, 0.25);
    z-index: 10;
    white-space: pre-wrap;
  }
  .toast.error {
    border-color: var(--danger);
    color: var(--danger);
  }
</style>
