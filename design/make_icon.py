"""Draws the CloseGram app icon ("The Inner Circle"): a gold ring holding a small
constellation, on deep navy. Renders at 4x and scales down for smooth edges.
Usage: python3 design/make_icon.py <output.png>"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024 * 4
NAVY_TOP, NAVY_BOTTOM = (34, 38, 92), (14, 16, 48)
GOLD = (232, 190, 104)

# Background: soft vertical gradient.
bg = Image.new("RGB", (S, S))
px = ImageDraw.Draw(bg)
for y in range(S):
    t = y / (S - 1)
    px.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(NAVY_TOP, NAVY_BOTTOM)))

# Constellation points, as fractions of the canvas. A small group, close together.
pts = [(0.30, 0.52), (0.40, 0.41), (0.51, 0.45), (0.61, 0.52), (0.72, 0.44), (0.66, 0.65)]
pts = [(x * S, y * S) for x, y in pts]
edges = [(0, 1), (1, 2), (2, 3), (3, 4), (3, 5)]
dot_r = [0.030, 0.034, 0.030, 0.038, 0.030, 0.028]

def draw_art(d, scale=1.0):
    cx = cy = S / 2
    r = 0.355 * S
    w = int(0.028 * S * scale)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GOLD, width=w)
    for a, b in edges:
        d.line([pts[a], pts[b]], fill=GOLD, width=int(0.014 * S * scale))
    for (x, y), rr in zip(pts, dot_r):
        rr *= S * scale
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=GOLD)

# Glow: the same art, thicker, blurred and faint, under the crisp art.
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw_art(ImageDraw.Draw(glow), scale=1.6)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.02))
alpha = glow.getchannel("A").point(lambda v: int(v * 0.45))
glow.putalpha(alpha)
bg.paste(glow, (0, 0), glow)

art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw_art(ImageDraw.Draw(art))
bg.paste(art, (0, 0), art)

bg.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(sys.argv[1])  # no alpha: App Store requirement
