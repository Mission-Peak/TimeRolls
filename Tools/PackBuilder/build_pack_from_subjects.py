#!/usr/bin/env python3
"""Turn an enumerated subject list into a photo pack.

The earlier builders searched Commons for a subject's name and tried to work out whether
the file that came back was really that subject. That is a hard problem and it got several
answers wrong in ways that would have shipped: a painting *by* Leonardo offered as a
picture *of* him, a portrait of Caravaggio for Michelangelo — whose real name is
Michelangelo Merisi — and a photograph of a German gasometer for Primavera.

This does not search. Wikidata records a representative image for a subject (P18), chosen
by people who were looking at that subject, so the picture arrives already attached to the
thing it shows. The name-matching problem disappears rather than being solved.

What still has to be checked is the licence, which comes from Commons in batches of fifty.

  python3 Tools/PackBuilder/build_pack_from_subjects.py --pack famous-artworks
  python3 Tools/PackBuilder/build_pack_from_subjects.py --pack famous-artworks --apply --stop-at 400
"""

import argparse, hashlib, json, os, subprocess, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")

# Commons and public is the bar. CC BY and CC BY-SA need attribution, which every item
# carries and the credits screen shows.
ALLOWED = ("public domain", "pd-", "cc0", "no restrictions", "cc by", "cc-by", "attribution")

# Files in a person's Commons category that are about them without being of them. Matched
# as whole words, so "Jailhouse Rock" is not thrown away for containing "house".
# How much of the frame the largest face has to fill before somebody is recognisable.
#
# Measured against portraits already in the pack rather than guessed, and the first guess
# of 0.06 was wrong: it threw out perfectly good likenesses of Gandhi at 0.054, Elizabeth
# II at 0.030 and Handel at 0.040. Painted portraits and engravings read lower than
# photographs do — the detector was built for faces in photographs and is less sure of a
# face in oils — so the bar has to sit below where those land.
# Raised from 0.022, which let through photographs of somebody at work across a room.
# Measured against portraits we already had: Elizabeth II sits at 0.030, Handel at 0.040,
# Gandhi at 0.054, Harriet Tubman between 0.080 and 0.171. A candid at a desk or a lectern
# falls below 0.02. Thirty-five thousandths keeps the painted portraits and drops the rest.
PROMINENT_FACE = 0.035

# Works this audience should not be shown.
#
# The art-historical canon contains a great deal of nudity, and the notability ranking
# surfaces it — Courbet's L'Origine du monde is one of the most written-about paintings
# there is. This app is played by older adults, often with a caregiver beside them and
# sometimes in a care home; an explicit painting on the screen is wrong there whatever its
# standing in a gallery. Matched on the work's name, which is how these are known.
NOT_FOR_THIS_AUDIENCE = (
    "origine du monde", "venus of urbino", "sleeping venus", "rokeby venus",
    "valpincon bather", "valpinçon bather", "great bathers", "olympia",
    "maja desnuda", "nude", "naked", "odalisque", "turkish bath", "danae", "danaë",
    "leda and the swan", "susanna and the elders", "venus anadyomene",
)

NOT_A_PORTRAIT = {
    "signature", "autograph", "manuscript", "score", "sheet", "music", "letter",
    "grave", "tomb", "headstone", "memorial", "statue", "bust", "monument", "plaque",
    "house", "birthplace", "museum", "stamp", "coin", "medal", "banknote", "logo",
    "map", "diagram", "document", "certificate", "handwriting", "quote", "text",
}

PACKS = {
    "famous-artworks": {
        "subjects": "artworks", "themes": ["objects", "chronology"],
        "title": "Famous Artworks", "blurb": "Paintings almost everybody has seen.",
        "chronologyBasis": "created", "chronologyPrompt": "Which one was painted first?",
        "namedSubjectPrompt": "Which one shows {name}?",
        "needsYear": True,
    },
    "famous-faces": {
        "subjects": "people", "themes": ["chronology", "objects"],
        "title": "Famous Faces",
        "blurb": "Leaders, scientists, writers and performers almost everyone has seen.",
        "chronologyBasis": "birth", "chronologyPrompt": "Who was born first?",
        "namedSubjectPrompt": "Which one shows {name}?",
        "needsYear": True,
        # A round asking which one shows Beethoven has to show Beethoven. His Commons
        # category holds his sheet music, his signature, his house, his grave and statues
        # of him — all genuinely about him, none of them a picture of him — and the first
        # build of this pack put a page of manuscript in as his portrait.
        #
        # The face detector already runs on every photograph, so the test is free: a
        # portrait has a face in it and a page of music does not.
        "needsFace": True,
    },
    "travel-landmarks": {
        "subjects": "landmarks", "themes": ["places"],
        "title": "Travel Landmarks", "blurb": "Places people travel a long way to see.",
        "namedSubjectPrompt": "Which one shows {name}?",
        "needsYear": False,
    },
    "animals": {
        "subjects": "animals", "themes": ["objects"],
        "title": "Animals", "blurb": "Creatures from all over the world.",
        "namedSubjectPrompt": "Which photo has {name} in it?",
        "needsYear": False,
    },
    "plants": {
        "subjects": "plants", "themes": ["objects"],
        "title": "Plants", "blurb": "Flowers, trees and things that grow.",
        # Same shape as Animals, for the same reason: it asks what is in the picture,
        # which is answerable by looking. The list leans to food crops — tomato, onion,
        # potato, garlic, lemon — because those are the plants the world writes most
        # about, and they are also the ones a person is most likely to recognise.
        "namedSubjectPrompt": "Which photo has {name} in it?",
        "needsYear": False,
    },
}


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


def filename(image_url):
    """The Commons file name out of a P18 value."""
    if not image_url:
        return None
    tail = image_url.rsplit("/", 1)[-1]
    return "File:" + urllib.parse.unquote(tail).replace("_", " ")


def image_info(titles):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "titles": "|".join(titles), "prop": "imageinfo",
        "iiprop": "url|size|extmetadata", "iiurlwidth": 1200, "format": "json"})
    wait = 4.0
    for attempt in range(5):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response).get("query", {}).get("pages", {})
        except Exception:
            if attempt == 4:
                return None
            time.sleep(wait)
            wait *= 1.8
    return None


class Sieve:
    """Every photograph goes through the app's own curation before it enters a pack.

    The pack builders never did this — only the Commons harvest did — so a pack could hold
    a photograph the app would refuse at the point of use: a diagram, a scan of a document,
    a picture Apple scores below zero for being barely a photograph at all. Running it here
    means a pack cannot contain one.
    """

    def __init__(self, floor):
        self.process = subprocess.Popen(
            [os.path.join(ROOT, "Tools", "PhotoSieve", "run.sh"),
             "--aesthetics-floor", str(floor)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)

    def judge(self, path):
        try:
            self.process.stdin.write(os.path.abspath(path) + "\n")
            self.process.stdin.flush()
            line = self.process.stdout.readline()
            return json.loads(line) if line else None
        except Exception:
            return None


def download(url, into):
    if os.path.exists(into):
        return True
    os.makedirs(os.path.dirname(into), exist_ok=True)
    try:
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        if len(data) < 3000:
            return False
        with open(into, "wb") as handle:
            handle.write(data)
        return True
    except Exception:
        return False


def cache_path(url):
    return os.path.join(ROOT, "build", "vet-cache",
                        hashlib.sha256(url.encode()).hexdigest()[:20] + ".jpg")


def commons_categories(ids):
    """Each subject's own Commons category, where it has one.

    This is how a pack gets several photographs of the same thing without going back to
    searching by name — the category *is* the subject's collection of pictures, curated by
    people who were looking at it. Fetched with the candidates pinned in VALUES, because
    asking Wikidata an open-ended question about categories times out and asking it a
    bounded one does not.
    """
    out = {}
    for start in range(0, len(ids), 150):
        values = " ".join("wd:" + q for q in ids[start:start + 150])
        query = f"SELECT ?item ?cat WHERE {{ VALUES ?item {{ {values} }} ?item wdt:P373 ?cat . }}"
        url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode(
            {"query": query, "format": "json"})
        wait = 5.0
        for attempt in range(4):
            try:
                request = urllib.request.Request(
                    url, headers={"User-Agent": AGENT,
                                  "Accept": "application/sparql-results+json"})
                with urllib.request.urlopen(request, timeout=120) as response:
                    rows = json.load(response)["results"]["bindings"]
                for row in rows:
                    out[row["item"]["value"].rsplit("/", 1)[-1]] = row["cat"]["value"]
                break
            except Exception:
                if attempt == 3:
                    break
                time.sleep(wait)
                wait *= 1.8
        time.sleep(0.6)
    return out


def files_in(category, most=12):
    """The image files in a Commons category."""
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "list": "categorymembers",
        "cmtitle": "Category:" + category, "cmtype": "file",
        "cmlimit": most, "format": "json"})
    wait = 4.0
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = json.load(response)
            return [m["title"] for m in
                    data.get("query", {}).get("categorymembers", [])]
        except Exception:
            if attempt == 3:
                return []
            time.sleep(wait)
            wait *= 1.8
    return []


def slug(name):
    keep = [ch.lower() if ch.isalnum() else "-" for ch in name]
    out = "".join(keep)
    while "--" in out:
        out = out.replace("--", "-")
    return out.strip("-")[:60]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", required=True, choices=sorted(PACKS))
    parser.add_argument("--min-known", type=int, default=40,
                        help="fewest Wikipedia language editions a subject must appear in. "
                             "This is the anti-obscurity bar: at 20 the landmarks are "
                             "Milan Cathedral and the Holy Sepulchre, at 10 they are the "
                             "Tower of Penegate")
    parser.add_argument("--aesthetics-floor", type=float, default=0.35,
                        help="Apple's aesthetics score a photograph must reach")
    parser.add_argument("--per-subject", type=int, default=1,
                        help="how many photographs to take of each subject. More than one "
                             "is how a pack reaches thousands of pictures of things people "
                             "recognise, rather than hundreds of recognisable things and "
                             "thousands of obscure ones")
    parser.add_argument("--stop-at", type=int, default=400,
                        help="stop once the pack holds this many, for a look before more")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    spec = PACKS[args.pack]
    subjects = json.load(open(os.path.join(ROOT, "build", "subjects",
                                           f"{spec['subjects']}.json")))
    folder = os.path.join(ROOT, "TimeRolls", "Packs", args.pack)
    path = os.path.join(folder, f"{args.pack}.pack.json")
    manifest = json.load(open(path)) if os.path.exists(path) else {}
    items = list(manifest.get("items", []))
    have_ids = {i["id"] for i in items}
    have_names = {(i.get("title") or "").lower() for i in items}

    # Best known first, so stopping early stops at the recognisable end of the list.
    subjects.sort(key=lambda s: -s.get("sitelinks", 0))
    # No obscure subjects, and no two subjects with the same name. "The Kiss" is the title
    # of several different paintings and "St. Peter's Church" of hundreds of buildings — a
    # round holding two of them asks which one shows a thing both of them show.
    taken_names = set(have_names)
    wanted = []
    for subject in subjects:
        name = subject["name"].lower()
        if subject.get("sitelinks", 0) < args.min_known:
            continue
        if any(word in name for word in NOT_FOR_THIS_AUDIENCE):
            continue
        if name in taken_names:
            continue
        if f"{args.pack}-{slug(subject['name'])}" in have_ids:
            continue
        if spec["needsYear"] and not subject.get("year"):
            continue
        taken_names.add(name)
        wanted.append(subject)

    turned_away = []

    def refuse(subject, why):
        rejected[why] = rejected.get(why, 0) + 1
        turned_away.append((subject.get("name", "?"), why))

    added, rejected = 0, {"no licence we can use": 0, "no file": 0, "lookup failed": 0,
                          "the year cannot be right": 0,
                          "the app's curation refused the photograph": 0,
                          "could not be downloaded": 0,
                          "not a picture of the person": 0,
                          "the face is too small to recognise": 0,
                          "a crowd rather than a portrait": 0}
    sieve = Sieve(args.aesthetics_floor)

    # Several photographs of each subject, taken from the subject's own Commons category.
    # One per subject ran out of recognisable material at about two hundred famous
    # paintings; the category holds a dozen pictures of the same painting, and every one of
    # them is still a picture of something people know.
    print(f"  finding Commons categories for {len(wanted)} subjects...", flush=True)
    categories = commons_categories([w["id"] for w in wanted])
    print(f"  {len(categories)} of {len(wanted)} have one", flush=True)

    for start in range(0, len(wanted), 10):
        if len(items) >= args.stop_at:
            break
        batch = wanted[start:start + 10]

        # Every candidate for this handful of subjects: the representative image first,
        # because Wikidata chose it, then whatever else the category holds.
        candidates = {}
        for subject in batch:
            names = []
            if first := filename(subject.get("image")):
                names.append(first)
            # Always look at the category, even when keeping only one photograph. Taking
            # Wikidata's single representative image gave no choice at all, and its choice
            # is often a candid — somebody at a lectern, at their desk, in a crowd. With a
            # dozen to rank we can keep the one where the face is largest, which is what
            # "a portrait" means in practice.
            if category := categories.get(subject["id"]):
                for name in files_in(category, most=args.per_subject * 4):
                    if name not in names:
                        names.append(name)
            candidates[subject["id"]] = names

        every = [n for names in candidates.values() for n in names]
        pages = {}
        for chunk in range(0, len(every), 50):
            got = image_info(every[chunk:chunk + 50])
            if got is None:
                rejected["lookup failed"] += 1
                continue
            for page in got.values():
                pages[page.get("title", "")] = page

        for subject in batch:
            if len(items) >= args.stop_at:
                break
            if spec["needsYear"]:
                year, died = subject.get("year"), subject.get("creatorDied")
                # A year that cannot be right is worse than a missing one: this pack
                # answers "which was painted first", and Wikidata had A Burial at Ornans,
                # painted in 1849, recorded as 2020. Nothing is made after its maker dies.
                if year is None or year > 2025 or (died is not None and year > died + 1):
                    refuse(subject, "the year cannot be right")
                    continue

            # Look at every candidate, then keep the best — not the first that passes.
            # "I hardly recognised him" is what taking the first one produces: an
            # acceptable photograph rather than the clearest one available.
            shortlist = []
            for name in candidates[subject["id"]][:max(args.per_subject * 5, 12)]:
                if len(shortlist) >= max(args.per_subject * 3, 8):
                    break
                # Thrown out on the file name before anything is downloaded: a page of
                # Beethoven's music is not a photograph of Beethoven.
                if spec.get("needsFace"):
                    words = set("".join(ch if ch.isalnum() else " "
                                        for ch in name.lower()).split())
                    if words & NOT_A_PORTRAIT:
                        refuse(subject, "not a picture of the person")
                        continue

                page = pages.get(name)
                info = (page or {}).get("imageinfo")
                if not info:
                    refuse(subject, "no file")
                    continue
                info = info[0]
                meta = info.get("extmetadata", {}) or {}
                licence = strip_html((meta.get("LicenseShortName", {}) or {}).get("value", ""))
                if not any(word in licence.lower() for word in ALLOWED):
                    refuse(subject, "no licence we can use")
                    continue
                if min(info.get("width", 0), info.get("height", 0)) < 500:
                    refuse(subject, "no file")
                    continue
                picture = info.get("thumburl") or info.get("url")
                local = cache_path(picture)
                if not download(picture, local):
                    refuse(subject, "could not be downloaded")
                    continue
                # The app's own curation, the same Vision requests the phone runs.
                verdict = sieve.judge(local)
                if verdict is not None and not verdict["passes"]:
                    refuse(subject, "the app's curation refused the photograph")
                    continue
                # And the person has to be recognisable in it, which is a stronger claim
                # than "there is a face somewhere". A photograph of Paul McCartney at a
                # library and one of Michael Jackson in a crowd both have his face in them
                # and neither is a picture you would know him from.
                #
                # Two measures, because they catch different failures. How much of the
                # frame the largest face fills separates a portrait from a figure in a
                # room. How many faces there are separates a portrait from an occasion.
                if spec.get("needsFace") and verdict is not None:
                    if not verdict["hasFace"] or verdict["faceArea"] < PROMINENT_FACE:
                        refuse(subject, "the face is too small to recognise")
                        continue
                    if verdict.get("faceCount", 1) > 1:
                        refuse(subject, "a crowd rather than a portrait")
                        continue

                shortlist.append((verdict, info, meta, licence, picture))

            # The clearest face first for a portrait pack, the best-looking photograph
            # otherwise.
            if spec.get("needsFace"):
                shortlist.sort(key=lambda c: -(c[0]["faceArea"] if c[0] else 0))
            else:
                shortlist.sort(key=lambda c: -(c[0]["aesthetics"] if c[0] else 0))

            for kept_here, (verdict, info, meta, licence, picture) in \
                    enumerate(shortlist[:args.per_subject]):
                if len(items) >= args.stop_at:
                    break
                items.append({
                    "id": f"{args.pack}-{slug(subject['name'])}-{kept_here + 1}",
                    # Which thing this is a photograph of. Several items share it, and a
                    # round must never hold two that do.
                    "subjectID": subject["id"],
                    "title": subject["name"],
                    "objectTags": [],
                    "remoteURL": picture,
                    "aesthetics": round(verdict["aesthetics"], 3) if verdict else None,
                    "year": subject.get("year") or 2015,
                    "month": 6,
                    "credit": strip_html((meta.get("Artist", {}) or {}).get("value", ""))[:140]
                              or "Wikimedia Commons contributor",
                    "source": "Wikimedia Commons",
                    "sourceURL": info.get("descriptionurl", ""),
                    "license": licence,
                    "licenseURL": strip_html((meta.get("LicenseUrl", {}) or {}).get("value", "")),
                    "isResizedCopy": True,
                    "knownBy": subject.get("sitelinks", 0),
                    "creator": subject.get("creator"),
                    "creatorDied": subject.get("creatorDied"),
                    "group": subject.get("group"),
                    "latitude": subject.get("latitude"),
                    "longitude": subject.get("longitude"),
                    "fact": subject.get("fact"),
                    "factSource": subject.get("factSource"),
                })
                added += 1
        print(f"  {len(items):>5} in the pack ({added} added so far)", flush=True)
        time.sleep(0.5)

    print(f"\n{args.pack}: {len(items)} photographs, {added} added this run")
    for why, count in rejected.items():
        if count:
            print(f"   {count:>5} left out — {why}")

    # And which ones, because a subject nobody can name is a subject nobody can fix.
    kept = {i.get("title") for i in items}
    lost = [(name, why) for name, why in turned_away if name not in kept]
    if lost:
        print(f"\n{len(lost)} subjects ended up with no photograph at all:")
        for name, why in lost[:60]:
            print(f"   {name[:34]:<36} {why}")

    if not args.apply:
        print("\nnothing written — pass --apply")
        return
    out = dict(manifest)
    out.update({
        "formatVersion": 2, "id": args.pack, "title": spec["title"],
        "blurb": spec["blurb"], "themes": spec["themes"],
        "namedSubjectPrompt": spec.get("namedSubjectPrompt"),
        "license": "Public domain, CC0, CC BY, CC BY-SA",
        "items": items,
    })
    for key in ("chronologyBasis", "chronologyPrompt"):
        if spec.get(key):
            out[key] = spec[key]
    os.makedirs(folder, exist_ok=True)
    with open(path, "w") as handle:
        json.dump(out, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"written to {path}")


if __name__ == "__main__":
    main()
