#!/usr/bin/env python3
"""Lay a built pack out as one labelled sheet, so somebody can look at it.

Every automatic check in build_pack.py is a check on *text*: the licence line, the file
title, the date field. None of them can tell that Wikipedia's picture for Honus Wagner is
a chewing-gum card, that the top search result for Jack Dempsey is a photograph of a
crowd, or that the article on Roger Bannister leads with a photograph of him at seventy.
Those only show up when you look, and the rule this app is built to is that a public
photograph earns its place by being recognisable. So looking is a build step:

    python3 contact_sheet.py sports entertainment --out /tmp/check.jpg
"""

import argparse, io, json, os, sys, time, urllib.request

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("This needs Pillow: pip3 install Pillow")

PACKS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "..", "TimeRolls", "Packs")
AGENT = "TimeRolls-pack-review/1.0 (https://attimis.co)"
CELL = (250, 285)
THUMB = 240
COLUMNS = 6


def load(pack_id):
    path = os.path.join(PACKS, pack_id, f"{pack_id}.pack.json")
    manifest = json.load(open(path))
    return [(item["year"], item["title"], item["remoteURL"]) for item in manifest["items"]]


def fetch(entry):
    """One at a time, unhurried. Commons rate-limits a fast loop over a few dozen files
    and answers 429 for most of them, which looks exactly like a pack full of dead links."""
    year, title, url = entry
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            image = Image.open(io.BytesIO(urllib.request.urlopen(request, timeout=60).read()))
            image = image.convert("RGB")
            image.thumbnail((THUMB, THUMB))
            return year, title, image
        except Exception as error:
            if attempt == 2:
                print(f"  ! {title}: {error}")
                return year, title, None
            time.sleep(4 * (attempt + 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("packs", nargs="+", help="pack ids, e.g. sports entertainment")
    parser.add_argument("--out", default="pack-review.jpg")
    args = parser.parse_args()

    entries = [entry for pack in args.packs for entry in load(pack)]
    fetched = []
    for entry in entries:
        fetched.append(fetch(entry))
        time.sleep(0.4)

    rows = (len(fetched) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (COLUMNS * CELL[0], rows * CELL[1]), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
    except OSError:
        font = ImageFont.load_default()

    for index, (year, title, image) in enumerate(fetched):
        x, y = (index % COLUMNS) * CELL[0], (index // COLUMNS) * CELL[1]
        if image:
            sheet.paste(image, (x + (THUMB - image.width) // 2 + 5, y + 5))
        else:
            draw.text((x + 10, y + 100), "COULD NOT FETCH", fill="red", font=font)
        draw.text((x + 6, y + 252), f"{year}  {title[:26]}", fill="black", font=font)

    sheet.save(args.out, quality=88)
    missing = sum(1 for _, _, image in fetched if image is None)
    print(f"\n{args.out} — {len(fetched)} photographs, {missing} could not be fetched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
