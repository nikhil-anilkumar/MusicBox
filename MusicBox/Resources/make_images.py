"""Generates the app icon (gold vinyl on black) and launch images. Usage: make_images.py <outdir>"""
import math, sys
from PIL import Image, ImageDraw

out = sys.argv[1]
S = 1024                      # master resolution; downsampled for anti-aliasing

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

GOLD_DARK = (110, 78, 18)
GOLD_MID = (196, 152, 52)
GOLD_LIGHT = (255, 232, 150)

def vinyl_master():
    c = S / 2
    R = S * 0.455             # record radius
    LABEL = S * 0.165         # centre label radius
    HOLE = S * 0.022          # spindle hole
    px = []
    for y in range(S):
        dy = y + 0.5 - c
        for x in range(S):
            dx = x + 0.5 - c
            r = math.hypot(dx, dy)
            if r > R:
                px.append((0, 0, 0)); continue
            th = math.atan2(dy, dx)
            # Two opposed light reflections sweeping across the grooves (classic vinyl sheen).
            sheen = math.cos(2 * (th + math.pi / 4)) ** 2
            sheen = sheen ** 3
            if r <= HOLE:
                px.append((0, 0, 0)); continue
            if r <= LABEL:
                # Black centre label with a fine gold ring and a soft gold inner disc.
                if r > LABEL - S * 0.012:
                    px.append(lerp(GOLD_MID, GOLD_LIGHT, sheen)); continue
                if r < S * 0.055:
                    px.append(lerp(GOLD_DARK, GOLD_MID, 0.5 + 0.5 * sheen)); continue
                px.append((14, 12, 10)); continue
            # Gold record surface: base tone + fine grooves + sheen + darker rim.
            groove = 0.5 + 0.5 * math.sin(r * 0.9)
            band = 1.0 if (S * 0.30 < r < S * 0.305 or S * 0.40 < r < S * 0.404) else 0.0   # track gaps
            t = 0.35 + 0.55 * sheen - 0.10 * groove - 0.25 * band
            t = max(0.0, min(1.0, t))
            col = lerp(GOLD_DARK, GOLD_MID, min(1, t * 1.6)) if t < 0.62 else lerp(GOLD_MID, GOLD_LIGHT, (t - 0.62) / 0.38)
            if r > R - S * 0.012:     # bevelled outer edge
                col = lerp(col, GOLD_DARK, 0.6)
            px.append(col)
    im = Image.new("RGB", (S, S))
    im.putdata(px)
    return im

master = vinyl_master()
for name, size in [("Icon.png", 57), ("Icon@2x.png", 114), ("Icon-Small.png", 29), ("Icon-Small@2x.png", 58)]:
    master.resize((size, size), Image.LANCZOS).save(f"{out}/{name}")
master.resize((512, 512), Image.LANCZOS).save(f"{out}/../icon-preview.png")

def launch(w, h):  # full-screen; black status + nav bar over white, black tab bar at the bottom
    im = Image.new("RGB", (w, h), (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, 64 * w // 320], fill=(24, 24, 24))
    d.rectangle([0, h - 49 * w // 320, w, h], fill=(24, 24, 24))
    return im

launch(320, 480).save(f"{out}/Default.png")
launch(640, 960).save(f"{out}/Default@2x.png")
launch(640, 1136).save(f"{out}/Default-568h@2x.png")
