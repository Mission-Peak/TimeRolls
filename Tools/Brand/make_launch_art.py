#!/usr/bin/env python3
"""The app icon, the launch logo and the launch scene, from one icon image.

    python3 Tools/Brand/make_launch_art.py path/to/icon-1024.png

The icon is the source of truth for the palette, so the launch screen is drawn from it
rather than painted separately: the static launch screen iOS shows is the logo on the
icon's own sky colour, and the scene that fades in around it is the same sky, the same
clay sun, the same sage hills and the same charcoal film strip. The old launch painting
was sky blue and grass green from the first palette, and stayed that way after the app
did not.

Writes into TimeRolls/Assets.xcassets:
  AppIcon.appiconset/icon.png (and the dark and tinted slots, the same image for now)
  LaunchMark.imageset/launch-logo-{iphone@2x,iphone@3x,ipad@1x,ipad@2x}.png
  LaunchScene.imageset/launch-scene.jpg
  LaunchSky.colorset/Contents.json
"""

import json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "TimeRolls", "Assets.xcassets")

# Taken from the icon itself.
SKY = (0xE5, 0xD0, 0xCD)
SKY_LOW = (0xEC, 0xDB, 0xD6)       # a touch lighter towards the horizon
SUN = (0xC1, 0x9B, 0x86)
HILL_FAR = (0x9A, 0xA8, 0x8A)
HILL_MID = (0x70, 0x80, 0x63)
HILL_NEAR = (0x55, 0x6B, 0x4E)
HILL_FRONT = (0x40, 0x57, 0x3D)
FILM = (0x57, 0x5C, 0x5A)
TREE = (0x8A, 0x74, 0x66)
TRUNK = (0x58, 0x4B, 0x3B)

# LaunchSplash.swift: the logo is drawn at these sizes, with 14% room for its shadow.
LOGO_POINTS = {"iphone": 210, "ipad": 380}
SHADOW_ROOM = 0.14
# LaunchSplash.horizonInPicture — where the hilltops sit in the scene, as a share of it.
HORIZON = 0.698


def squircle_mask(size):
    """Apple's icon shape, near enough: a rounded rectangle at 22.37% of the side."""
    scale = 4
    mask = Image.new("L", (size * scale, size * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * scale - 1, size * scale - 1),
                                           radius=int(size * scale * 0.2237), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def launch_logo(icon, logo_px):
    canvas = round(logo_px * (1 + 2 * SHADOW_ROOM))
    inset = (canvas - logo_px) // 2
    art = icon.resize((logo_px, logo_px), Image.LANCZOS)
    mask = squircle_mask(logo_px)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    # A soft shadow under the logo, the way it sits on a home screen.
    shadow = Image.new("L", (canvas, canvas), 0)
    shadow.paste(mask, (inset, inset + round(logo_px * 0.03)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(logo_px * 0.045)).point(lambda v: v * 0.30)
    out.paste((40, 45, 38, 255), (0, 0), shadow)
    out.paste(art, (inset, inset), mask)
    return out


# MARK: - The scene

def curve(width, base, waves):
    """y for every x: a base line plus a few gentle sine waves."""
    xs = np.arange(width)
    y = np.full(width, float(base))
    for amp, period, phase in waves:
        y += amp * np.sin(2 * math.pi * xs / period + phase)
    return y


def fill_below(draw, ys, colour, height):
    pts = [(0, height)] + [(x, float(y)) for x, y in enumerate(ys)] + [(len(ys) - 1, height)]
    draw.polygon(pts, fill=colour)


def tree(draw, x, ground, h):
    w = h * 0.55
    draw.rectangle((x - h * 0.045, ground - h * 0.42, x + h * 0.045, ground), fill=TRUNK)
    draw.ellipse((x - w / 2, ground - h, x + w / 2, ground - h * 0.32), fill=TREE)


def film_strip(draw, width, centre, half, holes):
    """A band along `centre` (a y for every x) with sprocket holes down both edges."""
    xs = np.arange(width)
    dy = np.gradient(centre)
    norm = np.sqrt(1 + dy ** 2)
    nx, ny = -dy / norm, 1 / norm
    top = [(x + nx[x] * -half, centre[x] + ny[x] * -half) for x in xs]
    bottom = [(x + nx[x] * half, centre[x] + ny[x] * half) for x in xs]
    draw.polygon(top + bottom[::-1], fill=FILM)
    step = width / holes
    hole_w, hole_h = half * 0.30, half * 0.44
    for i in range(holes + 1):
        x = int(min(width - 1, i * step + step / 2))
        angle = math.atan(dy[x])
        for side in (-1, 1):
            cx = x + nx[x] * side * half * 0.62
            cy = centre[x] + ny[x] * side * half * 0.62
            corners = []
            for px, py in ((-hole_w, -hole_h), (hole_w, -hole_h), (hole_w, hole_h), (-hole_w, hole_h)):
                rx = px * math.cos(angle) - py * math.sin(angle)
                ry = px * math.sin(angle) + py * math.cos(angle)
                corners.append((cx + rx / 2, cy + ry / 2))
            draw.polygon(corners, fill=SKY_LOW)


def launch_scene(width=1290, height=2803):
    s = 2  # drawn at twice the size, then reduced, for smooth edges
    W, H = width * s, height * s
    img = Image.new("RGB", (W, H), SKY)
    draw = ImageDraw.Draw(img)

    # Sky: the launch colour at the top, a shade lighter at the horizon.
    horizon = HORIZON * H
    for y in range(int(horizon)):
        t = max(0.0, (y / horizon - 0.45) / 0.55)
        draw.line((0, y, W, y), fill=tuple(int(a + (b - a) * t) for a, b in zip(SKY, SKY_LOW)))

    # The clay sun, low, half behind the far hills — as on the icon.
    # Off to the right and well below "by Mission Peak", so the line never sits on it.
    r = W * 0.17
    cx, cy = W * 0.85, horizon + H * 0.02
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=SUN)

    far = curve(W, horizon + H * 0.012, [(H * 0.010, W * 1.3, 0.4), (H * 0.004, W * 0.45, 1.1)])
    fill_below(draw, far, HILL_FAR, H)
    for x, h in ((0.12, 0.050), (0.22, 0.040), (0.86, 0.046)):
        tree(draw, W * x, far[int(W * x)] + H * 0.004, H * h)

    mid = curve(W, horizon + H * 0.055, [(H * 0.018, W * 1.1, 2.2), (H * 0.006, W * 0.5, 0.3)])
    fill_below(draw, mid, HILL_MID, H)

    # The film strip, winding across the hills.
    strip = curve(W, horizon + H * 0.085, [(H * 0.030, W * 1.05, 0.9), (H * 0.008, W * 0.5, 2.0)])
    film_strip(draw, W, strip, H * 0.017, holes=38)

    near = curve(W, horizon + H * 0.145, [(H * 0.020, W * 1.2, 4.0), (H * 0.006, W * 0.55, 1.4)])
    fill_below(draw, near, HILL_NEAR, H)
    tree(draw, W * 0.80, near[int(W * 0.80)] + H * 0.006, H * 0.085)

    front = curve(W, horizon + H * 0.215, [(H * 0.018, W * 1.4, 0.2)])
    fill_below(draw, front, HILL_FRONT, H)

    return img.resize((width, height), Image.LANCZOS)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    icon = Image.open(sys.argv[1]).convert("RGB")
    if icon.size != (1024, 1024):
        icon = icon.resize((1024, 1024), Image.LANCZOS)

    folder = os.path.join(ASSETS, "AppIcon.appiconset")
    for name in ("icon.png", "icon-dark.png", "icon-tinted.png"):
        icon.save(os.path.join(folder, name), optimize=True)

    folder = os.path.join(ASSETS, "LaunchMark.imageset")
    for idiom, scales in (("iphone", (2, 3)), ("ipad", (1, 2))):
        for scale in scales:
            logo = launch_logo(icon, LOGO_POINTS[idiom] * scale)
            logo.save(os.path.join(folder, f"launch-logo-{idiom}@{scale}x.png"), optimize=True)

    launch_scene().save(os.path.join(ASSETS, "LaunchScene.imageset", "launch-scene.jpg"),
                        quality=90, optimize=True)

    colour = {"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
        "red": "0x%02X" % SKY[0], "green": "0x%02X" % SKY[1], "blue": "0x%02X" % SKY[2],
        "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ASSETS, "LaunchSky.colorset", "Contents.json"), "w") as f:
        json.dump(colour, f, indent=2)
        f.write("\n")
    print("icon, launch logo, launch scene and launch colour written")


if __name__ == "__main__":
    main()
