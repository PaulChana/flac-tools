<script lang="ts">
  import { Check, ChevronRight } from "@lucide/svelte";
  import { tick } from "svelte";
  import { menu, type MenuEntry } from "./menu.svelte";

  let menuEl = $state<HTMLDivElement>();
  let subEl = $state<HTMLDivElement>();
  let left = $state(0);
  let top = $state(0);
  let open = $state<number | null>(null);
  let subLeft = $state(0);
  let subTop = $state(0);
  let parentRect: DOMRect | null = null;

  const isItem = (e: MenuEntry): e is Exclude<MenuEntry, "separator"> => e !== "separator";
  const hasItems = (e: MenuEntry) => isItem(e) && "items" in e;
  let anyChecks = $derived(menu.entries?.some((e) => isItem(e) && "checked" in e && e.checked !== undefined) ?? false);
  let anySubmenus = $derived(menu.entries?.some(hasItems) ?? false);

  $effect(() => {
    if (!menu.entries) return;
    open = null;
    left = menu.x;
    top = menu.y;
    tick().then(() => {
      if (!menuEl) return;
      const r = menuEl.getBoundingClientRect();
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      if (top + r.height > vh - 6) {
        top = menu.anchor ? menu.anchor.top - r.height - 4 : top - r.height;
      }
      top = Math.max(6, Math.min(top, vh - r.height - 6));
      left = Math.max(6, Math.min(left, vw - r.width - 6));
      menuEl.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus({ preventScroll: true });
    });
  });

  async function openSub(i: number, el: HTMLElement) {
    parentRect = el.getBoundingClientRect();
    open = i;
    subLeft = parentRect.right - 2;
    subTop = parentRect.top - 5;
    await tick();
    if (!subEl || !parentRect) return;
    const r = subEl.getBoundingClientRect();
    if (subLeft + r.width > window.innerWidth - 6) subLeft = parentRect.left - r.width + 2;
    subTop = Math.max(6, Math.min(subTop, window.innerHeight - r.height - 6));
  }

  function choose(e: MenuEntry) {
    if (!isItem(e) || e.enabled === false || !("action" in e)) return;
    menu.close();
    e.action();
  }

  function onkeydown(e: KeyboardEvent) {
    if (!menu.entries) return;
    if (e.key === "Escape") {
      e.preventDefault();
      if (open !== null) open = null;
      else menu.close();
      return;
    }
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp" && e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    e.preventDefault();
    const inSub = subEl?.contains(document.activeElement);
    if (e.key === "ArrowLeft" && inSub) {
      open = null;
      return;
    }
    if (e.key === "ArrowRight") {
      const el = document.activeElement as HTMLElement | null;
      if (el?.dataset.sub !== undefined) {
        openSub(Number(el.dataset.sub), el).then(() => subEl?.querySelector<HTMLButtonElement>("button:not(:disabled)")?.focus());
      }
      return;
    }
    const container = inSub ? subEl : menuEl;
    const buttons = [...(container?.querySelectorAll<HTMLButtonElement>("button:not(:disabled)") ?? [])];
    const i = buttons.indexOf(document.activeElement as HTMLButtonElement);
    const next = e.key === "ArrowDown" ? (i + 1) % buttons.length : (i - 1 + buttons.length) % buttons.length;
    buttons[next]?.focus();
  }

  function onpointerdown(e: PointerEvent) {
    if (!menu.entries) return;
    const t = e.target as Node;
    if (!menuEl?.contains(t) && !subEl?.contains(t)) menu.close();
  }
</script>

<svelte:window {onkeydown} onpointerdowncapture={onpointerdown} onblur={() => menu.close()} onresize={() => menu.close()} />

{#snippet entryButton(entry: MenuEntry, i: number, sub: boolean)}
  {#if !isItem(entry)}
    <div class="divider" role="separator"></div>
  {:else}
    <button
      type="button"
      class="item"
      class:danger={"danger" in entry && entry.danger}
      class:open={!sub && open === i}
      role="menuitem"
      disabled={entry.enabled === false}
      data-sub={!sub && "items" in entry ? i : undefined}
      onmouseenter={(e) => {
        if (sub) return;
        if ("items" in entry && entry.enabled !== false) openSub(i, e.currentTarget);
        else open = null;
      }}
      onclick={(e) => ("items" in entry ? openSub(i, e.currentTarget) : choose(entry))}
    >
      {#if anyChecks}
        <span class="check">{#if "checked" in entry && entry.checked}<Check size={13} />{/if}</span>
      {/if}
      <span class="label">{entry.text}</span>
      {#if !sub && anySubmenus}
        <span class="chevron" class:empty={!("items" in entry)}><ChevronRight size={13} /></span>
      {/if}
    </button>
  {/if}
{/snippet}

{#if menu.entries}
  <div class="menu" role="menu" tabindex="-1" bind:this={menuEl} style:left="{left}px" style:top="{top}px">
    {#each menu.entries as entry, i (i)}
      {@render entryButton(entry, i, false)}
    {/each}
  </div>
  {#if open !== null}
    {@const parent = menu.entries[open]}
    {#if isItem(parent) && "items" in parent}
      <div class="menu sub" role="menu" tabindex="-1" bind:this={subEl} style:left="{subLeft}px" style:top="{subTop}px">
        {#each parent.items as entry, i (i)}
          {@render entryButton(entry, i, true)}
        {/each}
      </div>
    {/if}
  {/if}
{/if}

<style>
  .menu {
    position: fixed;
    z-index: 10050;
    min-width: 11rem;
    max-width: 26rem;
    max-height: calc(100vh - 1rem);
    overflow-y: auto;
    padding: 0.25rem;
    background: var(--panel-background);
    border: 1px solid var(--border);
    border-radius: 0.5rem;
    box-shadow: 0 0.25rem 1rem rgba(0, 0, 0, 0.4);
    animation: pop 0.1s ease-out;
    outline: none;
  }
  .menu.sub {
    z-index: 10051;
  }
  @keyframes pop {
    from {
      opacity: 0;
      transform: scale(0.97);
    }
  }
  .item {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    width: 100%;
    padding: 0.4rem 0.7rem;
    border: none;
    border-radius: 0.3rem;
    background: none;
    color: var(--text);
    text-align: left;
    font-size: 0.93rem;
    outline: none;
  }
  .item:hover:not(:disabled),
  .item:focus-visible,
  .item.open {
    background: var(--overlay-2);
  }
  .item:disabled {
    opacity: 0.4;
  }
  .item.danger:hover:not(:disabled) {
    color: var(--error);
  }
  .label {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .check,
  .chevron {
    display: inline-flex;
    width: 13px;
    flex: none;
  }
  .chevron {
    color: var(--text-muted);
  }
  .chevron.empty {
    visibility: hidden;
  }
  .divider {
    height: 1px;
    margin: 0.25rem 0.4rem;
    background: var(--border-subtle);
  }
</style>
