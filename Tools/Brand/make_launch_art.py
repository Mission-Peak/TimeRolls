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
  LaunchScene.imageset/launch-scene.jpg
  LaunchSky.colorset/Contents.json
"""

import json, math, os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

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


def film_strip(draw, width, centre, half, frames):
    """Film as on the icon: two sprocket rails with open frames between them.

    It was a solid band with a row of light holes down each edge, which at launch-screen
    size read as a road across the hills. The icon's film is open — the hills show
    through each frame — so this draws the rails and the bars between frames, and leaves
    the frames themselves empty.
    """
    xs = np.arange(width)
    dy = np.gradient(centre)
    norm = np.sqrt(1 + dy ** 2)
    nx, ny = -dy / norm, 1 / norm

    def offset(x, d):
        return (x + nx[x] * d, centre[x] + ny[x] * d)

    rail = half * 0.30
    for inner, outer in ((-half + rail, -half), (half - rail, half)):
        edge_a = [offset(x, outer) for x in xs]
        edge_b = [offset(x, inner) for x in xs]
        draw.polygon(edge_a + edge_b[::-1], fill=FILM)

    # Sprocket holes down each rail.
    step = rail * 1.6
    hole_w, hole_h = rail * 0.55, rail * 0.50
    x = step / 2
    while x < width:
        i = int(x)
        angle = math.atan(dy[i])
        for d in (-half + rail / 2, half - rail / 2):
            cx, cy = offset(i, d)
            corners = []
            for px, py in ((-hole_w, -hole_h), (hole_w, -hole_h), (hole_w, hole_h), (-hole_w, hole_h)):
                rx = px * math.cos(angle) - py * math.sin(angle)
                ry = px * math.sin(angle) + py * math.cos(angle)
                corners.append((cx + rx / 2, cy + ry / 2))
            draw.polygon(corners, fill=SKY_LOW)
        x += step

    # The bars between frames, square to the strip.
    frame = width / frames
    bar = rail * 0.55
    x = frame * 0.35
    while x < width:
        i = int(x)
        tx, ty = 1 / norm[i], dy[i] / norm[i]
        a, b = offset(i, -half + rail * 0.9), offset(i, half - rail * 0.9)
        draw.polygon([(a[0] - tx * bar, a[1] - ty * bar), (a[0] + tx * bar, a[1] + ty * bar),
                      (b[0] + tx * bar, b[1] + ty * bar), (b[0] - tx * bar, b[1] - ty * bar)],
                     fill=FILM)
        x += frame


def diffuse(a, iters, k, lam=0.2):
    """Smooth flat areas while keeping edges (Perona-Malik): compression noise goes, the
    lines stay."""
    a = a.copy()
    for _ in range(iters):
        ds = [np.roll(a, s, ax) - a for s in (-1, 1) for ax in (0, 1)]
        a += lam * sum(np.exp(-((np.abs(d).mean(-1, keepdims=True)) / k) ** 2) * d for d in ds)
    return a


def sharp_art(icon, out):
    """The icon's picture at `out` pixels square, sharp. See `sharp`."""
    # A few pixels off each edge: the source has a thin light line along its top.
    return sharp(icon.crop((6, 6, 1018, 1018)), out, out, film=(84, 89, 84))


def sharp(src, out_w, out_h, film):
    """A flat-colour picture at `out_w` by `out_h`, sharp, from a small compressed source.

    Stretched as it is, the source goes soft and blotchy on a phone and worse on an iPad:
    it is 1024 pixels with compression noise. The picture is flat colours, so each colour
    area is found, scaled up with smooth edges and filled with one clean colour. The film
    strip's sprocket holes and outlines are too small for that, so there the picture
    itself is used, cleaned and sharpened, and the two are blended along the strip.
    """
    a = diffuse(np.asarray(src, np.float32), 30, 6.0)
    px = a.reshape(-1, 3)
    K = 12
    rng = np.random.default_rng(2)
    sample = px[rng.choice(len(px), 150000, replace=False)]
    # k-means++ style init
    cent = [sample[0]]
    for _ in range(K - 1):
        d = np.min([((sample - c) ** 2).sum(1) for c in cent], 0)
        cent.append(sample[rng.choice(len(sample), p=d / d.sum())])
    cent = np.array(cent)
    for _ in range(40):
        lab = ((sample[:, None] - cent[None]) ** 2).sum(-1).argmin(1)
        cent = np.array([sample[lab == k].mean(0) if (lab == k).any() else cent[k] for k in range(K)])
    labels = np.concatenate([((px[i:i+150000, None] - cent[None]) ** 2).sum(-1).argmin(1)
                             for i in range(0, len(px), 150000)]).reshape(a.shape[:2])
    # One colour per thing in the picture. The darkest shades are all the outline; greys
    # within a few levels of each other are the one film strip, mottled by compression; and a
    # colour with almost no pixels is the halo compression leaves along an edge, so those
    # pixels go to whichever real colour is nearest.
    counts0 = np.bincount(labels.ravel(), minlength=K)
    group = np.arange(K)
    dark = [k for k in range(K) if cent[k].mean() < 65]
    for k in dark: group[k] = dark[0]
    for i in range(K):
        for j in range(i):
            if group[i] == i and np.abs(cent[i] - cent[j]).max() < 12: group[i] = group[j]
    halo = [k for k in range(K) if counts0[k] < 0.008 * labels.size and k not in dark]
    for k in halo:
        others = [j for j in range(K) if j not in halo]
        group[k] = group[others[int(np.argmin([((cent[k] - cent[j]) ** 2).sum() for j in others]))]]
    labels = group[labels]
    for g in set(group.tolist()):
        members = [k for k in range(K) if group[k] == g and k not in halo]
        cent[g] = np.average(cent[members], axis=0, weights=counts0[members])
    # Specks: any pixel whose 5x5 neighbourhood mostly disagrees takes the local majority.
    counts = np.stack([ndimage.uniform_filter((labels == k).astype(np.float32), 5) for k in range(K)])
    labels = np.where(counts.max(0) > 0.6, counts.argmax(0), labels)
    ss = 2; bw, bh = out_w * ss, out_h * ss
    best = np.full((bh, bw), -1, np.float32); arg = np.zeros((bh, bw), np.uint8)
    for k in range(K):
        m = np.asarray(Image.fromarray((labels == k).astype(np.float32)).resize((bw, bh), Image.BICUBIC))
        m = ndimage.gaussian_filter(m, sigma=bw / src.width * 0.9)
        upd = m > best; best[upd] = m[upd]; arg[upd] = k
    rgb = cent.clip(0, 255).astype(np.uint8)[arg]
    flat = Image.fromarray(rgb).resize((out_w, out_h), Image.LANCZOS)
    # The film strip's sprocket holes and outlines are too small to rebuild from colour
    # areas: there, the photograph itself, cleaned of compression and sharpened.
    film = int(group[int(np.argmin([abs(c - np.array(film)).max() for c in cent]))])
    strip = np.isin(labels, [film, group[dark[0]]] if dark else [film])
    strip = ndimage.binary_closing(strip, iterations=4)
    strip = ndimage.binary_dilation(strip, iterations=2).astype(np.float32)
    mask = Image.fromarray(ndimage.gaussian_filter(strip, 1.2)).resize((out_w, out_h), Image.BICUBIC)
    mask = Image.fromarray((np.asarray(mask).clip(0, 1) * 255).astype(np.uint8))
    photo = Image.fromarray(a.clip(0, 255).astype(np.uint8)).resize((out_w, out_h), Image.LANCZOS)
    photo = Image.fromarray(diffuse(np.asarray(photo, np.float32), 10, 5.0).clip(0, 255).astype(np.uint8))
    photo = photo.filter(ImageFilter.UnsharpMask(radius=4, percent=80, threshold=1))
    return Image.composite(photo, flat, mask)


def launch_wide(source_path, width=2752, height=2064):
    """The launch screen for screens wider than they are tall, from Hanna's design.

    The design (Tools/Brand/launch-wide-source.jpg) is a wide meadow — hills across the
    whole width, the sun, two film strips, pines and round trees — with the name written
    in the sky on the left. The name is taken out of the picture here and drawn by
    LaunchSplash.swift instead, so it is crisp at any size; the picture is rebuilt sharp
    at iPad resolution; and sky is added above it, because the design is 16:9 and an iPad
    on its side is 4:3. Wider screens crop that added sky off the top.
    """
    art = Image.open(source_path).convert("RGB")
    a = np.asarray(art).copy()
    # Paint the sky back over the name, row by row, from a strip of plain sky beside it.
    for y in range(195, 395):
        a[y, 70:645] = np.median(a[y, 655:720], axis=0)
    art = Image.fromarray(a)
    scene_h = round(width * art.height / art.width)
    picture = sharp(art, width, scene_h, film=(79, 86, 71))
    sky = tuple(int(v) for v in np.asarray(picture)[2:8, :].reshape(-1, 3).mean(0))
    canvas = Image.new("RGB", (width, height), sky)
    canvas.paste(picture, (0, height - scene_h))
    return canvas


def launch_scene(icon, width=2400, height=5215):
    """The icon's own picture across the bottom of the screen, under a tall sky of its colour.

    The launch scene used to be a separate painting of the icon's hills, sun and film
    strip. Hanna asked for the icon itself, with the name written in the sky above it, so
    this is the icon square at the full width of the screen and the sky carried on up
    above it. LaunchSplash.swift writes "Time Rolls by Mission Peak" in that sky.
    """
    # A few pixels off each edge (in sharp_art): the source has a thin light line along
    # its top. Drawn at iPad resolution, so it is sharp everywhere.
    art = sharp_art(icon, width)
    img = Image.new("RGB", (width, height), SKY)
    top = height - width
    img.paste(art, (0, top))
    # The icon's sky meets the plain sky without a seam: blend across a band.
    band = width // 8
    sky = Image.new("RGB", (width, band), tuple(int(v) for v in np.array(art.crop((0, 0, width, 4))).reshape(-1, 3).mean(0)))
    fade = Image.linear_gradient("L").resize((width, band)).transpose(Image.FLIP_TOP_BOTTOM)
    img.paste(sky, (0, top), fade)
    upper = Image.new("RGB", (width, top), sky.getpixel((0, 0)))
    img.paste(upper, (0, 0))
    return img


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    icon = Image.open(sys.argv[1]).convert("RGB")
    if icon.size != (1024, 1024):
        icon = icon.resize((1024, 1024), Image.LANCZOS)

    folder = os.path.join(ASSETS, "AppIcon.appiconset")
    for name in ("icon.png", "icon-dark.png", "icon-tinted.png"):
        icon.save(os.path.join(folder, name), optimize=True)

    folder = os.path.join(ASSETS, "LaunchWide.imageset")
    os.makedirs(folder, exist_ok=True)
    launch_wide(os.path.join(os.path.dirname(os.path.abspath(__file__)), "launch-wide-source.jpg")
                ).save(os.path.join(folder, "launch-wide.jpg"), quality=90, optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "launch-wide.jpg", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")

    launch_scene(icon).save(os.path.join(ASSETS, "LaunchScene.imageset", "launch-scene.jpg"),
                        quality=90, optimize=True)

    # The static launch screen is this colour alone, the sky the scene fades in under.
    sky = Image.open(os.path.join(ASSETS, "LaunchScene.imageset", "launch-scene.jpg")).getpixel((10, 10))
    colour = {"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
        "red": "0x%02X" % sky[0], "green": "0x%02X" % sky[1], "blue": "0x%02X" % sky[2],
        "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ASSETS, "LaunchSky.colorset", "Contents.json"), "w") as f:
        json.dump(colour, f, indent=2)
        f.write("\n")
    print("icon, launch scene and launch colour written")


if __name__ == "__main__":
    main()
