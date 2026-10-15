<script lang="ts">
  import { onMount } from "svelte";
  import { app } from "./state.svelte";
  import { renameItem } from "./actions";
  import { t } from "./i18n";

  let { path, name, isDir }: { path: string; name: string; isDir: boolean } = $props();

  // svelte-ignore state_referenced_locally
  let value = $state(name);
  let input: HTMLInputElement;
  let done = false;

  onMount(() => {
    input.focus();
    const dot = isDir ? -1 : name.lastIndexOf(".");
    input.setSelectionRange(0, dot > 0 ? dot : name.length);
  });

  async function commit() {
    if (done) return;
    done = true;
    if (value.trim() === name || !value.trim()) {
      app.renaming = null;
      return;
    }
    if (!(await renameItem(path, value))) {
      done = false;
      input?.focus();
    }
  }

  function cancel() {
    done = true;
    app.renaming = null;
  }

  function onkeydown(e: KeyboardEvent) {
    e.stopPropagation();
    if (e.key === "Enter") {
      e.preventDefault();
      commit();
    } else if (e.key === "Escape") {
      e.preventDefault();
      cancel();
    }
  }
</script>

<input
  class="rename"
  bind:this={input}
  bind:value
  {onkeydown}
  onblur={commit}
  onclick={(e) => e.stopPropagation()}
  ondblclick={(e) => e.stopPropagation()}
  title={$t("New name — Return to rename, Esc to cancel")}
  spellcheck="false"
  autocomplete="off"
/>

<style>
  .rename {
    width: 100%;
    min-width: 120px;
    height: 20px;
    padding: 0 4px;
    border-radius: 3px;
    color: var(--fg);
  }
</style>
