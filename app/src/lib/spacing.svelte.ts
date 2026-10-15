export const DEFAULT_ROW_PADDING = 0.2;
export const MIN_ROW_PADDING = 0;
export const MAX_ROW_PADDING = 1.3;
const STEP = 0.1;

function load(): number {
  try {
    const saved = parseFloat(localStorage.getItem("row-padding") ?? "");
    return Number.isFinite(saved) ? clamp(saved) : DEFAULT_ROW_PADDING;
  } catch {
    return DEFAULT_ROW_PADDING;
  }
}

function clamp(n: number) {
  return Math.min(MAX_ROW_PADDING, Math.max(MIN_ROW_PADDING, Math.round(n * 10) / 10));
}

class Spacing {
  rowPadding = $state(load());

  set(n: number) {
    this.rowPadding = clamp(n);
    try {
      localStorage.setItem("row-padding", String(this.rowPadding));
    } catch {
    }
    this.apply();
  }

  increase = () => this.set(this.rowPadding + STEP);
  reduce = () => this.set(this.rowPadding - STEP);
  reset = () => this.set(DEFAULT_ROW_PADDING);

  apply() {
    document.documentElement.style.setProperty("--row-padding", `${this.rowPadding}rem`);
  }
}

export const spacing = new Spacing();
