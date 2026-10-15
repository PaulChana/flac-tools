import { mount } from "svelte";
import { waitLocale } from "svelte-i18n";
import App from "./App.svelte";
import "./lib/i18n";
import "./lib/tooltip";
import "./app.css";
import { theme } from "./lib/theme.svelte";
import { spacing } from "./lib/spacing.svelte";

theme.apply();
spacing.apply();

await waitLocale().catch(() => {});
const app = mount(App, { target: document.getElementById("app")! });

requestAnimationFrame(() =>
  requestAnimationFrame(() => {
    import("@tauri-apps/api/window").then(({ getCurrentWindow }) => getCurrentWindow().show()).catch(() => {});
  }),
);

export default app;
