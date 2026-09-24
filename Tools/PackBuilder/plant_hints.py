#!/usr/bin/env python3
"""Give every plant a hint about how it looks.

Animals get their hint from the taxonomy — "it's a mammal" — and there is no equivalent
for plants that means anything to a player: "it's a monocot" helps nobody. What does help
is what the picture shows, which is what somebody is comparing four photographs by.

Two parts, and the second is the one that always works. The *form* comes from the
description already fetched — tree, shrub, grass, herb, vine, fern — which covers about a
fifth of them. The *colour* is measured from the photograph itself, which covers all of
them, and is the thing a player is actually looking at.

  python3 Tools/PackBuilder/plant_hints.py
"""

import colorsys, hashlib, json, os, re
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

FORMS = [("a tree", ["tree"]), ("a grass", ["grass", "cereal", "bamboo"]),
         ("a shrub", ["shrub", "bush"]), ("a vine", ["vine", "climber", "creeping"]),
         ("a fern", ["fern"]), ("a herb", ["herb", "herbaceous"])]
# "a flower" is deliberately not here. It matched "bulbous flowering plants", which is how
# an encyclopedia describes garlic — so garlic came out as "a flower, mostly red", wrong
# twice in five words. A hint that is wrong is worse than no hint: it sends somebody to
# the wrong photograph with confidence.

# Hue bands, in the words somebody would use looking at a photograph.
COLOURS = [(20, "red"), (45, "orange"), (70, "yellow"), (170, "green"),
           (260, "blue"), (330, "purple"), (361, "red")]


def dominant_colour(path):
    """The colour most of the picture is, ignoring what is nearly grey."""
    try:
        image = Image.open(path).convert("RGB").resize((64, 64))
    except Exception:
        return None
    counts = {}
    for red, green, blue in image.getdata():
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        # Washed-out and near-black pixels carry no colour worth naming — sky, bark,
        # shadow, an overexposed petal — and counting them makes everything "grey".
        if saturation < 0.25 or value < 0.2:
            continue
        degrees = hue * 360
        name = next(label for edge, label in COLOURS if degrees < edge)
        counts[name] = counts.get(name, 0) + 1
    if not counts:
        return None
    best, count = max(counts.items(), key=lambda pair: pair[1])
    # A colour that barely leads is not a colour anybody would name.
    # A third of the coloured pixels, not an eighth. At the lower bar garlic came out
    # "mostly red" from a few warm pixels in the background of an otherwise white bulb.
    return best if count > 64 * 64 * 0.33 else None


def cache_path(url):
    return os.path.join(ROOT, "build", "vet-cache",
                        hashlib.sha256(url.encode()).hexdigest()[:20] + ".jpg")


COMMON = re.compile(r"^(?:The )?([A-Za-z][A-Za-z' \-]{2,28}?)\s*\(")
# "Zea mays, also known as corn, is a tall stout grass" — the other way encyclopedias say
# it, and common enough that leaving it out halved the coverage.
ALSO_KNOWN = re.compile(
    r"(?:also |commonly |widely )?known as (?:the )?([A-Za-z][A-Za-z' \-]{2,28}?)[,.]", re.I)
NATIVE = re.compile(r"native to ([^.,;()]{3,46})", re.I)


def better_hint(item):
    """What a player can actually use, in order of how much it helps.

    Colour was the first attempt and it was close to useless: almost every plant reads as
    green, so four green photographs each got the hint "it's mostly green", which narrows
    nothing. Worse, it looked like help.

    Almost every plant here is filed under its Latin name — Allium sativum, Cucumis
    sativus — and the encyclopedia opens by giving the name people actually use. That is
    the hint: it does not say which photograph, it says what to look for.
    """
    fact = item.get("fact") or ""
    title = item.get("title") or ""

    # The common name, where the title is Latin and the description leads with it.
    found = COMMON.match(fact)
    if found:
        common = found.group(1).strip()
        if common.lower() not in title.lower() and len(common.split()) <= 3:
            return f"also called {common.lower()}"

    found = ALSO_KNOWN.search(fact)
    if found:
        common = found.group(1).strip()
        if common.lower() not in title.lower() and len(common.split()) <= 3:
            return f"also called {common.lower()}"

    # Failing that, where it grows.
    found = NATIVE.search(fact)
    if found:
        where = found.group(1).strip().rstrip(" and")
        if len(where.split()) <= 6:
            return f"native to {where}"
    return None


def main():
    path = os.path.join(ROOT, "TimeRolls", "Packs", "plants", "plants.pack.json")
    pack = json.load(open(path))
    described = 0
    for item in pack["items"]:
        # Clear first. Skipping a plant used to leave whatever a previous, looser run had
        # written, so garlic kept "a flower, mostly red" after both rules that produced it
        # had been removed.
        item.pop("group", None)
        hint = better_hint(item)
        if hint is None:
            # No colour fallback. A hint that fits every photograph in the round is not a
            # hint, and leaving the card blank is honest about having nothing to add.
            continue
        item["group"] = hint
        described += 1

    with open(path, "w") as handle:
        json.dump(pack, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"{described} of {len(pack['items'])} plants have a hint")
    for item in pack["items"][:6]:
        if item.get("group"):
            print(f"   {item['title'][:28]:<30} It's {item['group']}.")


if __name__ == "__main__":
    main()
