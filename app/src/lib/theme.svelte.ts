import { contrastingText, mix, normaliseHex, parseHex, readableOn, toHex } from "./colour";
import { msg } from "./i18n";

export type PaletteId = "super-dark" | "dark" | "light" | "super-light";

export interface Palette {
  id: PaletteId;
  label: string;
  type: "dark" | "light";
  background: string;
  panel: string;
  border: string;
  text: string;
  defaultAccent: string;
}

export const PALETTES: Palette[] = [
  { id: "super-dark", label: msg("Super dark"), type: "dark", background: "#0f1012", panel: "#191a1c", border: "#3a3d42", text: "#ede0ce", defaultAccent: "#92b55f" },
  { id: "dark", label: msg("Dark"), type: "dark", background: "#23201c", panel: "#312d27", border: "#5c5449", text: "#edebe6", defaultAccent: "#94c7b6" },
  { id: "light", label: msg("Light"), type: "light", background: "#faf4ed", panel: "#e1dbd5", border: "#b8b3ae", text: "#575279", defaultAccent: "#d7827e" },
  { id: "super-light", label: msg("Super light"), type: "light", background: "#ffffff", panel: "#f2f2f2", border: "#bfbfbf", text: "#000000", defaultAccent: "#007acc" },
];

export const ACCENTS: { label: string; hex: string }[] = [
  { label: msg("Red"), hex: "#e5484d" }, { label: msg("Coral"), hex: "#f2695c" }, { label: msg("Clay"), hex: "#d7827e" },
  { label: msg("Rust"), hex: "#cc6633" }, { label: msg("Orange"), hex: "#f2761a" }, { label: msg("Amber"), hex: "#e8a33d" },
  { label: msg("Gold"), hex: "#d9a326" }, { label: msg("Sand"), hex: "#c2a878" }, { label: msg("Bronze"), hex: "#a9836b" },
  { label: msg("Olive"), hex: "#9a9d4a" }, { label: msg("Moss"), hex: "#92b55f" }, { label: msg("Lime"), hex: "#a8cc47" },
  { label: msg("Green"), hex: "#40b869" }, { label: msg("Sage"), hex: "#94c7b6" }, { label: msg("Mint"), hex: "#4dc9a0" },
  { label: msg("Jade"), hex: "#0ca678" }, { label: msg("Teal"), hex: "#12a594" }, { label: msg("Cyan"), hex: "#0fb5c4" },
  { label: msg("Sky"), hex: "#22a7e8" }, { label: msg("Azure"), hex: "#007acc" }, { label: msg("Blue"), hex: "#3b82f6" },
  { label: msg("Steel"), hex: "#5f8fa8" }, { label: msg("Slate"), hex: "#7b8794" }, { label: msg("Indigo"), hex: "#5c7cfa" },
  { label: msg("Violet"), hex: "#7c5cff" }, { label: msg("Lavender"), hex: "#a99ae0" }, { label: msg("Purple"), hex: "#9775fa" },
  { label: msg("Plum"), hex: "#a05ea8" }, { label: msg("Magenta"), hex: "#cc5de8" }, { label: msg("Pink"), hex: "#f06595" },
  { label: msg("Rose"), hex: "#e93d82" }, { label: msg("Crimson"), hex: "#d6336c" },
];

function load(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function save(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
  }
}

function initialPalette(): PaletteId {
  const saved = load("palette");
  if (PALETTES.some((p) => p.id === saved)) return saved as PaletteId;
  return matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

class Theme {
  palette = $state<PaletteId>(initialPalette());
  customAccent = $state<string | null>(normaliseHex(load("accent") ?? ""));

  get current(): Palette {
    return PALETTES.find((p) => p.id === this.palette) ?? PALETTES[1];
  }

  get accent(): string {
    return this.customAccent ?? this.current.defaultAccent;
  }

  setPalette(id: PaletteId) {
    this.palette = id;
    save("palette", id);
    this.apply();
  }

  setAccent(hex: string | null) {
    this.customAccent = hex === null ? null : normaliseHex(hex);
    save("accent", this.customAccent);
    this.apply();
  }

  apply() {
    const p = this.current;
    const root = document.documentElement;
    const set = (name: string, value: string) => root.style.setProperty(name, value);
    set("--background", p.background);
    set("--panel-background", p.panel);
    set("--border", p.border);
    set("--text", p.text);
    set("--accent", this.accent);
    const accent = parseHex(this.accent);
    const background = parseHex(p.background);
    if (accent && background) {
      set("--accent-contrast", toHex(contrastingText(accent)));
      set("--accent-readable", toHex(readableOn(accent, background, 4.5)));
      set("--accent-quiet", toHex(mix(accent, background, p.type === "dark" ? 0.72 : 0.82)));
    }
    root.dataset.themeType = p.type;
    root.dataset.palette = p.id;
    root.style.colorScheme = p.type;
  }
}

export const theme = new Theme();
