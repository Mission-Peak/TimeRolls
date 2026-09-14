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
        "targets": [
            {"place": "Paris, France",           "lat": 48.8584,  "lon": 2.2945,   "take": 3},
            {"place": "Rome, Italy",             "lat": 41.8902,  "lon": 12.4922,  "take": 3},
            {"place": "London, England",         "lat": 51.5007,  "lon": -0.1246,  "take": 3},
            {"place": "San Francisco, CA",       "lat": 37.8199,  "lon": -122.4783,"take": 3},
            {"place": "Sydney, Australia",       "lat": -33.8568, "lon": 151.2153, "take": 3},
            {"place": "Agra, India",             "lat": 27.1751,  "lon": 78.0421,  "take": 2},
            {"place": "New York, NY",            "lat": 40.6892,  "lon": -74.0445, "take": 3},
            {"place": "Barcelona, Spain",        "lat": 41.4036,  "lon": 2.1744,   "take": 2},
            {"place": "Amsterdam, Netherlands",  "lat": 52.3600,  "lon": 4.8852,   "take": 2},
            {"place": "Venice, Italy",           "lat": 45.4341,  "lon": 12.3388,  "take": 2},
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
        "queries": [
            {"q": 'online_media_type:"Images" AND media_usage:"CC0" AND object_type:"Photographs" AND (family OR children OR portrait)', "take": 12},
            {"q": 'online_media_type:"Images" AND media_usage:"CC0" AND object_type:"Photographs" AND (street OR city OR shop OR market)', "take": 12},
            {"q": 'online_media_type:"Images" AND media_usage:"CC0" AND object_type:"Photographs" AND (farm OR train OR automobile OR bicycle)', "take": 12},
        ],
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
            complaint = looks_like_a_photograph(title, info.get("mime"), info.get("width"))
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
        params = {"q": query["q"], "rows": 100, "api_key": api_key}
        url = "https://api.si.edu/openaccess/api/v1.0/search?" + urllib.parse.urlencode(params)
        try:
            payload = fetch_json(url)
        except Exception as error:
            if "429" in str(error):
                print("    ! rate limited. DEMO_KEY allows about 30 requests an hour —")
                print("      get a free key at https://api.data.gov/signup and pass --si-key.")
            else:
                print(f"    ! query failed: {error}")
            continue

        taken = 0
        for row in payload.get("response", {}).get("rows", []):
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
            image = first.get("content")
            if not image:
                rejections.add("no image URL")
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
        print(f"    kept {taken} for: {query['q'][:58]}…")
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
    if os.path.exists(pack_dir):
        shutil.rmtree(pack_dir)
    os.makedirs(pack_dir)

    print(f"\nDownloading {len(candidates)} images…")
    items = []
    for index, candidate in enumerate(candidates, start=1):
        item_id = f"{spec['id']}-{index:03d}"
        filename = f"{item_id}.jpg"
        if not download_and_resize(candidate["image"], os.path.join(pack_dir, filename)):
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
    manifest_name = f"{spec['id']}.pack.json"
    with open(os.path.join(pack_dir, manifest_name), "w") as handle:
        json.dump(manifest, handle, indent=2)

    total_bytes = sum(os.path.getsize(os.path.join(pack_dir, entry["file"])) for entry in items)
    years = sorted(entry["year"] for entry in items)
    print(f"\nWrote {len(items)} items to {pack_dir}")
    print(f"  years  {years[0]}–{years[-1]}")
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
