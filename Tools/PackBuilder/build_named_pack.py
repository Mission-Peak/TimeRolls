#!/usr/bin/env python3
"""Source a pack of named subjects from Wikimedia Commons.

The Famous Artworks builder proved the shape: name the thing you want, search Commons, and
take a file only when it is plainly that thing. This is the same tool with the specifics
lifted out, so people, places, instruments, spacecraft and events can all use it.

Two rules do the work, and both exist because the first version of this got them wrong:

**The file has to name the subject.** Taking the largest public file a search returns gave
a photograph of a German gasometer for "Primavera". So the subject's distinguishing word —
a surname, a landmark's name — must appear in the file's own title.

**And it has to be the subject itself.** Commons holds enormous amounts of material
*about* famous things: statues of them, graves, plaques, murals, stamps, streets named
after them. Every one of those is a photograph somebody took of a physical object, which
is a different licence question and, more to the point, not a picture of the person.

  python3 Tools/PackBuilder/build_named_pack.py --pack famous-faces
  python3 Tools/PackBuilder/build_named_pack.py --pack famous-faces --apply --rounds 12
"""

import argparse, importlib.util, json, os, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")

# Commons and public is the bar. CC BY and CC BY-SA need attribution, which every pack
# already carries per item, and the credits screen shows it.
ALLOWED = ("public domain", "pd-", "cc0", "no restrictions", "cc by", "cc-by", "attribution")

# Not the subject: a photograph of a statue, a grave or a plaque is a picture of an object
# somebody made, not of the person or place named on it.
NOT_THE_SUBJECT = (
    "statue", "sculpture", "bust of", "memorial", "grave", "tomb", "headstone", "plaque",
    "stamp", "postage", "banknote", "coin", "medal", "signature", "autograph", "mural",
    "graffiti", "waxwork", "madame tussauds", "street", "avenue", "boulevard", "school",
    "hospital", "library named", "museum of", "birthplace", "house", "monument", "replica",
    "reproduction", "cosplay", "impersonator", "tribute", "lego", "cake", "costume",
    "map of", "diagram", "logo", "poster for", "book cover", "sheet music", "letter from",
    "home", "residence", "birthplace of", "childhood home", "exhibit", "exhibition",
)

SMALL_WORDS = {"the", "of", "a", "an", "at", "in", "on", "and", "de", "da", "van", "von", "jr"}


def fold(text):
    stripped = unicodedata.normalize("NFKD", text.lower())
    return "".join(ch for ch in stripped if not unicodedata.combining(ch))


def key_words(name):
    cleaned = "".join(ch if ch.isalnum() or ch.isspace() else " " for ch in fold(name))
    return [w for w in cleaned.split() if w not in SMALL_WORDS and len(w) > 2]


def relevance(file_title, name):
    """How well a file matches the subject, or None for "not this"."""
    # Drop the "File:" prefix and the extension, or every position below is off by one and
    # the name-leads-the-title test measures the wrong thing.
    title = fold(file_title)
    title = title.removeprefix("file:").rsplit(".", 1)[0]
    # Whole words, not substrings. "Jailhouse Rock" contains "house" and is a photograph of
    # Elvis; "Presley family home" contains the same word and is a photograph of a building.
    # Ordered, because where the name sits in the title matters below; the set is only
    # for the whole-word rejection test.
    parts = "".join(ch if ch.isalnum() else " " for ch in title).split()
    words = set(parts)
    for unwanted in NOT_THE_SUBJECT:
        if " " in unwanted:
            if unwanted in title:
                return None
        elif unwanted in words:
            return None
    named = key_words(name)
    if not named:
        return None
    # The last distinctive word is the surname, or the landmark's own name. It has to be
    # there: "Lincoln Memorial" is not Abraham Lincoln, and "Einstein" alone usually is.
    where = next((i for i, p in enumerate(parts) if p.startswith(named[-1])), None)
    if where is None:
        return None
    # A picture *of* somebody, not a picture *by* them. Commons names a work
    # "Lady with an Ermine - Leonardo da Vinci", so the artist's surname is in the title
    # and the file is a painting of a stranger. A file that is actually of the person
    # almost always leads with their name — "Abraham Lincoln O-77", "Mahatma Gandhi 1942" —
    # or says outright that it is a portrait.
    portrait = "portrait" in title or "photograph of" in title
    if where > 2 and not portrait:
        return None
    score = sum(1 for w in named if any(p.startswith(w) for p in parts))
    if where == 0:
        score += 3
    if portrait:
        score += 2
    return score


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


def best_file(term, name):
    titles = []
    for phrasing in (f"{term} filetype:bitmap", f"{name} filetype:bitmap"):
        found = api({"action": "query", "list": "search", "srsearch": phrasing,
                     "srnamespace": 6, "srlimit": 14})
        if found is None:
            return "Commons refused the request, so nothing is known"
        for hit in found.get("query", {}).get("search", []):
            if hit["title"] not in titles:
                titles.append(hit["title"])
        time.sleep(2.0)
    if not titles:
        return "no file of any licence matches that name"

    info = api({"action": "query", "titles": "|".join(titles[:40]), "prop": "imageinfo",
                "iiprop": "url|size|extmetadata", "iiurlwidth": 1200})
    if info is None:
        return "Commons refused the request, so nothing is known"
    candidates = []
    for page in info.get("query", {}).get("pages", {}).values():
        image = (page.get("imageinfo") or [{}])[0]
        if not image:
            continue
        meta = image.get("extmetadata", {})
        licence = strip_html((meta.get("LicenseShortName", {}) or {}).get("value", ""))
        if not any(word in licence.lower() for word in ALLOWED):
            continue
        fit = relevance(page["title"], name)
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
        return "files matched the name but none is both freely licensed and the subject"
    return max(candidates, key=lambda c: (c["fit"], c["pixels"]))


def load(module, attribute):
    spec = importlib.util.spec_from_file_location(module, os.path.join(HERE, module + ".py"))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return getattr(loaded, attribute)


PACKS = {
    "famous-faces": {
        "subjects": ("subjects_people", "PEOPLE"),
        "title": "Famous Faces",
        "blurb": "Leaders, scientists, writers and explorers almost everyone has seen.",
        "themes": ["chronology"],
        "chronologyPrompt": "Who was born first?",
        "chronologyBasis": "birth",
        "namedSubjectPrompt": "Which one shows {name}?",
        "fact": lambda name, role, year: f"{name} was a {role}, born in {year}.",
    },
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", required=True, choices=sorted(PACKS))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--force", action="store_true",
                        help="write even if the pack would come out smaller than it is now")
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--rest", type=int, default=240)
    args = parser.parse_args()
    for number in range(args.rounds):
        if number:
            print(f"\n--- resting {args.rest}s, then pass {number + 1} of {args.rounds} ---\n",
                  flush=True)
            time.sleep(args.rest)
        FAILED["calls"] = 0
        if not one_pass(args):
            print("\nevery subject sourced — stopping early")
            break


def one_pass(args):
    spec = PACKS[args.pack]
    subjects = load(*spec["subjects"])
    folder = os.path.join(ROOT, "TimeRolls", "Packs", args.pack)
    path = os.path.join(folder, f"{args.pack}.pack.json")

    existing, manifest = {}, {}
    if os.path.exists(path):
        manifest = json.load(open(path))
        for item in manifest.get("items", []):
            existing[item["id"]] = item

    items, unresolved = list(manifest.get("items", [])), []
    have = set(existing)
    refused_in_a_row = 0
    for slug, name, term, year, role in subjects:
        item_id = f"{args.pack}-{slug}"
        if item_id in have:
            continue
        file = best_file(term, name)
        if isinstance(file, str):
            print(f"{name:<30} UNRESOLVED — {file}", flush=True)
            unresolved.append((name, file))
            refused_in_a_row = refused_in_a_row + 1 if "refused" in file else 0
            if refused_in_a_row >= 4:
                print("\n  Commons is refusing everything now — ending this pass early")
                break
            continue
        refused_in_a_row = 0
        print(f"{name:<30} {file['license']:<16} {file['file'][:42]}", flush=True)
        items.append({
            "id": item_id,
            "title": name,
            "objectTags": [],
            "remoteURL": file["url"],
            "year": year,
            "month": 6,
            "credit": file["credit"] or "Wikimedia Commons contributor",
            "source": "Wikimedia Commons",
            "sourceURL": file["sourceURL"],
            "license": file["license"],
            "licenseURL": file["licenseURL"],
            "isResizedCopy": True,
            "subject": role,
            "fact": spec["fact"](name, role, year),
        })
        time.sleep(2.0)

    print(f"\n{len(items)} in the pack, {len(subjects) - len(items)} still to find"
          + (f" ({FAILED['calls']} lookups refused)" if FAILED["calls"] else ""))

    if args.apply:
        # Never replace a fuller pack with a thinner one.
        #
        # A run that Commons refuses produces an empty list of items, and writing that out
        # replaces a shipped pack of 335 photographs with a pack of none — which is exactly
        # what happened to Famous Faces. The builder cannot tell "there are no photographs"
        # from "nobody would give me any today", so it is not allowed to act on the
        # difference. `build_pack.py` has refused this for a while; this one had not.
        existing = len((manifest or {}).get("items", []))
        if len(items) < existing and not args.force:
            print(f"\nREFUSING TO WRITE: this run found {len(items)} photographs and the "
                  f"pack on disk has {existing}.")
            print("A run Commons refuses looks exactly like a subject that does not exist. "
                  "Run it again, or pass --force if the pack really should shrink.")
            return 1

        out = dict(manifest) if manifest else {}
        out.update({
            "formatVersion": 2, "id": args.pack, "title": spec["title"],
            "blurb": spec["blurb"], "themes": spec["themes"],
            "chronologyPrompt": spec.get("chronologyPrompt"),
            "chronologyBasis": spec.get("chronologyBasis"),
            "namedSubjectPrompt": spec.get("namedSubjectPrompt"),
            "license": "Public domain, CC0, CC BY, CC BY-SA",
            "items": items,
        })
        os.makedirs(folder, exist_ok=True)
        with open(path, "w") as handle:
            json.dump(out, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        print(f"written to {path}")
    return len(subjects) - len([i for i in items if i["id"].startswith(args.pack)])


if __name__ == "__main__":
    main()
