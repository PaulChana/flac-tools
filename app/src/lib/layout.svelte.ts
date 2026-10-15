function load<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(`layout.${key}`);
    return raw === null ? fallback : (JSON.parse(raw) as T);
  } catch {
    return fallback;
  }
}

function save(key: string, value: unknown) {
  try {
    localStorage.setItem(`layout.${key}`, JSON.stringify(value));
  } catch {
  }
}

class Layout {
  showLeft = $state(load("showLeft", true));
  showRight = $state(load("showRight", true));
  showBottom = $state(load("showBottom", false));
  leftWidth = $state(load("leftWidth", 260));
  rightWidth = $state(load("rightWidth", 390));
  bottomHeight = $state(load("bottomHeight", 240));

  toggle(panel: "Left" | "Right" | "Bottom", show?: boolean) {
    const key = `show${panel}` as const;
    this[key] = show ?? !this[key];
    save(key, this[key]);
  }

  resize(size: "leftWidth" | "rightWidth" | "bottomHeight", value: number) {
    const limits = { leftWidth: [180, 520], rightWidth: [300, 640], bottomHeight: [120, 700] } as const;
    const [min, max] = limits[size];
    this[size] = Math.round(Math.max(min, Math.min(max, value)));
  }

  saveSizes() {
    save("leftWidth", this.leftWidth);
    save("rightWidth", this.rightWidth);
    save("bottomHeight", this.bottomHeight);
  }
}

export const layout = new Layout();

export function startDrag(
  e: PointerEvent,
  size: "leftWidth" | "rightWidth" | "bottomHeight",
  sign: 1 | -1,
) {
  if (e.button !== 0) return;
  e.preventDefault();
  const vertical = size === "bottomHeight";
  const start = vertical ? e.clientY : e.clientX;
  const startSize = layout[size];
  document.body.classList.add(vertical ? "row-resizing" : "col-resizing");
  const move = (ev: PointerEvent) => {
    const now = vertical ? ev.clientY : ev.clientX;
    layout.resize(size, startSize + sign * (now - start));
  };
  const up = () => {
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
    document.body.classList.remove("row-resizing", "col-resizing");
    layout.saveSizes();
  };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
}
