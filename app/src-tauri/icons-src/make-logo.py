# Generates logo.svg: the FLAC Tools icon, a stereo LED level meter.
# Laid out on Apple's macOS icon grid: a 1024 canvas with the 824 rounded
# square inset 100 on each side (transparent around it) and a soft shadow.
# Run: python3 make-logo.py
CANVAS = 1024
INSET = 100
SIZE = CANVAS - 2 * INSET
RADIUS = 185

SEGMENTS = 10
GREEN, AMBER = 6, 2
COLOURS = {"green": "#4fd18b", "amber": "#f2b33d", "red": "#f0524f"}
LEVELS = [(7, 9), (6, 8)]

WIN_X, WIN_Y = INSET + 150, INSET + 132
WIN_W, WIN_H = SIZE - 300, SIZE - 264
COL_W, COL_GAP = 168, 52
SEG_GAP = 16

def colour(i):
    return "green" if i < GREEN else "amber" if i < GREEN + AMBER else "red"

seg_h = (WIN_H - 2 * 36 - (SEGMENTS - 1) * SEG_GAP) / SEGMENTS
cols_w = 2 * COL_W + COL_GAP
x0 = WIN_X + (WIN_W - cols_w) / 2
rects = []
for ch, (level, peak) in enumerate(LEVELS):
    x = x0 + ch * (COL_W + COL_GAP)
    for i in range(SEGMENTS):
        y = WIN_Y + WIN_H - 36 - (i + 1) * seg_h - i * SEG_GAP
        lit = i < level or i == peak - 1
        c = COLOURS[colour(i)]
        if lit:
            rects.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{COL_W}" height="{seg_h:.1f}" rx="7" fill="{c}" filter="url(#glow)"/>')
        else:
            rects.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{COL_W}" height="{seg_h:.1f}" rx="7" fill="{c}" opacity="0.13"/>')

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" width="{CANVAS}" height="{CANVAS}" role="img" aria-label="FLAC Tools">
  <defs>
    <linearGradient id="body" x1="0" y1="{INSET}" x2="0" y2="{INSET + SIZE}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#3a4654"/>
      <stop offset="1" stop-color="#1b2128"/>
    </linearGradient>
    <linearGradient id="window" x1="0" y1="{WIN_Y}" x2="0" y2="{WIN_Y + WIN_H}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#0b0e12"/>
      <stop offset="1" stop-color="#12171d"/>
    </linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.35"/>
    </filter>
    <filter id="glow" x="-20%" y="-60%" width="140%" height="220%">
      <feGaussianBlur stdDeviation="6" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect x="{INSET}" y="{INSET}" width="{SIZE}" height="{SIZE}" rx="{RADIUS}" fill="url(#body)" filter="url(#shadow)"/>
  <rect x="{INSET + 2}" y="{INSET + 2}" width="{SIZE - 4}" height="{SIZE - 4}" rx="{RADIUS - 2}" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="3"/>
  <rect x="{WIN_X}" y="{WIN_Y}" width="{WIN_W}" height="{WIN_H}" rx="56" fill="url(#window)"/>
  <rect x="{WIN_X}" y="{WIN_Y}" width="{WIN_W}" height="{WIN_H}" rx="56" fill="none" stroke="#000" stroke-opacity="0.5" stroke-width="4"/>
  {chr(10).join("  " + r for r in rects).strip()}
</svg>
'''
open("logo.svg", "w").write(svg)
print("wrote logo.svg")
