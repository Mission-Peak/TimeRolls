#!/usr/bin/env python3
"""
build_pack.py — assembles a Photo Chronology photo pack from CC0 sources.

Licensing discipline (spec §6.2, §12): this tool accepts CC0 and nothing else.
CC0 is a worldwide waiver, so it sidesteps the fact that "public domain" is
jurisdiction-specific and the App Store is not — an item that is PD in the US can
still be in copyright in the EU. Anything whose licence is not exactly CC0 is
dropped and counted in the rejection tally printed at the end.

CC0 requires no attribution. We record provenance anyway — source, creator, and the
page the item came from — so any item in a shipped pack can be traced back later.

Sources
  commons-geo    Wikimedia Commons geosearch around a coordinate. Gives real
                 coordinates, so these items can carry the Places theme.
  smithsonian    Smithsonian Open Access. ~35k CC0 photographs with dates, which is
                 where historical material comes from.

Usage
  python3 build_pack.py --pack landmarks --out ../../Photo\\ Chronology/Packs
  python3 build_pack.py --pack decades   --out ../../Photo\\ Chronology/Packs
  python3 build_pack.py --list

The Smithsonian API needs a key. DEMO_KEY works for small runs (30 requests/hour);
get a free one at api.data.gov and pass --si-key for anything larger.
"""

import argparse, json, os, re, shutil, subprocess, sys, tempfile, time, urllib.parse, urllib.request

UA = "PhotoChronologyPackBuilder/1.0 (Attimis prototype; +hanna@attimis.co)"
MAX_EDGE = 1200          # long edge, px — enough for a tile on any device
JPEG_QUALITY = "60"      # sips quality step

# --------------------------------------------------------------------------- specs

PACK_SPECS = {
    "landmarks": {
        "id": "travel-landmarks",
        "title": "Travel Landmarks",
        "blurb": "Places worth remembering, from six decades of travel photography.",
        "source": "commons-geo",
        # Coordinates are the query; the place name is ours, so Places questions read well.
        # Each target is a well-photographed landmark; the place name is ours, so a
        # Places question reads the way a person would say it. More cities is not just
        # more content — Places picks its distractors by distance from the answer, so a
        # wider spread is what makes the difficulty lever work.
        "targets": [
            # Europe
            {"place": "Paris, France",          "lat": 48.8584,  "lon": 2.2945,   "take": 2},
            {"place": "Rome, Italy",            "lat": 41.8902,  "lon": 12.4922,  "take": 2},
            {"place": "Venice, Italy",          "lat": 45.4341,  "lon": 12.3388,  "take": 2},
            {"place": "London, England",        "lat": 51.5007,  "lon": -0.1246,  "take": 2},
            {"place": "Edinburgh, Scotland",    "lat": 55.9486,  "lon": -3.1999,  "take": 2},
            {"place": "Dublin, Ireland",        "lat": 53.3438,  "lon": -6.2546,  "take": 2},
            {"place": "Barcelona, Spain",       "lat": 41.4036,  "lon": 2.1744,   "take": 2},
            {"place": "Lisbon, Portugal",       "lat": 38.6916,  "lon": -9.2160,  "take": 2},
            {"place": "Amsterdam, Netherlands", "lat": 52.3600,  "lon": 4.8852,   "take": 2},
            {"place": "Berlin, Germany",        "lat": 52.5163,  "lon": 13.3777,  "take": 2},
            {"place": "Prague, Czechia",        "lat": 50.0865,  "lon": 14.4114,  "take": 2},
            {"place": "Vienna, Austria",        "lat": 48.1845,  "lon": 16.3122,  "take": 2},
            {"place": "Athens, Greece",         "lat": 37.9715,  "lon": 23.7267,  "take": 2},
            {"place": "Copenhagen, Denmark",    "lat": 55.6798,  "lon": 12.5912,  "take": 2},
            {"place": "Stockholm, Sweden",      "lat": 59.3251,  "lon": 18.0711,  "take": 2},
            {"place": "Istanbul, Türkiye",      "lat": 41.0086,  "lon": 28.9802,  "take": 2},
            {"place": "Reykjavík, Iceland",     "lat": 64.1418,  "lon": -21.9266, "take": 2},
            # North America
            {"place": "New York, NY",           "lat": 40.6892,  "lon": -74.0445, "take": 2},
            {"place": "San Francisco, CA",      "lat": 37.8199,  "lon": -122.4783,"take": 2},
            {"place": "Chicago, IL",            "lat": 41.8827,  "lon": -87.6233, "take": 2},
            {"place": "Seattle, WA",            "lat": 47.6205,  "lon": -122.3493,"take": 2},
            {"place": "Washington, DC",         "lat": 38.8893,  "lon": -77.0502, "take": 2},
            {"place": "Boston, MA",             "lat": 42.3541,  "lon": -71.0704, "take": 2},
            {"place": "New Orleans, LA",        "lat": 29.9574,  "lon": -90.0629, "take": 2},
            {"place": "Toronto, Canada",        "lat": 43.6426,  "lon": -79.3871, "take": 2},
            {"place": "Mexico City, Mexico",    "lat": 19.4270,  "lon": -99.1677, "take": 2},
            # South America
            {"place": "Rio de Janeiro, Brazil", "lat": -22.9519, "lon": -43.2105, "take": 2},
            {"place": "Buenos Aires, Argentina","lat": -34.6037, "lon": -58.3816, "take": 2},
            # Asia
            {"place": "Tokyo, Japan",           "lat": 35.7148,  "lon": 139.7967, "take": 2},
            {"place": "Kyoto, Japan",           "lat": 34.9671,  "lon": 135.7727, "take": 2},
            {"place": "Hong Kong",              "lat": 22.2940,  "lon": 114.1722, "take": 2},
            {"place": "Singapore",              "lat": 1.2834,   "lon": 103.8607, "take": 2},
            {"place": "Bangkok, Thailand",      "lat": 13.7500,  "lon": 100.4913, "take": 2},
            {"place": "Dubai, UAE",             "lat": 25.1972,  "lon": 55.2744,  "take": 2},
            {"place": "Agra, India",            "lat": 27.1751,  "lon": 78.0421,  "take": 2},
            # Africa
            {"place": "Cairo, Egypt",           "lat": 29.9792,  "lon": 31.1342,  "take": 2},
            {"place": "Cape Town, South Africa","lat": -33.9628, "lon": 18.4098,  "take": 2},
            # Oceania
            {"place": "Sydney, Australia",      "lat": -33.8568, "lon": 151.2153, "take": 2},
            {"place": "Melbourne, Australia",   "lat": -37.8183, "lon": 144.9671, "take": 2},
            {"place": "Auckland, New Zealand",  "lat": -36.8485, "lon": 174.7622, "take": 2},
        ],
    },
    "decades": {
        "id": "decades",
        "title": "Decades",
        "blurb": "Everyday life as it was photographed, decade by decade.",
        "source": "smithsonian",
        # Each query is aimed at a slice of the century. Yield varies a lot by era.
        # object_type matters as much as the keyword: without it the collection hands
        # back paintings, sketchbook folios and herbarium sheets, which are not what
        # "when was this taken?" means.
        #
        # One query per decade, because an untargeted search piles up wherever the
        # collection is deepest — which for CC0 is the late 1800s. A pack called
        # Decades should actually span them.
        "queries": [
            {"decade": decade, "take": 6,
             "q": ('online_media_type:"Images" AND media_usage:"CC0" AND '
                   'object_type:"Photographs" AND (%s)'
                   % " OR ".join(str(decade + offset) for offset in range(0, 10)))}
            for decade in range(1880, 1990, 10)
        ],
        # No decade may take over the pack.
        "perDecadeCap": 5,
    },
}

# --------------------------------------------------------------------------- helpers

class Rejections:
    def __init__(self):
        self.counts = {}
    def add(self, reason):
        self.counts[reason] = self.counts.get(reason, 0) + 1
    def report(self):
        if not self.counts:
            return "  (none)"
        return "\n".join(f"  {v:4d}  {k}" for k, v in sorted(self.counts.items(), key=lambda kv: -kv[1]))


def fetch_json(url, timeout=45):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def strip_html(text):
    return re.sub(r"<[^>]+>", " ", str(text or "")).strip()


def parse_year(text):
    """Pull a plausible 4-digit year out of the messy date strings these sources use."""
    cleaned = strip_html(text)
    match = re.search(r"\b(1[89]\d{2}|20[0-2]\d)\b", cleaned)
    return int(match.group(1)) if match else None


# Geosearch returns whatever is pinned at a coordinate — maps, diagrams, webcam
# grabs and video posters included. A photo pack wants photographs.
NOT_A_PHOTOGRAPH = re.compile(
    r"\b(map|diagram|chart|plan|logo|icon|screenshot|cam|webcam|panorama|"
    r"schematic|drawing|poster|sign|graph)\b", re.IGNORECASE)
PHOTO_MIMES = {"image/jpeg", "image/png"}

# Smithsonian object types that are actually photographs. Paintings and drawings are
# lovely, but "which of these is older" is a question about photographs.
PHOTOGRAPHIC_TYPES = re.compile(
    r"photograph|photoprint|daguerreotype|ambrotype|tintype|negative|slide|albumen",
    re.IGNORECASE)


# Curation, not prudishness. The audience for this game is older adults, some living
# with dementia, and the whole design is built to avoid distress. An archive search will
# happily return a lynching victim's funeral, a machine-gun company and a train wreck
# alongside the picnics. None of that belongs in a gentle reminiscence game, so it is
# filtered by subject before anyone ever sees it. Word boundaries matter here: without
# them "Ward" matches "war" and a cassowary matches on "Wattled".
DISTRESSING = re.compile(
    r"\b(funeral|cemet\w+|grave|graves|burial|buried|lynch\w*|riot\w*|murder\w*|"
    r"killed|death|deaths|dead|wounded|casualt\w+|war|wars|battle|combat|"
    r"disaster|flood|famine|epidemic|hospital|asylum|prison|jail|slave\w*|corpse|autopsy|"
    # Military, including the abbreviations these catalogues actually use: a title like
    # "366 Inf. 92nd Div." never trips a filter looking for the word "infantry".
    r"soldier\w*|infantry|inf|regiment\w*|brigade|battalion|squadron|div|division|troops?|"
    r"military|legion|officers?|hdqrs|headquarters|"
    r"army|navy|naval|marine|marines|corps|uniform|camouflag\w+|supply train|"
    r"cpl|sgt|lt|lieutenant|capt|captain|gen|general|col|colonel|major|admiral|"
    r"weapon\w*|rifle|gun|guns|bomb\w*|wreck\w*|crash\w*|"
    # Proper nouns carry the same weight as the topic words above and none of the same
    # spelling. A photo captioned only "Hitler at the Charles Bridge" is a picture of an
    # occupation to anyone old enough to remember it, and nothing in a list of topics
    # catches it.
    r"hitler|nazi\w*|f[uü]hrer|reich|gestapo|wehrmacht|swastika|holocaust|"
    r"concentration camp|genocide|mussolini|stalin|apartheid|ku klux|lynching|"
    r"execution|hanged|hanging|massacre|atrocit\w+|occupation|invasion)\b",
    re.IGNORECASE)

# The Smithsonian documents itself thoroughly: building interiors, gallery halls,
# construction sites and scanned album pages. All fine records, all dull as a photo to
# reminisce over.
INSTITUTIONAL = re.compile(
    r"\b(national museum|smithsonian institution|smithsonian building|the castle|"
    r"national gallery|museum of natural history|zoological park|hall of|regents|"
    r"secretary'?s parlor|si commons|sorting center|exhibits?|exhibition|construction|"
    r"installation|supplement|arts and industries|south yard|bureau building|centennial|"
    r"first ladies|album|sign for)\b|pages? \d+",
    re.IGNORECASE)


def unsuitable_subject(title):
    """Reasons a photograph shouldn't go in a pack, whatever its licence."""
    if DISTRESSING.search(title):
        return "distressing subject"
    if INSTITUTIONAL.search(title):
        return "institutional record, not a scene"
    return None


def looks_like_a_photograph(title, mime, width):
    if mime not in PHOTO_MIMES:
        return "not a photo file (%s)" % (mime or "unknown")
    if width and width < 800:
        return "too small (%dpx)" % width
    if NOT_A_PHOTOGRAPH.search(title):
        return "title suggests it isn't a photograph"
    return None


def parse_month(text):
    cleaned = strip_html(text)
    iso = re.search(r"\b(1[89]\d{2}|20[0-2]\d)-(\d{2})\b", cleaned)
    if iso:
        month = int(iso.group(2))
        return month if 1 <= month <= 12 else 6
    for index, name in enumerate(
        ["january","february","march","april","may","june",
         "july","august","september","october","november","december"], start=1):
        if name in cleaned.lower():
            return index
    return 6


def download_and_resize(url, destination):
    """Fetch an image and normalise it to a bundle-friendly JPEG. Returns True on success."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=90) as response:
            payload = response.read()
    except Exception:
        return False
    if len(payload) < 8_000:          # a stub or an error page, not a photograph
        return False

    with tempfile.NamedTemporaryFile(delete=False, suffix=".img") as handle:
        handle.write(payload)
        raw = handle.name
    try:
        result = subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", JPEG_QUALITY,
             "-Z", str(MAX_EDGE), raw, "--out", destination],
            capture_output=True, text=True)
        return result.returncode == 0 and os.path.exists(destination)
    finally:
        os.unlink(raw)

# --------------------------------------------------------------------------- sources

def from_commons(spec, rejections, limit_per_target=80):
    """Geosearch around each landmark, keeping only strict-CC0 files with a date."""
    items = []
    for target in spec["targets"]:
        params = {
            "action": "query", "format": "json", "generator": "geosearch",
            "ggsnamespace": 6, "ggsradius": 2500,
            "ggscoord": f"{target['lat']}|{target['lon']}", "ggslimit": limit_per_target,
            "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400,
        }
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
        try:
            payload = fetch_json(url)
        except Exception as error:
            print(f"    ! {target['place']}: {error}")
            continue

        taken = 0
        for page in ((payload.get("query") or {}).get("pages") or {}).values():
            if taken >= target["take"]:
                break
            info = (page.get("imageinfo") or [{}])[0]
            extra = info.get("extmetadata") or {}

            licence = strip_html((extra.get("LicenseShortName") or {}).get("value"))
            if licence != "CC0":
                rejections.add(f"licence not CC0 ({licence or 'unknown'})")
                continue
            title = strip_html(page.get("title", "")).replace("File:", "")
            complaint = (looks_like_a_photograph(title, info.get("mime"), info.get("width"))
                         or unsuitable_subject(title))
            if complaint:
                rejections.add(complaint)
                continue
            year = parse_year((extra.get("DateTimeOriginal") or {}).get("value"))
            if not year:
                rejections.add("no usable date")
                continue
            if not info.get("thumburl"):
                rejections.add("no image URL")
                continue

            items.append({
                "title": title,
                "year": year,
                "month": parse_month((extra.get("DateTimeOriginal") or {}).get("value")),
                "place": target["place"],
                "lat": target["lat"], "lon": target["lon"],
                "image": info["thumburl"],
                "credit": strip_html((extra.get("Artist") or {}).get("value")) or "Unknown",
                "source": "Wikimedia Commons",
                "source_url": info.get("descriptionurl", ""),
            })
            taken += 1
        print(f"    {target['place']}: {taken} kept")
        time.sleep(0.4)
    return items


def from_smithsonian(spec, rejections, api_key):
    """Smithsonian Open Access, filtered to items whose media is explicitly CC0."""
    items = []
    seen_titles = set()
    for query in spec["queries"]:
        taken = 0
        rows = []
        # Filtering is aggressive, so one page of results often isn't enough.
        for page in range(3):
            params = {"q": query["q"], "rows": 100, "start": page * 100, "api_key": api_key}
            url = "https://api.si.edu/openaccess/api/v1.0/search?" + urllib.parse.urlencode(params)
            try:
                payload = fetch_json(url)
            except Exception as error:
                if "429" in str(error):
                    print("    ! rate limited. DEMO_KEY allows about 30 requests an hour —")
                    print("      get a free key at https://api.data.gov/signup and pass --si-key.")
                else:
                    print(f"    ! query failed: {error}")
                break
            batch = payload.get("response", {}).get("rows", [])
            rows.extend(batch)
            if len(batch) < 100:
                break
            time.sleep(0.4)

        for row in rows:
            if taken >= query["take"]:
                break
            content = row.get("content", {})
            media = ((content.get("descriptiveNonRepeating") or {}).get("online_media") or {}).get("media") or []
            if not media:
                rejections.add("no media")
                continue
            first = media[0]
            if (first.get("usage") or {}).get("access") != "CC0":
                rejections.add("media not marked CC0")
                continue

            object_types = (content.get("indexedStructured") or {}).get("object_type") or []
            if not any(PHOTOGRAPHIC_TYPES.search(str(kind)) for kind in object_types):
                rejections.add("not a photograph (%s)" % (", ".join(map(str, object_types))[:36] or "no type"))
                continue

            dates = [entry.get("content") for entry in (content.get("freetext", {}).get("date") or [])]
            year = next((parse_year(value) for value in dates if parse_year(value)), None)
            if not year:
                rejections.add("no usable date")
                continue

            title = strip_html(row.get("title"))
            if title in seen_titles:
                rejections.add("duplicate title")
                continue
            complaint = unsuitable_subject(title)
            if complaint:
                rejections.add(complaint)
                continue
            image = first.get("content")
            if not image:
                rejections.add("no image URL")
                continue

            wanted_decade = query.get("decade")
            if wanted_decade and not (wanted_decade <= year < wanted_decade + 10):
                rejections.add("outside the decade asked for")
                continue

            makers = [strip_html(entry.get("content"))
                      for entry in (content.get("freetext", {}).get("name") or [])]
            seen_titles.add(title)
            items.append({
                "title": title[:80],
                "year": year,
                "month": 6,
                "place": None, "lat": None, "lon": None,
                "image": image,
                "credit": makers[0] if makers else "Smithsonian Institution",
                "source": "Smithsonian Open Access",
                "source_url": f"https://www.si.edu/object/{row.get('id','')}",
            })
            taken += 1
        label = str(query.get("decade") or query["q"][:40])
        print(f"    {label}: kept {taken}")
        time.sleep(1.0)
    return items

# --------------------------------------------------------------------------- build

def build(pack_name, out_root, api_key):
    spec = PACK_SPECS[pack_name]
    rejections = Rejections()

    print(f"\nBuilding '{spec['title']}' from {spec['source']} — CC0 only\n")
    if spec["source"] == "commons-geo":
        candidates = from_commons(spec, rejections)
    else:
        candidates = from_smithsonian(spec, rejections, api_key)

    if not candidates:
        print("\nNothing passed the licence gate. Rejections:")
        print(rejections.report())
        return 1

    pack_dir = os.path.join(out_root, spec["id"])
    staging = pack_dir + ".building"
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(staging)

    print(f"\nDownloading {len(candidates)} images…")
    items = []
    for index, candidate in enumerate(candidates, start=1):
        item_id = f"{spec['id']}-{index:03d}"
        filename = f"{item_id}.jpg"
        if not download_and_resize(candidate["image"], os.path.join(staging, filename)):
            rejections.add("download or resize failed")
            continue
        entry = {
            "id": item_id,
            "file": filename,
            "title": candidate["title"],
            "year": candidate["year"],
            "month": candidate["month"],
            "credit": candidate["credit"],
            "source": candidate["source"],
            "sourceURL": candidate["source_url"],
            "license": "CC0",
        }
        if candidate["place"]:
            entry.update({"place": candidate["place"],
                          "latitude": candidate["lat"],
                          "longitude": candidate["lon"]})
        items.append(entry)
        print(f"  {index:3d}/{len(candidates)}  {candidate['year']}  {candidate['title'][:52]}")

    manifest = {
        "formatVersion": 1,
        "id": spec["id"],
        "title": spec["title"],
        "blurb": spec["blurb"],
        "license": "CC0",
        "builtAt": time.strftime("%Y-%m-%d"),
        "items": items,
    }
    existing = 0
    if os.path.isdir(pack_dir):
        existing = len([name for name in os.listdir(pack_dir) if name.endswith(".jpg")])
    if items and existing > len(items):
        print(f"\nStopping: this run produced {len(items)} photos but {pack_dir} already "
              f"has {existing}. Refusing to replace a fuller pack with a thinner one —")
        print("rerun with --si-key once you have a key, or delete the pack directory to force it.")
        shutil.rmtree(staging)
        print("\nRejected along the way:")
        print(rejections.report())
        return 1

    manifest_name = f"{spec['id']}.pack.json"
    with open(os.path.join(staging, manifest_name), "w") as handle:
        json.dump(manifest, handle, indent=2)

    if os.path.exists(pack_dir):
        shutil.rmtree(pack_dir)
    os.rename(staging, pack_dir)

    total_bytes = sum(os.path.getsize(os.path.join(pack_dir, entry["file"])) for entry in items)
    years = sorted(entry["year"] for entry in items)
    spread = {}
    for entry in items:
        spread[entry["year"] // 10 * 10] = spread.get(entry["year"] // 10 * 10, 0) + 1
    print(f"\nWrote {len(items)} items to {pack_dir}")
    print(f"  years  {years[0]}–{years[-1]}")
    print(f"  spread {dict(sorted(spread.items()))}")
    print(f"  size   {total_bytes/1_000_000:.1f} MB")
    print(f"  places {len({entry.get('place') for entry in items if entry.get('place')})}")
    print("\nRejected along the way:")
    print(rejections.report())
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pack", choices=sorted(PACK_SPECS))
    parser.add_argument("--out", default="../../Photo Chronology/Packs")
    parser.add_argument("--si-key", default=os.environ.get("SI_API_KEY", "DEMO_KEY"))
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    if args.list or not args.pack:
        print("Packs this tool can build:\n")
        for name, spec in sorted(PACK_SPECS.items()):
            print(f"  {name:12} {spec['title']:20} via {spec['source']}")
        return 0
    return build(args.pack, os.path.abspath(args.out), args.si_key)


if __name__ == "__main__":
    sys.exit(main())
