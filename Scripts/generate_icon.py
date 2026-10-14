"""Draws LumaGrid's original app icon: a glowing 3x3 tile grid with a central prism star.
Usage: python3 Scripts/generate_icon.py <output.png> [size]
App Store icons must be opaque, so the image is RGB with no alpha."""
import math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
S = int(sys.argv[2]) if len(sys.argv) > 2 else 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def hexrgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

# Background: deep ink radial-ish vertical gradient
bg = Image.new("RGB", (S, S))
top, bottom = hexrgb("#2A2466"), hexrgb("#0B0A1F")
px = bg.load()
for y in range(S):
    for x in range(S):
        d = math.hypot(x - S * 0.5, y - S * 0.42) / (S * 0.75)
        px[x, y] = lerp(top, bottom, min(1, d))

colors = ["#5FE3C0", "#4CC9F0", "#B69CFF",
          "#FF8A7A", None, "#F5CF6B",
          "#B69CFF", "#5FE3C0", "#4CC9F0"]
grid = S * 0.62
gap = S * 0.035
tile = (grid - 2 * gap) / 3
x0 = (S - grid) / 2
y0 = (S - grid) / 2
radius = tile * 0.22
center_color = hexrgb("#F4F1FF")

glow = Image.new("RGB", (S, S), (0, 0, 0))
gd = ImageDraw.Draw(glow)
tiles = Image.new("RGBA", (S, S), (0, 0, 0, 0))
td = ImageDraw.Draw(tiles)
for i, c in enumerate(colors):
    r, col = divmod(i, 3)
    x = x0 + col * (tile + gap); y = y0 + r * (tile + gap)
    rgb = center_color if c is None else hexrgb(c)
    box = [x, y, x + tile, y + tile]
    gd.rounded_rectangle(box, radius, fill=tuple(int(v * (1.0 if c is None else 0.6)) for v in rgb))
    td.rounded_rectangle(box, radius, fill=rgb + (255,))
    # Subtle top highlight for depth
    hl = [x + tile * 0.08, y + tile * 0.06, x + tile * 0.92, y + tile * 0.32]
    td.rounded_rectangle(hl, radius * 0.7, fill=(255, 255, 255, 46))

glow = glow.filter(ImageFilter.GaussianBlur(S * 0.045))
# Additive glow behind the tiles
img = Image.fromarray(np.clip(np.asarray(bg, dtype=np.int32) + np.asarray(glow, dtype=np.int32), 0, 255).astype(np.uint8))
img.paste(tiles, (0, 0), tiles)

# Prism star on the centre tile
d = ImageDraw.Draw(img)
cx, cy = S / 2, S / 2
outer, inner = tile * 0.36, tile * 0.13
pts = []
for k in range(8):
    ang = -math.pi / 2 + k * math.pi / 4
    rr = outer if k % 2 == 0 else inner
    pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
d.polygon(pts, fill=hexrgb("#6C4CF0"))

img.convert("RGB").save(out, "PNG")
print("wrote", out, img.size)
