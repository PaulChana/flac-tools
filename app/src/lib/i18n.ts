import { addMessages, getLocaleFromNavigator, init, locale, register, t } from "svelte-i18n";
import { get, writable } from "svelte/store";
import en from "./locales/en.json";

export { t, locale };

const modules = import.meta.glob<{ default: Record<string, unknown> }>("./locales/*.json");
const codes = Object.keys(modules).map((p) => p.split("/").pop()!.replace(".json", ""));

addMessages("en", en);
for (const code of codes) if (code !== "en") register(code, () => modules[`./locales/${code}.json`]().then((m) => m.default));

function systemLanguage(): string {
  const nav = getLocaleFromNavigator() ?? "en";
  if (codes.includes(nav)) return nav;
  const short = nav.split("-")[0];
  return codes.includes(short) ? short : "en";
}

function saved(): string {
  try {
    return localStorage.getItem("ui-language") ?? "auto";
  } catch {
    return "auto";
  }
}

export const language = writable(saved());

init({ fallbackLocale: "en", initialLocale: saved() === "auto" ? systemLanguage() : saved() });

language.subscribe((lang) => {
  try {
    localStorage.setItem("ui-language", lang);
  } catch {
  }
  locale.set(lang === "auto" ? systemLanguage() : lang);
});

export async function languages(): Promise<{ code: string; label: string }[]> {
  const out = await Promise.all(
    codes.map(async (code) => {
      const data = (await modules[`./locales/${code}.json`]()).default as { meta?: { language?: string } };
      return { code, label: data.meta?.language ?? code };
    }),
  );
  out.sort((a, b) => a.label.localeCompare(b.label));
  return [{ code: "auto", label: "" }, ...out];
}

export function tr(text: string, values?: Record<string, string | number>): string {
  return get(t)(text, values ? { values } : undefined);
}

export const msg = (text: string) => text;
