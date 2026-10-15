<script lang="ts">
  import { ChevronLeft, ChevronRight, X, FolderSearch, LoaderCircle } from "@lucide/svelte";
  import { api, type FileSummary } from "./api";
  import { formatSize } from "./format";
  import { t } from "./i18n";

  let {
    images,
    start,
    onclose,
  }: {
    images: FileSummary[];
    start: number;
    onclose: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let index = $state(start);
  let src = $state<string | null>(null);
  let error = $state<string | null>(null);

  let img = $derived(images[index]);

  $effect(() => {
    const path = img?.path;
    src = null;
    error = null;
    if (!path) return;
    api
      .readImage(path)
      .then((url) => {
        if (img?.path === path) src = url;
      })
      .catch((e) => {
        if (img?.path === path) error = String(e);
      });
  });

  function step(d: number) {
    if (images.length > 1) index = (index + d + images.length) % images.length;
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape" || e.key === " ") {
      e.preventDefault();
      onclose();
    } else if (e.key === "ArrowRight" || e.key === "ArrowDown") {
      e.preventDefault();
      step(1);
    } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
      e.preventDefault();
      step(-1);
    }
  }
</script>

<svelte:window {onkeydown} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="viewer" onclick={onclose}>
  <header onclick={(e) => e.stopPropagation()}>
    <span class="name" title={img.path}>{img.name}</span>
    <span class="meta">
      {#if img.width && img.height}
        {img.width} × {img.height}
        {#if img.width !== img.height}<span class="warn">· {$t("not square")}</span>{/if}
        ·
      {/if}
      {formatSize(img.size)}
      {#if images.length > 1}· {$t("{index} of {total}", { values: { index: index + 1, total: images.length } })}{/if}
    </span>
    <span class="spacer"></span>
    <button class="icon-btn" title={$t("Reveal in Finder")} onclick={() => api.revealInFinder(img.path)}>
      <FolderSearch size={16} />
    </button>
    <button class="icon-btn" title={$t("Close (Esc)")} onclick={onclose}><X size={17} /></button>
  </header>

  <div class="stage">
    {#if error}
      <p class="error">{error}</p>
    {:else if src}
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions, a11y_click_events_have_key_events -->
      <img {src} alt={img.name} onclick={(e) => e.stopPropagation()} />
    {:else}
      <LoaderCircle size={22} class="spin" />
    {/if}
  </div>

  {#if images.length > 1}
    <button class="nav prev" title={$t("Previous (←)")} onclick={(e) => (e.stopPropagation(), step(-1))}>
      <ChevronLeft size={26} />
    </button>
    <button class="nav next" title={$t("Next (→)")} onclick={(e) => (e.stopPropagation(), step(1))}>
      <ChevronRight size={26} />
    </button>
  {/if}
</div>

<style>
  .viewer {
    position: fixed;
    inset: 0;
    z-index: 30;
    display: flex;
    flex-direction: column;
    background: rgba(12, 12, 14, 0.97);
    backdrop-filter: blur(8px);
    color: #ececee;
  }
  header {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 46px;
    padding: 0 10px 0 18px;
    flex: none;
  }
  .name {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .meta {
    color: #a1a1a8;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .warn {
    color: #f0a640;
  }
  .spacer {
    flex: 1;
  }
  header .icon-btn {
    color: #c4c4ca;
  }
  header .icon-btn:hover {
    background: rgba(255, 255, 255, 0.1);
    color: #fff;
  }
  .stage {
    flex: 1;
    min-height: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 64px 28px;
  }
  img {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
    background: repeating-conic-gradient(#3a3a3e 0% 25%, #2a2a2e 0% 50%) 50% / 16px 16px;
  }
  .error {
    color: #ff7b72;
  }
  .nav {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    width: 44px;
    height: 64px;
    border: none;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.06);
    color: #d8d8dc;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .nav:hover {
    background: rgba(255, 255, 255, 0.14);
    color: #fff;
  }
  .prev {
    left: 10px;
  }
  .next {
    right: 10px;
  }
</style>
