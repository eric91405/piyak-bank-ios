#!/usr/bin/env python3
"""Compose the iOS / watchOS app icons from the transparent chick render.

python3 scripts/app_icon/make_icons.py /tmp/piyak-icon-master.png

Writes (all 1024x1024 PNG, no alpha channel):
  PiyakBank/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png         default
  PiyakBank/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_dark.png    iOS 18+ dark
  PiyakBank/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_tinted.png  iOS 18+ tinted (grayscale)
  PiyakWatch Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png  circular-safe framing
Needs Pillow and NumPy. The master comes from render_chick.py.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SIZE = 1024
# The master is rendered with a 2.6-unit wide frame. The iOS icon uses the central
# 2.22 units (same view as a 50 mm lens); the watch keeps a little more room because
# watchOS masks the icon to a circle.
MASTER_FRAME, IOS_FRAME, WATCH_FRAME = 2.6, 2.22, 2.5

# Brand purple (PB.C.accent #6653BE) as a soft vertical gradient with a glow behind the head.
LIGHT = dict(top='#9C8AEE', bottom='#6553C2', glow=(0.5, 0.34, 0.62, '#C4B8FA', 0.45))
DARK = dict(top='#3B3274', bottom='#191731', glow=(0.5, 0.34, 0.62, '#6A5AC8', 0.42))
SPARKLES = [  # (x, y, radius, colour, opacity) in unit coordinates
    (0.155, 0.20, 0.050, '#FFFFFF', 0.95),
    (0.86, 0.30, 0.034, '#FFF3C4', 0.90),
    (0.10, 0.44, 0.022, '#FFFFFF', 0.70),
]
WATCH_SPARKLES = [(0.20, 0.25, 0.046, '#FFFFFF', 0.95), (0.82, 0.31, 0.032, '#FFF3C4', 0.90)]


def rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def background(top, bottom, glow):
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / (SIZE - 1)
    t = (y * y * (3 - 2 * y)) * 0.35 + y * 0.65
    img = rgb(top)[None, None] * (1 - t[..., None]) + rgb(bottom)[None, None] * t[..., None]
    cx, cy, r, col, strength = glow
    g = (np.clip(1 - np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r, 0, 1) ** 2 * strength)[..., None]
    img = img * (1 - g) + rgb(col)[None, None] * g
    return Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), 'RGB')


def sparkle_layer(sparkles, opacity=1.0, ss=4):
    s = SIZE * ss
    stars = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    glow = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    for cx, cy, r, col, a in sparkles:
        c = tuple(int(v) for v in rgb(col))
        a *= opacity
        pts = []
        for k in range(96):  # concave four-point star |x|^p + |y|^p = 1, p < 1
            ang = 2 * math.pi * k / 96
            ca, sa = math.cos(ang), math.sin(ang)
            rr = 1.0 / (abs(ca) ** 0.55 + abs(sa) ** 0.55) ** (1 / 0.55)
            pts.append(((cx + r * rr * ca) * s, (cy + r * rr * sa) * s))
        ImageDraw.Draw(stars).polygon(pts, fill=c + (int(255 * a),))
        gr = r * 0.55 * s
        ImageDraw.Draw(glow).ellipse([cx * s - gr, cy * s - gr, cx * s + gr, cy * s + gr], fill=c + (int(110 * a),))
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.012))
    glow.alpha_composite(stars)
    return glow.resize((SIZE, SIZE), Image.LANCZOS)


def crop(master, frame, dy=0.0):
    w = master.width
    c = int(round(w * frame / MASTER_FRAME))
    ox = (w - c) // 2
    oy = int(round((w - c) / 2 + dy * c))
    return master.crop((ox, oy, ox + c, oy + c)).resize((SIZE, SIZE), Image.LANCZOS)


def compose(fg, bg, sparkles, sparkle_opacity=1.0, fg_gain=1.0):
    base = bg.convert('RGBA')
    base.alpha_composite(sparkle_layer(sparkles, sparkle_opacity))
    if fg_gain != 1.0:
        arr = np.asarray(fg).astype(np.float32)
        arr[..., :3] *= fg_gain
        fg = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGBA')
    base.alpha_composite(fg)
    return base.convert('RGB')


def tinted(fg):
    """Grayscale artwork on black; iOS applies the person's tint colour to it.
    The channel mix keeps the yellow head brighter than both the mint hoodie and the
    orange beak/cheeks, so the face still reads once the colour is gone."""
    a = np.asarray(fg).astype(np.float32) / 255
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    gray = 0.40 * r + 0.55 * g + 0.05 * b
    gray = np.clip((gray - 0.10) / 0.82, 0, 1) ** 1.15
    # Orange/pink parts (beak, cheeks) have a lower green/red ratio than the yellow head;
    # shade them down so they stay visible without colour.
    warm = np.clip((0.80 - g / np.maximum(r, 1e-3)) / 0.10, 0, 1) * (r > 0.55)
    gray *= 1 - 0.28 * warm
    lum = gray * a[..., 3]
    img = Image.fromarray((lum * 255 + 0.5).astype(np.uint8), 'L')
    img = img.filter(ImageFilter.UnsharpMask(radius=6, percent=60, threshold=2)).convert('RGBA')
    img.alpha_composite(sparkle_layer([(x, y, r, '#FFFFFF', o) for x, y, r, _, o in SPARKLES], 0.8))
    return img.convert('L').convert('RGB')


def save(img, path):
    assert img.mode == 'RGB' and img.size == (SIZE, SIZE)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)


def main():
    master = Image.open(sys.argv[1] if len(sys.argv) > 1 else '/tmp/piyak-icon-master.png').convert('RGBA')
    ios_fg = crop(master, IOS_FRAME)
    watch_fg = crop(master, WATCH_FRAME, dy=-0.056)

    ios = ROOT / 'PiyakBank/Assets.xcassets/AppIcon.appiconset'
    save(compose(ios_fg, background(**LIGHT), SPARKLES), ios / 'AppIcon_1024.png')
    save(compose(ios_fg, background(**DARK), SPARKLES, sparkle_opacity=0.75, fg_gain=0.93), ios / 'AppIcon_1024_dark.png')
    save(tinted(ios_fg), ios / 'AppIcon_1024_tinted.png')

    def entry(name, appearance=None):
        e = {'filename': name, 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}
        if appearance:
            e['appearances'] = [{'appearance': 'luminosity', 'value': appearance}]
        return e
    contents = {'images': [entry('AppIcon_1024.png'), entry('AppIcon_1024_dark.png', 'dark'),
                           entry('AppIcon_1024_tinted.png', 'tinted')],
                'info': {'author': 'xcode', 'version': 1}}
    (ios / 'Contents.json').write_text(json.dumps(contents, indent=2, sort_keys=True).replace('": ', '" : ') + '\n')

    watch = ROOT / 'PiyakWatch Watch App/Assets.xcassets/AppIcon.appiconset'
    save(compose(watch_fg, background(**LIGHT), WATCH_SPARKLES), watch / 'AppIcon_1024.png')
    print('Wrote iOS (default, dark, tinted) and watchOS app icons.')


if __name__ == '__main__':
    main()
