#!/usr/bin/env python3
"""
Generate the Signoff app icon set at all macOS sizes.

Design principles (anti-"AI slop"):
  - One colour accent (amber) against deep ink-black. No neon, no cyan-magenta.
  - A hand-crafted pen-stroke "S" — not parametric, not circular, not a shape.
  - Neural Engine motif is architectural (ordered tile array), not decorative
    "floating dots in a sphere" cliché.
  - Restrained layers: background, grid, stroke, paper texture, single rim light.
  - Must read as a mark at 16×16.
"""

import math
import random
from pathlib import Path
from PIL import Image, ImageDraw

# ── Palette ────────────────────────────────────────────────────────────────
INK_DEEP   = (10, 9, 7)
INK_MID    = (24, 22, 19)
INK_WARM   = (32, 28, 24)
AMBER      = (212, 160, 23)
AMBER_HOT  = (255, 195, 60)
AMBER_SHAD = (160, 121, 18)
NODE_IDLE  = (58, 52, 40)
NODE_ACTV  = (155, 120, 50)
TRACE      = (48, 44, 40)
WHITE_     = (255, 255, 255)
BORDER     = (46, 42, 34)

OUT_DIR = Path("Resources/Assets.xcassets/AppIcon.appiconset")
SIZES = {
    "icon_16x16.png":      16,   "icon_16x16@2x.png":   32,
    "icon_32x32.png":      32,   "icon_32x32@2x.png":   64,
    "icon_128x128.png":   128,   "icon_128x128@2x.png": 256,
    "icon_256x256.png":   256,   "icon_256x256@2x.png": 512,
    "icon_512x512.png":   512,   "icon_512x512@2x.png": 1024,
    "icon_1024.png":     1024,
}

# ── helpers ────────────────────────────────────────────────────────────────
def col(c, a=1.0):
    """Return c with alpha scaled [0,1]."""
    return (*c, int(max(0, min(255, round(a * 255)))))

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def lerp_f(a, b, t):
    return a + (b - a) * t

def hand_stroke_path(cx, cy, s):
    """
    Hand-crafted 'S' path. Cubic bezier segments sampled finely,
    centroid at （cx, cy). Panning: (-1..+1, -1..+1) scaled by `s`.
    """
    def pt(xn, yn):
        return (cx + xn * s, cy + yn * s)

    pts = []

    # entry flick (top-left → top-centre)
    for t in (i / 28 for i in range(29)):
        x = lerp_f(-0.29, -0.03, t)
        y = lerp_f(-0.78, -0.70, t)
        pts.append(pt(x * (1 + 0.06 * t), y))

    # top loop (rightward)
    for t in (i / 42 for i in range(1, 43)):
        x = (-0.09 + 0.27*t + 0.12*t*t - 0.23*t*t*t) * 1.02
        y = (-0.68 - 0.14*t + 0.36*t*t - 0.29*t*t*t) * 0.98
        pts.append(pt(x, y))

    # upper crossing (left)
    for t in (i / 28 for i in range(1, 29)):
        x = (0.26 - 0.47*t + 0.20*t*t + 0.14*t*t*t) * 1.03
        y = (-0.30 - 0.25*t + 0.09*t*t - 0.05*t*t*t) * 0.95
        pts.append(pt(x, y))

    # belly — fullest part (right-down)
    for t in (i / 52 for i in range(1, 53)):
        x = (0.03 + 0.44*t - 0.21*t*t - 0.11*t*t*t) * 1.02
        y = (-0.05 + 0.78*t - 0.32*t*t + 0.04*t*t*t) * 0.94
        pts.append(pt(x, y))

    # lower crossing (left-up)
    for t in (i / 28 for i in range(1, 29)):
        x = (0.33 - 0.30*t - 0.12*t*t + 0.22*t*t*t) * 1.02
        y = (0.52 - 0.13*t - 0.50*t*t + 0.30*t*t*t) * 0.93
        pts.append(pt(x, y))

    # terminal tail (right-down)
    for t in (i / 32 for i in range(1, 33)):
        x = 0.12 + 0.16*t + 0.24*t*t*t
        y = 0.38 + 0.44*t + 0.04*t*t - 0.02*t*t*t
        pts.append(pt(x, y))

    return pts


def render(size):
    rs = max(1, int(size * 0.225))
    c_x, c_y = size / 2, size / 2 + size * 0.018
    stk = size * 0.38

    # ──── mask ─────────────────────────────────────────────────────────────
    mask_img = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask_img).rounded_rectangle(
        [0, 0, size, size], radius=rs, fill=255)

    # ──── 1. ink ground ─────────────────────────────────────────────────────
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    diag = math.sqrt(c_x**2 + c_y**2)
    step = max(1, size // 200)
    for y in range(0, size, step):
        for x in range(0, size, step):
            dst = math.sqrt((x - c_x)**2 + (y - c_y)**2) / diag
            base = lerp(INK_DEEP, INK_MID, dst * 0.55)
            warm = max(0, (1 - dst * 1.15))
            clr = lerp(base, INK_WARM, warm * 0.18)
            d.rectangle([x, y, x + step, y + step], fill=clr)

    # Paper grain
    grain = int(size * size * 0.09)
    for _ in range(grain):
        gx, gy = random.randint(0, size-1), random.randint(0, size-1)
        r, gv, bv, _ = bg.getpixel((gx, gy))
        dv = random.choice([0, 1, 2, 3])
        bg.putpixel((gx, gy), (max(0, r-dv), max(0, gv-dv), max(0, bv-dv), 255))

    # Vignette
    vig = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vig)
    step_v = max(1, size // 160)
    for y in range(0, size, step_v):
        for x in range(0, size, step_v):
            dst = math.sqrt((x - c_x)**2 + (y - c_y)**2) / diag
            if dst > 0.42:
                a_ = int(min(255, (dst - 0.42) * 0.42 * 255))
                vd.rectangle([x, y, x+step_v, y+step_v], fill=(0, 0, 0, a_))
    vig.putalpha(mask_img)
    bg = Image.alpha_composite(bg, vig)

    # ──── 2 ─────────────────────────────────────────────────────────────────
    grid = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    margin = int(size * 0.18)
    usable = size - 2 * margin
    cols_n, rows_n = 7, 5
    nodes = []
    for row_i in range(rows_n):
        shift = usable / (cols_n * 2.6) if row_i % 2 == 1 else 0
        for col_i in range(cols_n):
            nx = margin + usable * (col_i + 0.75) / (cols_n + 0.5) + shift
            ny = margin + usable * (row_i + 0.65) / (rows_n + 0.3)
            nodes.append((nx, ny))

    for i_a, a_ in enumerate(nodes):
        for j_a, b_ in enumerate(nodes):
            if i_a >= j_a:
                continue
            if math.hypot(b_[0]-a_[0], b_[1]-a_[1]) < size * 0.24:
                gd.line([a_, b_], fill=col(TRACE, 0.08), width=1)

    for nx, ny in nodes:
        hot = (((int(nx * 13.7) ^ int(ny * 42.3)) % 53) & 1) == 0
        colour = col(NODE_ACTV if hot else NODE_IDLE, 0.38 if hot else 0.12)
        r = max(1.5, size * 0.0048) if hot else max(1.0, size * 0.0030)
        gd.ellipse([nx - r, ny - r, nx + r, ny + r], fill=colour)
    grid.putalpha(mask_img)

    # ──── 3. Signature S stroke ──────────────────────────────────────────────
    stroke_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stroke_img)
    pts = hand_stroke_path(c_x, c_y, stk)

    for w_scale, clr in [
        (0.30, col((18, 14, 9), 0.18)),
        (0.20, col(AMBER_SHAD,  0.06)),
        (0.135, col(AMBER,      0.115)),
        (0.07, col(AMBER_HOT,  0.195)),
        (0.028, col(AMBER_HOT, 0.34)),
        (0.010, col(AMBER_HOT, 0.48)),
    ]:
        sd.line(pts, fill=clr, width=max(1, int(round(stk * w_scale))), joint="curve")

    # ──── 4. underline flourish ─────────────────────────────────────────────
    uy = int(c_y + stk * 0.59)
    ul = int(c_x - stk * 0.38)
    ur = int(c_x + stk * 0.38)
    for w_scale, am in [
        (0.09, 0.04), (0.055, 0.09), (0.028, 0.18), (0.011, 0.26),
    ]:
        sd.line([(ul, uy), (ur, uy)],
                fill=col(AMBER if w_scale > 0.05 else AMBER_HOT, am),
                width=max(1, int(round(stk * w_scale))))

    stroke_img.putalpha(mask_img)

    # ──── 5. compose ────────────────────────────────────────────────────────
    out = Image.alpha_composite(bg, grid)
    out = Image.alpha_composite(out, stroke_img)

    dd2 = ImageDraw.Draw(out)
    dd2.rounded_rectangle([0, 0, size-1, size-1],
                          radius=rs, outline=col(BORDER, 0.38), width=1)

    # ──── 6. top-rim glass ─────────────────────────────────────────────────
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(0, int(size * 0.36)):
        t = 1.0 - max(0, (y - size * 0.04) / (size * 0.29))
        dg = ImageDraw.Draw(gloss)
        dg.rectangle(
            [int(size * 0.125), y, int(size * 0.875), y + 1],
            fill=col(WHITE_, max(0, t * 0.055)))
    gloss.putalpha(mask_img)
    out = Image.alpha_composite(out, gloss)

    return out


def main():
    random.seed(9)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for fn, sz in SIZES.items():
        print(f"  {fn} … ({sz}×{sz})")
        img = render(sz)
        img.save(str(OUT_DIR / fn))
    print("  Done — all icon sizes generated.")

if __name__ == "__main__":
    main()