<script lang="ts">
  import { X, ArrowLeft, ChevronRight, ChevronDown, ExternalLink, Copy, Check, GitBranch, Scale } from "@lucide/svelte";
  import { t, msg } from "./i18n";
  import { api } from "./api";
  import { app } from "./state.svelte";
  import { licenses, type LicenseEntry } from "./generated/licenses";

  let { onclose }: { onclose: () => void } = $props();

  const GITHUB = "https://github.com/PaulChana/flac-tools";
  const WEBSITE = "https://escapement-audio.co.uk";
  const BREW = "brew install fish flac jq shntool cuetools rsgain";

  const CATEGORIES: Record<string, string> = { Frontend: msg("Interface"), Fonts: msg("Fonts") };

  let page = $state<"about" | "licences">("about");
  let copied = $state(false);
  let expanded = $state<string | null>(null);

  async function copyBrew() {
    try {
      await api.copyText(BREW);
      copied = true;
      setTimeout(() => (copied = false), 1800);
    } catch (e) {
      app.showError(e);
    }
  }

  function openLink(url: string) {
    api.openUrl(url).catch((e) => app.showError(e));
  }

  const LICENSE_URLS: Record<string, string> = {
    MIT: "https://opensource.org/license/mit",
    "Apache-2.0": "https://opensource.org/license/apache-2-0",
    ISC: "https://opensource.org/license/isc-license-txt",
    "OFL-1.1": "https://openfontlicense.org",
  };

  let groups = $derived(
    licenses.reduce<{ category: string; items: (LicenseEntry & { key: string })[] }[]>((out, l) => {
      const key = `${l.category}-${l.name}`;
      const last = out[out.length - 1];
      if (last?.category === l.category) last.items.push({ ...l, key });
      else out.push({ category: l.category, items: [{ ...l, key }] });
      return out;
    }, []),
  );

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape") onclose();
  }
</script>

<svelte:window {onkeydown} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="overlay" onclick={onclose}>
  <div class="modal" role="dialog" aria-label={$t("About FLAC Tools")} tabindex="-1" onclick={(e) => e.stopPropagation()}>
    <header>
      {#if page === "licences"}
        <button class="icon-btn" onclick={() => (page = "about")} title={$t("Back")}><ArrowLeft size={16} /></button>
        <h2>{$t("Open source licences")}</h2>
      {:else}
        <h2>{$t("About FLAC Tools")}</h2>
      {/if}
      <button class="icon-btn" onclick={onclose} title={$t("Close")}><X size={16} /></button>
    </header>

    {#if page === "about"}
      <div class="about">
        <img class="logo" src="/logo.svg" alt="" />
        <div class="details">
          <h1 class="wordmark"><span class="flac">FLAC</span><span class="tools">Tools</span></h1>
          <p class="company">Escapement Audio</p>
          <dl>
            <dt>{$t("Version")}</dt>
            <dd>{__APP_VERSION__}</dd>
            <dt>{$t("Licence")}</dt>
            <dd>
              <button class="chip" onclick={() => openLink(LICENSE_URLS.MIT)} title={$t("FLAC Tools is open source under the MIT licence")}>
                <Scale size={12} /> MIT
              </button>
            </dd>
          </dl>
          <div class="links">
            <button class="btn" onclick={() => openLink(GITHUB)} title={GITHUB}>
              <GitBranch size={14} /> {$t("Source on GitHub")}
            </button>
            <button class="btn" onclick={() => openLink(WEBSITE)} title={WEBSITE}>
              <span class="esc-mark" aria-hidden="true"></span> Escapement Audio
            </button>
          </div>
        </div>
      </div>

      <section class="install">
        <h3>{$t("Install the tools")}</h3>
        <p class="muted">{$t("The tools need these command-line programs. With Homebrew installed, paste this into Terminal:")}</p>
        <div class="command">
          <code>{BREW}</code>
          <button class="icon-btn" onclick={copyBrew} title={copied ? $t("Copied") : $t("Copy the command")}>
            {#if copied}<Check size={14} />{:else}<Copy size={14} />{/if}
          </button>
        </div>
      </section>

      <button class="licences-link" onclick={() => (page = "licences")} title={$t("The open source software in FLAC Tools, and its licences")}>
        {$t("Open source licence information")}
      </button>
    {:else}
      <div class="licences">
        {#each groups as g (g.category)}
          <div class="category">{CATEGORIES[g.category] ? $t(CATEGORIES[g.category]) : g.category}</div>
          {#each g.items as l (l.key)}
            <button class="licence" onclick={() => (expanded = expanded === l.key ? null : l.key)} title={$t("Show details")}>
              {#if expanded === l.key}<ChevronDown size={14} />{:else}<ChevronRight size={14} />{/if}
              <span class="name">{l.name}</span>
              <span class="badge">{l.license}</span>
            </button>
            {#if expanded === l.key}
              <dl class="licence-details">
                <dt>{$t("Version")}</dt>
                <dd>{l.version}</dd>
                <dt>{$t("Source")}</dt>
                <dd><button class="link" onclick={() => openLink(l.url)} title={l.url}>{l.url} <ExternalLink size={11} /></button></dd>
                <dt>{$t("Licence")}</dt>
                <dd>
                  {#each l.license.split(" / ") as lic, i}
                    {#if i > 0}{" / "}{/if}
                    {#if LICENSE_URLS[lic]}
                      <button class="link" onclick={() => openLink(LICENSE_URLS[lic])} title={LICENSE_URLS[lic]}>{lic} <ExternalLink size={11} /></button>
                    {:else}{lic}{/if}
                  {/each}
                </dd>
              </dl>
            {/if}
          {/each}
        {/each}
      </div>
    {/if}
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
    width: min(34rem, calc(100vw - 2rem));
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
    gap: 0.4rem;
    padding: 0.6rem 0.75rem 0.6rem 1.25rem;
    border-bottom: 1px solid var(--border);
  }
  h2 {
    flex: 1;
    margin: 0;
    font-size: 1.25rem;
    font-weight: 500;
  }
  .about {
    display: flex;
    gap: 1.5rem;
    padding: 1.5rem;
  }
  .logo {
    width: 7.5rem;
    height: 7.5rem;
    margin: -0.75rem;
    flex: none;
  }
  .details {
    flex: 1;
    min-width: 0;
  }
  .wordmark {
    margin: 0;
    font-size: 1.6rem;
    font-weight: 600;
    letter-spacing: -0.005em;
  }
  .flac {
    color: var(--accent-readable);
  }
  .tools {
    color: var(--text-secondary);
    margin-left: 0.3em;
  }
  .company {
    margin: 0.15rem 0 0.9rem;
    font-family: "Momo Trust Display", "Outfit", sans-serif;
    font-size: 1.05rem;
    color: var(--text-muted);
  }
  dl {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 0.4rem 1rem;
    margin: 0;
    align-items: center;
  }
  dt {
    color: var(--text-muted);
  }
  dd {
    margin: 0;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
    padding: 0.1rem 0.55rem;
    border: none;
    border-radius: 999px;
    background: var(--accent-overlay-2);
    color: var(--accent-readable);
    font-size: 0.8rem;
    font-weight: 600;
  }
  .links {
    display: flex;
    gap: 0.5rem;
    margin-top: 1.1rem;
    flex-wrap: wrap;
  }
  .esc-mark {
    width: 16px;
    height: 16px;
    flex: none;
    background: currentColor;
    -webkit-mask: url("/escapement-logo.png") center / contain no-repeat;
    mask: url("/escapement-logo.png") center / contain no-repeat;
  }
  .install {
    margin: 0 1.5rem 1.25rem;
    padding: 0.9rem 1rem;
    border: 1px solid var(--border);
    border-radius: 0.5rem;
    background: var(--surface-raised);
  }
  .install h3 {
    margin: 0 0 0.3rem;
    font-size: 0.95rem;
    font-weight: 600;
  }
  .install p {
    margin: 0 0 0.6rem;
    font-size: 0.88rem;
  }
  .command {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.35rem 0.35rem 0.35rem 0.75rem;
    border-radius: 0.375rem;
    background: var(--background);
    border: 1px solid var(--border-subtle);
  }
  .command code {
    flex: 1;
    min-width: 0;
    font-family: var(--mono);
    font-size: 0.82rem;
    overflow-x: auto;
    white-space: nowrap;
    user-select: text;
    -webkit-user-select: text;
  }
  .licences-link {
    padding: 0.8rem;
    border: none;
    border-top: 1px solid var(--border);
    background: none;
    color: var(--accent-readable);
  }
  .licences-link:hover {
    background: var(--overlay-1);
  }
  .licences {
    overflow-y: auto;
    flex: 1;
    min-height: 0;
    padding-bottom: 0.5rem;
  }
  .category {
    position: sticky;
    top: 0;
    padding: 0.6rem 1.25rem 0.3rem;
    background: var(--panel-background);
    font-size: 0.7rem;
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    color: var(--text-muted);
  }
  .licence {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.4rem 1.25rem;
    border: none;
    background: none;
    text-align: left;
  }
  .licence:hover {
    background: var(--overlay-1);
  }
  .licence .name {
    flex: 1;
  }
  .badge {
    padding: 0.1rem 0.4rem;
    border-radius: 0.25rem;
    background: var(--overlay-2);
    font-size: 0.7rem;
    color: var(--text-secondary);
  }
  .licence-details {
    padding: 0.4rem 1.25rem 0.7rem 2.6rem;
    background: var(--overlay-1);
    font-size: 0.85rem;
  }
  .link {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0;
    border: none;
    background: none;
    color: var(--accent-readable);
    text-align: left;
    word-break: break-all;
  }
  .link:hover {
    text-decoration: underline;
  }
</style>
