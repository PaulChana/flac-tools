<script lang="ts">
  import { Settings2, Palette, X, Check, ChevronDown, Minus, Plus, RotateCcw } from "@lucide/svelte";
  import { onMount } from "svelte";
  import { t, language, languages } from "./i18n";
  import { theme, PALETTES, ACCENTS } from "./theme.svelte";
  import { spacing, DEFAULT_ROW_PADDING, MIN_ROW_PADDING, MAX_ROW_PADDING } from "./spacing.svelte";
  import { contextMenu } from "./menu.svelte";
  import { zoom } from "./zoom";
  import { normaliseHex } from "./colour";

  let { onclose }: { onclose: () => void } = $props();

  let tab = $state<"general" | "theme">("general");
  let langs = $state<{ code: string; label: string }[]>([]);
  let customAccent = $state(theme.customAccent ?? "");
  let accentInvalid = $state(false);

  onMount(() => {
    languages().then((l) => (langs = l));
  });

  const langLabel = (code: string) => (code === "auto" ? $t("Automatic (system language)") : (langs.find((l) => l.code === code)?.label ?? code));

  function chooseLanguage() {
    contextMenu(
      langs.map((l) => ({
        text: langLabel(l.code),
        checked: $language === l.code,
        action: () => language.set(l.code),
      })),
    );
  }

  function applyCustomAccent() {
    const hex = normaliseHex(customAccent);
    if (!customAccent.trim()) theme.setAccent(null);
    else if (hex) theme.setAccent(hex);
    else accentInvalid = true;
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape") onclose();
  }

</script>

<svelte:window {onkeydown} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="overlay" onclick={onclose}>
  <div class="modal" role="dialog" aria-label={$t("Settings")} tabindex="-1" onclick={(e) => e.stopPropagation()}>
    <header>
      <h2>{$t("Settings")}</h2>
      <button class="icon-btn" onclick={onclose} title={$t("Close")}><X size={16} /></button>
    </header>
    <div class="body">
      <nav class="rail">
        <button class="tab" class:selected={tab === "general"} onclick={() => (tab = "general")} title={$t("Language, line spacing and zoom")}>
          <Settings2 size={17} /><span>{$t("General")}</span>
        </button>
        <button class="tab" class:selected={tab === "theme"} onclick={() => (tab = "theme")} title={$t("Colours")}>
          <Palette size={17} /><span>{$t("Theme")}</span>
        </button>
      </nav>

      <div class="panel">
        {#if tab === "general"}
          <div class="row">
            <span class="label">{$t("Language")}</span>
            <button class="select" onclick={chooseLanguage} title={$t("Choose the language the app uses")}>
              <span>{langLabel($language)}</span>
              <ChevronDown size={14} />
            </button>
          </div>

          <div class="row">
            <span class="label">{$t("Line spacing")}</span>
            <div class="stepper">
              <button class="icon-btn" onclick={spacing.reduce} disabled={spacing.rowPadding <= MIN_ROW_PADDING} title={$t("Reduce line spacing (⇧⌘-)")}>
                <Minus size={14} />
              </button>
              <input
                type="range"
                min={MIN_ROW_PADDING}
                max={MAX_ROW_PADDING}
                step="0.1"
                value={spacing.rowPadding}
                oninput={(e) => spacing.set(Number(e.currentTarget.value))}
                title={$t("Space above and below each row in tables and lists")}
              />
              <button class="icon-btn" onclick={spacing.increase} disabled={spacing.rowPadding >= MAX_ROW_PADDING} title={$t("Increase line spacing (⇧⌘=)")}>
                <Plus size={14} />
              </button>
              <button class="icon-btn" onclick={spacing.reset} disabled={spacing.rowPadding === DEFAULT_ROW_PADDING} title={$t("Reset line spacing (⇧⌘0)")}>
                <RotateCcw size={13} />
              </button>
            </div>
          </div>

          <div class="row">
            <span class="label">{$t("Zoom")}</span>
            <div class="stepper">
              <button class="icon-btn" onclick={() => zoom.out()} title={$t("Zoom out (⌘-)")}><Minus size={14} /></button>
              <button class="icon-btn" onclick={() => zoom.in()} title={$t("Zoom in (⌘=)")}><Plus size={14} /></button>
              <button class="icon-btn" onclick={() => zoom.reset()} title={$t("Actual size (⌘0)")}><RotateCcw size={13} /></button>
            </div>
          </div>
        {:else}
          <div class="row stacked">
            <span class="label">{$t("Palette")}</span>
            <div class="palettes">
              {#each PALETTES as p (p.id)}
                <button
                  class="palette"
                  class:active={theme.palette === p.id}
                  style="--swatch-bg: {p.background}; --swatch-panel: {p.panel}; --swatch-border: {p.border}; --swatch-text: {p.text}"
                  onclick={() => theme.setPalette(p.id)}
                  title={$t(p.label)}
                  aria-pressed={theme.palette === p.id}
                >
                  <span class="preview" aria-hidden="true">
                    <span class="side"><span class="line"></span><span class="line short"></span><span class="line"></span></span>
                    <span class="main">
                      <span class="line"></span><span class="line short"></span><span class="line hl"></span>
                      <span class="foot"></span>
                    </span>
                  </span>
                  <span class="name">{$t(p.label)}</span>
                </button>
              {/each}
            </div>
          </div>

          <div class="row stacked">
            <span class="label">{$t("Accent colour")}</span>
            <div class="accent-field">
              <div class="accents">
                {#each ACCENTS as a (a.hex)}
                  <button
                    class="accent"
                    class:active={theme.accent === a.hex}
                    style="--swatch: {a.hex}"
                    onclick={() => {
                      theme.setAccent(a.hex);
                      customAccent = a.hex;
                    }}
                    title={$t(a.label)}
                    aria-pressed={theme.accent === a.hex}
                  >
                    {#if theme.accent === a.hex}<Check size={14} />{/if}
                  </button>
                {/each}
              </div>
              <div class="custom">
                <label for="custom-accent">{$t("Custom")}</label>
                <input
                  id="custom-accent"
                  class:invalid={accentInvalid}
                  placeholder={theme.current.defaultAccent}
                  bind:value={customAccent}
                  oninput={() => (accentInvalid = false)}
                  onchange={applyCustomAccent}
                  onkeydown={(e) => e.key === "Enter" && applyCustomAccent()}
                  spellcheck="false"
                  title={$t("A colour as a hex value, like #94c7b6. Leave empty for the palette's own.")}
                />
                <span class="current" style="--swatch: {theme.accent}" title={$t("Current accent colour")}></span>
                <button
                  class="btn"
                  onclick={() => {
                    theme.setAccent(null);
                    customAccent = "";
                  }}
                  disabled={!theme.customAccent}
                  title={$t("Use the palette's own accent colour")}
                >
                  {$t("Reset")}
                </button>
              </div>
            </div>
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 1000;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.4);
    animation: fade 0.2s ease-out;
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  .modal {
    width: min(46rem, calc(100vw - 2rem));
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    background: var(--panel-background);
    border: 1px solid var(--border);
    border-radius: 0.75rem;
    box-shadow: 0 0 1.875rem rgba(0, 0, 0, 0.3);
    overflow: hidden;
  }
  header {
    display: flex;
    align-items: center;
    padding: 0.6rem 0.75rem 0.6rem 1.25rem;
    border-bottom: 1px solid var(--border);
  }
  h2 {
    flex: 1;
    margin: 0;
    font-size: 1.25rem;
    font-weight: 500;
  }
  .body {
    display: flex;
    min-height: 0;
    flex: 1;
  }
  .rail {
    flex: none;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.75rem 0.5rem;
    border-right: 1px solid var(--border-subtle);
    width: 10rem;
  }
  .tab {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.5rem 0.7rem;
    border: none;
    border-radius: 0.375rem;
    background: none;
    color: var(--text-muted);
    text-align: left;
  }
  .tab:hover {
    background: var(--overlay-1);
    color: var(--text);
  }
  .tab.selected {
    background: var(--accent-overlay-2);
    color: var(--accent-readable);
  }
  .panel {
    flex: 1;
    min-width: 0;
    overflow: auto;
    padding: 1.25rem 1.5rem 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }
  .row {
    display: grid;
    grid-template-columns: 9rem 1fr;
    align-items: center;
    gap: 1rem;
  }
  .row.stacked {
    grid-template-columns: 1fr;
    gap: 0.6rem;
  }
  .label {
    color: var(--text-secondary);
  }
  .row:not(.stacked) .label {
    text-align: right;
  }
  .select {
    display: inline-flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.6rem;
    min-width: 14rem;
    justify-self: start;
    height: 30px;
    padding: 0 0.6rem 0 0.75rem;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--surface-raised);
  }
  .select:hover {
    background: var(--surface-hover);
  }
  .stepper {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }
  .stepper input[type="range"] {
    width: 12rem;
    accent-color: var(--accent);
  }
  .palettes {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 0.75rem;
  }
  .palette {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
    padding: 0;
    border: none;
    background: none;
    color: var(--text-muted);
    font-size: 0.8rem;
  }
  .palette.active {
    color: var(--text);
  }
  .preview {
    display: flex;
    height: 5rem;
    border-radius: 0.375rem;
    overflow: hidden;
    background: var(--swatch-bg);
    box-shadow: inset 0 0 0 1px var(--swatch-border);
    transition: box-shadow 0.12s ease;
  }
  .palette:hover .preview {
    box-shadow:
      inset 0 0 0 1px var(--swatch-border),
      0 0 0 2px var(--surface-active);
  }
  .palette.active .preview {
    box-shadow:
      inset 0 0 0 1px var(--swatch-border),
      0 0 0 2px var(--accent);
  }
  .side {
    width: 28%;
    background: var(--swatch-panel);
    border-right: 1px solid var(--swatch-border);
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 5px 4px;
  }
  .main {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 5px 5px 0;
  }
  .line {
    height: 3px;
    border-radius: 2px;
    background: var(--swatch-text);
    opacity: 0.55;
  }
  .side .line {
    opacity: 0.35;
  }
  .line.short {
    width: 55%;
  }
  .line.hl {
    width: 72%;
    background: var(--accent);
    opacity: 1;
  }
  .foot {
    margin: auto -5px 0;
    height: 8px;
    background: var(--accent);
  }
  .accent-field {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding: 1rem;
    background: var(--surface-raised);
    border: 1px solid var(--border);
    border-radius: 0.5rem;
  }
  .accents {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(2rem, 1fr));
    gap: 0.75rem;
    justify-items: center;
  }
  .accent {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.75rem;
    height: 1.75rem;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: var(--swatch);
    color: #fff;
    box-shadow: inset 0 0 0 1px var(--overlay-3);
    transition: box-shadow 0.12s ease;
  }
  .accent:hover {
    box-shadow:
      inset 0 0 0 1px var(--overlay-3),
      0 0 0 2px var(--surface-active);
  }
  .accent.active {
    box-shadow: 0 0 0 2px var(--background), 0 0 0 4px var(--swatch);
  }
  .custom {
    display: flex;
    align-items: center;
    gap: 0.6rem;
  }
  .custom label {
    color: var(--text-secondary);
  }
  .custom input {
    width: 8rem;
    font-family: var(--mono);
  }
  .custom input.invalid {
    border-color: var(--error);
  }
  .current {
    width: 1.5rem;
    height: 1.5rem;
    border-radius: 50%;
    background: var(--swatch);
    box-shadow: inset 0 0 0 1px var(--overlay-3);
  }
</style>
