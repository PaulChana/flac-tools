export type MenuEntry =
  | { text: string; action: () => void; enabled?: boolean; checked?: boolean; danger?: boolean; tip?: string }
  | { text: string; items: MenuEntry[]; enabled?: boolean }
  | "separator";

interface Anchor {
  left: number;
  top: number;
  bottom: number;
}

class MenuState {
  entries = $state<MenuEntry[] | null>(null);
  x = $state(0);
  y = $state(0);
  anchor = $state<Anchor | null>(null);

  close() {
    this.entries = null;
  }
}

export const menu = new MenuState();

let last: { x: number; y: number; button: HTMLElement | null; context: boolean } = {
  x: 0,
  y: 0,
  button: null,
  context: false,
};
if (typeof window !== "undefined") {
  const remember = (context: boolean) => (e: MouseEvent) => {
    const button = (e.target as HTMLElement | null)?.closest?.("button") ?? null;
    last = { x: e.clientX, y: e.clientY, button, context };
  };
  window.addEventListener("pointerdown", remember(false), true);
  window.addEventListener("contextmenu", remember(true), true);
}

export async function contextMenu(entries: MenuEntry[]) {
  if (!last.context && last.button?.isConnected) {
    const r = last.button.getBoundingClientRect();
    menu.x = r.left;
    menu.y = r.bottom + 4;
    menu.anchor = { left: r.left, top: r.top, bottom: r.bottom };
  } else {
    menu.x = last.x;
    menu.y = last.y;
    menu.anchor = null;
  }
  menu.entries = entries;
}
