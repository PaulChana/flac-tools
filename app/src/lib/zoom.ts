import { getCurrentWebview } from "@tauri-apps/api/webview";

const STEPS = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3];

let level = load();
publish();

function publish() {
  document.documentElement.style.setProperty("--zoom", String(level));
}

function load(): number {
  try {
    const z = Number(localStorage.getItem("zoom"));
    return STEPS.includes(z) ? z : 1;
  } catch {
    return 1;
  }
}

async function set(z: number) {
  level = z;
  publish();
  try {
    localStorage.setItem("zoom", String(z));
  } catch {
  }
  await getCurrentWebview().setZoom(z);
}

export const zoom = {
  restore: () => (level !== 1 ? set(level) : Promise.resolve()),
  in: () => set(STEPS.find((s) => s > level) ?? level),
  out: () => set([...STEPS].reverse().find((s) => s < level) ?? level),
  reset: () => set(1),
};
