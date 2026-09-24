#!/usr/bin/env python3
"""Build the Famous Artworks pack from Wikimedia Commons, public-domain files only.

A faithful photograph of a flat, public-domain painting carries no new copyright — that
is the {{PD-Art}} position Commons works to, following Bridgeman v. Corel — so the picture
inherits the painting's status. This takes only files Commons reports as public domain,
and records the licence, the credit and the file's own page so all three travel with the
copy, as the other packs do.

Two things it deliberately does not do. It does not touch sculpture or architecture: a
photograph of a three-dimensional work is the photographer's own, and that is a different
licence question entirely. And it does not decide anything about the two entries whose
names in the spreadsheet do not match how Commons catalogues them — it writes them out
for somebody to look at.

  python3 Tools/PackBuilder/build_artworks.py           # look, write nothing
  python3 Tools/PackBuilder/build_artworks.py --apply   # write the pack
"""

import argparse, json, os, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AGENT = "TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) python-urllib/3"

# The paintings themselves live in subjects_artworks.py, which is the file to edit to
# grow the pack. Here we only keep the handful of notes about entries where the name in
# Fraidun's spreadsheet is not the name Commons files the work under.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from subjects_artworks import ARTWORKS

NOTES = {
    "whistlers-mother":
        "the spreadsheet calls it Whistler's Mother; Commons files it as "
        "Arrangement in Grey and Black No. 1",
    "creation-of-adam":
        "the spreadsheet asks for the whole Sistine Chapel ceiling, which Commons holds as "
        "separate panels and as photographs of the architecture — this takes the one panel "
        "everybody knows, and a photograph of the ceiling as a space would be the "
        "photographer's own work rather than PD-Art",
}

PUBLIC_DOMAIN = ("public domain", "pd-", "cc0", "no restrictions")

# Words that mean "not the painting itself". Commons holds a great deal of material *about*
# famous paintings — a mural of the Mona Lisa, a reproduction hanging in a château, a
# gasometer exhibition named after Primavera — and a search ranks those alongside the work.
# Each of these is also a photograph somebody took of a physical thing, so the PD-Art
# reasoning would not cover it even if the subject is old.
# Commons is multilingual, and a Dutch "Reproductie van Whistler's Mother" reads as a
# perfectly good match to a list of English words. The foreign spellings are here because
# that file was the one the builder picked.
NOT_THE_WORK = (
    "reproduction", "reproductie", "reproduktion", "reproduccion", "reproducción",
    "reproduction de", "kopie", "kopia", "nachbildung", "d'apres", "d'après", "naar ",
    "nach ", "copia", "imitation", "forgery", "variant", "study for", "sketch after", "replica", "copy", "after ", "mosaic", "tapestry", "engraving",
    "statue", "sculpture", "exhibition", "graffiti", "mural", "street", "lego",
    "cake", "costume", "parody", "pastiche", "sticker", "stamp", "banknote", "poster",
    "screenshot", "cosplay", "tattoo", "facade", "interior", "visitors", "tourists",
    "panorama", "plaque", "waxwork", "souvenir", "gasometer", "wikipedia", "logo",
    "illustration of", "diagram", "animation", "cover", "postcard", "playing card",
)

SMALL_WORDS = {"the", "of", "a", "an", "at", "in", "on", "and", "no", "le", "la", "du",
               "sur", "der", "die", "das", "el", "il"}


def distinctive(title):
    """The words in a painting's name that identify it."""
    cleaned = "".join(ch if ch.isalnum() or ch.isspace() else " " for ch in fold(title))
    return [w for w in cleaned.split() if w not in SMALL_WORDS and len(w) > 2]


def fold(text):
    """Lower case with the accents taken off, because Commons spells Gericault both ways."""
    stripped = unicodedata.normalize("NFKD", text.lower())
    return "".join(ch for ch in stripped if not unicodedata.combining(ch))


def surname(artist):
    words = fold(artist).replace("-", " ").split()
    # "Pieter Bruegel the Elder" is filed under Bruegel, not under Elder.
    while words and words[-1] in ("elder", "younger", "the"):
        words.pop()
    return words[-1] if words else ""


def relevance(file_title, title, artist):
    """How well a Commons file name matches the painting we asked for, or None for no.

    The old rule — take the biggest public-domain file the search returned — assumed the
    search only returns the painting. It does not, and the biggest file is often the least
    relevant one, because a photograph of a building is larger than a scan of a canvas.
    """
    name = fold(file_title)
    if any(word in name for word in NOT_THE_WORK):
        return None
    # The artist has to be named in the file. This throws away plenty of correct files —
    # the canonical Arnolfini Portrait scan does not say "van Eyck" anywhere — but the
    # alternative is worse in a way that matters here. Matching on the title alone lets
    # "Two people kissing in a park" answer to The Kiss, and a round that presents the
    # wrong painting as a famous one teaches the player something false. A work we fail
    # to find gets printed for somebody to look at; a wrong one just ships.
    if surname(artist) not in name:
        return None
    # And the title has to be there too, or we would take whichever Klimt happened to be
    # the largest file and call it The Kiss.
    parts = [w for w in "".join(ch if ch.isalnum() else " " for ch in name).split()]
    matched = sum(1 for w in distinctive(title) if any(p.startswith(w) for p in parts))
    if not matched:
        return None
    return matched


FAILED = {"calls": 0}


def api(params, tries=4):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(
        {**params, "format": "json"})
    wait = 3.0
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception as error:
            if attempt == tries - 1:
                print(f"    ! {type(error).__name__} {error}")
                FAILED["calls"] += 1
                return None
            time.sleep(wait)
            wait *= 2
    FAILED["calls"] += 1
    return None


def strip_html(text):
    out, inside = [], False
    for ch in text or "":
        if ch == "<":
            inside = True
        elif ch == ">":
            inside = False
        elif not inside:
            out.append(ch)
    return " ".join("".join(out).split())


def best_file(term, title, artist):
    """The public-domain file that best matches this painting.

    Returns the file, or a string saying why there is none — "throttled" is not the same
    answer as "no public-domain file exists", and reporting them as one is how a rate limit
    ends up recorded as a fact about the world.
    """
    titles = []
    for phrasing in (f"{term} filetype:bitmap", f"{artist} {title} filetype:bitmap"):
        found = api({"action": "query", "list": "search", "srsearch": phrasing,
                     "srnamespace": 6, "srlimit": 14})
        if found is None:
            return "the lookup failed — Commons refused the request, so nothing is known"
        for hit in found.get("query", {}).get("search", []):
            if hit["title"] not in titles:
                titles.append(hit["title"])
        time.sleep(2.0)
    if not titles:
        return "no file of any licence matches that name"
    titles = titles[:40]
    time.sleep(2.5)
    info = api({"action": "query", "titles": "|".join(titles), "prop": "imageinfo",
                "iiprop": "url|size|extmetadata", "iiurlwidth": 1400})
    if info is None:
        return "the lookup failed — Commons refused the request, so nothing is known"
    candidates = []
    for page in info.get("query", {}).get("pages", {}).values():
        image = (page.get("imageinfo") or [{}])[0]
        if not image:
            continue
        meta = image.get("extmetadata", {})
        licence = strip_html((meta.get("LicenseShortName", {}) or {}).get("value", ""))
        if not any(word in licence.lower() for word in PUBLIC_DOMAIN):
            continue
        name = page["title"].lower()
        # Skip details, crops and frames: the round shows the painting, not a corner of it.
        if any(word in name for word in ("detail", "crop", "frame", "signature", "verso")):
            continue
        fit = relevance(page["title"], title, artist)
        if fit is None:
            continue
        candidates.append({
            "fit": fit,
            "file": page["title"],
            "url": image.get("thumburl") or image.get("url"),
            "pixels": image.get("width", 0) * image.get("height", 0),
            "license": licence,
            "licenseURL": strip_html((meta.get("LicenseUrl", {}) or {}).get("value", "")),
            "credit": strip_html((meta.get("Artist", {}) or {}).get("value", ""))[:140],
            "sourceURL": image.get("descriptionurl", ""),
        })
    if not candidates:
        return "files matched the name but none is both public domain and the work itself"
    return max(candidates, key=lambda c: (c["fit"], c["pixels"]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rounds", type=int, default=1,
                        help="passes to make; each one fills the gaps the last left")
    parser.add_argument("--rest", type=int, default=240,
                        help="seconds between passes, to let the rate limit clear")
    args = parser.parse_args()
    for pass_number in range(args.rounds):
        if pass_number:
            print(f"\n--- resting {args.rest}s, then pass {pass_number + 1} "
                  f"of {args.rounds} ---\n", flush=True)
            time.sleep(args.rest)
        FAILED["calls"] = 0
        missing = one_pass(args)
        if not missing:
            print("\nevery painting sourced — stopping early")
            break


def one_pass(args):

    # Keep what a previous run already sourced. Commons allows a limited number of
    # lookups in a window, and this needs about twenty — so a single run reliably loses
    # one painting to a refusal, and it is a different one each time. Running twice with
    # a gap fills the gaps rather than starting over and losing a different one.
    path = os.path.join(ROOT, "TimeRolls", "Packs", "famous-artworks",
                        "famous-artworks.pack.json")
    already = {}
    if os.path.exists(path):
        for item in json.load(open(path)).get("items", []):
            already[item["id"]] = item

    items, look_at, refused_in_a_row = [], [], 0
    for slug, title, term, artist, year in ARTWORKS:
        note = NOTES.get(slug)
        if f"famous-artworks-{slug}" in already:
            items.append(already[f"famous-artworks-{slug}"])
            print(f"{title:<32} already sourced", flush=True)
            if note:
                look_at.append((title, note))
            continue
        file = best_file(term, title, artist)
        if isinstance(file, str):
            print(f"{title:<32} UNRESOLVED — {file}", flush=True)
            look_at.append((title, file))
            # Once Commons starts refusing, it refuses everything for a while. Grinding
            # through the rest of the list only collects the same refusal fifty times and
            # writes fifty paintings off as unfindable, so stop and come back rested.
            refused_in_a_row = refused_in_a_row + 1 if "refused" in file else 0
            if refused_in_a_row >= 4:
                print("\n  Commons is refusing everything now — ending this pass early")
                break
            continue
        refused_in_a_row = 0
        print(f"{title:<32} {file['license']:<16} {file['file'][:44]}", flush=True)
        if note:
            look_at.append((title, note))
        items.append({
            "id": f"famous-artworks-{slug}",
            "title": title,
            "objectTags": [],
            "remoteURL": file["url"],
            "year": year,
            "month": 6,
            "credit": file["credit"] or artist,
            "source": "Wikimedia Commons",
            "sourceURL": file["sourceURL"],
            "license": file["license"],
            "licenseURL": file["licenseURL"] or
                          "https://commons.wikimedia.org/wiki/Commons:Reuse_of_PD-Art_photographs",
            "isResizedCopy": True,
            "fact": f"{title} was painted by {artist}, around {year}.",
        })
        time.sleep(2.5)

    print(f"\n{len(items)} of {len(ARTWORKS)} sourced as public domain"
          + (f" ({FAILED['calls']} lookups were refused by Commons)" if FAILED["calls"] else ""))
    if look_at:
        print("\nfor somebody to look at:")
        for title, why in look_at:
            print(f"  · {title}: {why}")

    pack = {
        "formatVersion": 1,
        "themes": ["objects"],
        "id": "famous-artworks",
        "title": "Famous Artworks",
        "blurb": "Paintings almost everybody has seen.",
        "license": "Public domain (PD-Art)",
        "namedSubjectPrompt": "Which one shows {name}?",
        "items": items,
    }
    if args.apply:
        folder = os.path.join(ROOT, "TimeRolls", "Packs", "famous-artworks")
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, "famous-artworks.pack.json")
        with open(path, "w") as out:
            json.dump(pack, out, indent=2, ensure_ascii=False)
            out.write("\n")
        print(f"\nwritten to {path}")
    else:
        print("\nnothing written — pass --apply")
    return len(ARTWORKS) - len(items)


if __name__ == "__main__":
    main()
