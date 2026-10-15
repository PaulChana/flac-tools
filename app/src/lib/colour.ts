export interface Rgb {
  r: number;
  g: number;
  b: number;
}

export function parseHex(value: string): Rgb | null {
  const match = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(value.trim());
  if (!match) return null;
  let hex = match[1];
  if (hex.length === 3) {
    hex = hex
      .split('')
      .map((c) => c + c)
      .join('');
  }
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16),
  };
}

export function toHex({r, g, b}: Rgb): string {
  const part = (v: number) =>
    Math.round(Math.min(255, Math.max(0, v)))
      .toString(16)
      .padStart(2, '0');
  return `#${part(r)}${part(g)}${part(b)}`;
}

export function normaliseHex(value: string): string | null {
  const rgb = parseHex(value);
  return rgb ? toHex(rgb) : null;
}

function channelLuminance(value: number): number {
  const c = value / 255;
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

export function relativeLuminance(colour: Rgb): number {
  return (
    0.2126 * channelLuminance(colour.r) +
    0.7152 * channelLuminance(colour.g) +
    0.0722 * channelLuminance(colour.b)
  );
}

export function contrastRatio(a: Rgb, b: Rgb): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const lighter = Math.max(la, lb);
  const darker = Math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

export function mix(from: Rgb, to: Rgb, amount: number): Rgb {
  return {
    r: from.r + (to.r - from.r) * amount,
    g: from.g + (to.g - from.g) * amount,
    b: from.b + (to.b - from.b) * amount,
  };
}

const black: Rgb = {r: 0, g: 0, b: 0};
const white: Rgb = {r: 255, g: 255, b: 255};

export function contrastingText(background: Rgb): Rgb {
  return contrastRatio(background, white) >= contrastRatio(background, black)
    ? white
    : black;
}

export function readableOn(colour: Rgb, background: Rgb, target: number): Rgb {
  if (contrastRatio(colour, background) >= target) return colour;
  const towards = relativeLuminance(background) > 0.5 ? black : white;
  let best = colour;
  for (let step = 1; step <= 20; step++) {
    best = mix(colour, towards, step / 20);
    if (contrastRatio(best, background) >= target) return best;
  }
  return best;
}
