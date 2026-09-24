"""Adds named subjects to the Landmarks and Animals packs.

Same method as the rest of the pack: the subject is chosen by hand, the photograph is
whichever one the Wikipedia article leads with, the licence is checked, the fact comes
from the article's own opening. Coordinates and the place name are looked up rather than
typed, because three hundred of them typed by hand would be three hundred chances to put
Niagara Falls in Cambodia.

    python3 Tools/PackBuilder/expand_packs.py --pack landmarks
    python3 Tools/PackBuilder/expand_packs.py --pack animals

Writes straight into TimeRolls/Packs/…; run the contact sheet afterwards and look at it.
"""
import argparse
import importlib.util
import json
import os
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_pack as bp                                          # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PACKS = os.path.join(ROOT, "TimeRolls", "Packs")
ALLOWED = {"cc0", "public domain", "no restrictions", "cc by", "cc by-sa"}


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, f"subjects_{name}.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_LABELS = {}


def polite_json(url, attempts=5):
    """Wikidata answers 429 to a run of quick questions. Wait and ask again."""
    for attempt in range(attempts):
        try:
            return bp.fetch_json(url)
        except Exception as error:
            if "429" not in str(error) or attempt == attempts - 1:
                raise
            time.sleep(2 * (attempt + 1))
    return {}


def label(target):
    """An English label for a Wikidata entity, asked once."""
    if target in _LABELS:
        return _LABELS[target]
    got = polite_json("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode(
        {"action": "wbgetentities", "format": "json", "ids": target,
         "props": "labels", "languages": "en"}))
    value = (((got.get("entities") or {}).get(target) or {})
             .get("labels", {}).get("en", {}).get("value"))
    _LABELS[target] = value
    time.sleep(0.2)
    return value


def geography(article):
    """Where the place is: its coordinates, and "Town, Country" for the question."""
    params = {"action": "query", "format": "json", "titles": article, "redirects": 1,
              "prop": "coordinates|pageprops", "ppprop": "wikibase_item"}
    payload = polite_json("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params))
    latitude = longitude = None
    qid = None
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        coordinates = (page.get("coordinates") or [{}])[0]
        latitude, longitude = coordinates.get("lat"), coordinates.get("lon")
        qid = (page.get("pageprops") or {}).get("wikibase_item")
    if latitude is None or qid is None:
        return None

    entity = polite_json(
        "https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode(
            {"action": "wbgetentities", "format": "json", "ids": qid,
             "props": "claims", "languages": "en"}))
    claims = ((entity.get("entities") or {}).get(qid) or {}).get("claims") or {}

    def label_of(property_id):
        for claim in claims.get(property_id, []):
            value = (((claim.get("mainsnak") or {}).get("datavalue") or {}).get("value") or {})
            target = value.get("id")
            if target and (found := label(target)):
                return found
        return None

    country = label_of("P17")            # country
    area = label_of("P131")              # located in the administrative territorial entity
    if area and country and area != country:
        place = f"{area}, {country}"
    else:
        place = country or area
    return (latitude, longitude, place) if place else None


def lead_image(article):
    """The file the article leads with.

    `prop=pageimages` is the usual route and simply has no answer for a good number of
    articles — Heron, Jaguar, Lynx among them. The REST summary knows the same lead image
    for all of those, so it stands behind the first route rather than the subject being
    dropped for want of a second question."""
    # Asked here rather than through build_pack's version, which swallows a rate-limit
    # as "this article has no picture" — which is how sixty good landmarks were skipped.
    params = {"action": "query", "format": "json", "titles": article,
              "prop": "pageimages", "piprop": "name", "redirects": 1}
    payload = polite_json("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params))
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        if page.get("pageimage"):
            return page["pageimage"].replace("_", " ")
    url = ("https://en.wikipedia.org/api/rest_v1/page/summary/"
           + urllib.parse.quote(article.replace(" ", "_")))
    try:
        summary = bp.fetch_json(url)
    except Exception:
        return None
    source = (summary.get("originalimage") or {}).get("source")
    if not source:
        return None
    name = urllib.parse.unquote(source.split("/")[-1].split("?")[0])
    return name.replace("_", " ")


def commons_info(file_title):
    """Licence and URLs for one Commons file, with the same patience."""
    params = {"action": "query", "format": "json", "titles": f"File:{file_title}",
              "prop": "imageinfo", "iiprop": "url|extmetadata|size|mime", "iiurlwidth": 1400}
    payload = polite_json("https://commons.wikimedia.org/w/api.php?"
                          + urllib.parse.urlencode(params))
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        info = (page.get("imageinfo") or [{}])[0]
        if info.get("thumburl"):
            return bp.strip_html(page.get("title", "")).replace("File:", ""), info
    return None


def photograph(article):
    """The article's lead image, if its licence allows it here."""
    lead = lead_image(article)
    if not lead:
        return None
    found = commons_info(lead)
    if not found:
        return None
    name, info = found
    metadata = info.get("extmetadata") or {}
    licence = bp.strip_html((metadata.get("LicenseShortName") or {}).get("value", ""))
    if bp.licence_family(licence) not in ALLOWED:
        return None
    if bp.looks_like_a_photograph(name, info.get("mime", ""), info.get("width", 0)):
        return None
    creator = bp.strip_html((metadata.get("Artist") or {}).get("value", "")) or "Unknown"
    return {
        "remoteURL": "https://commons.wikimedia.org/wiki/Special:FilePath/"
                     + urllib.parse.quote(name) + "?width=1200",
        "sourceURL": "https://commons.wikimedia.org/wiki/File:"
                     + urllib.parse.quote(name.replace(" ", "_")),
        "credit": creator[:120],
        "license": licence,
        "width": info.get("width", 0),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", choices=["landmarks", "animals"], required=True)
    parser.add_argument("--limit", type=int, default=0)
    arguments = parser.parse_args()

    pack_id = "travel-landmarks" if arguments.pack == "landmarks" else "animals"
    path = os.path.join(PACKS, pack_id, f"{pack_id}.pack.json")
    pack = json.load(open(path))
    have = {item["title"] for item in pack["items"]}

    subjects = (load("landmarks").LANDMARKS if arguments.pack == "landmarks"
                else load("animals").ANIMALS)
    if arguments.limit:
        subjects = subjects[:arguments.limit]

    added, skipped = 0, []
    for subject in subjects:
        title, article = subject[0], subject[1]
        tags = [subject[2]] if len(subject) > 2 else []
        if title in have:
            continue
        picture = photograph(article)
        if not picture:
            skipped.append(f"{title}: no usable lead image")
            continue
        item = {
            "id": f"{pack_id}-{bp.slug(title)}",
            "objectTags": tags,
            "remoteURL": picture["remoteURL"],
            "title": title,
            "year": 2015,
            "month": 6,
            "credit": picture["credit"],
            "source": "Wikimedia Commons",
            "sourceURL": picture["sourceURL"],
            "license": picture["license"],
        }
        fact = None
        for attempt in range(4):
            try:
                fact = bp.wikipedia_fact(article)
                break
            except Exception as error:
                if "429" not in str(error):
                    break
                time.sleep(2 * (attempt + 1))
        if fact:
            item["fact"] = fact
        if arguments.pack == "landmarks":
            where = geography(article)
            if not where:
                skipped.append(f"{title}: no coordinates")
                continue
            item["place"] = where[2]
            item["latitude"] = round(where[0], 4)
            item["longitude"] = round(where[1], 4)
        # Ids have to be unique: the app keys photographs by them, and a repeat means one
        # photograph shadowing another. A previous run left thirteen in travel-landmarks.
        if any(existing["id"] == item["id"] for existing in pack["items"]):
            skipped.append(f"{title} — an item with this id is already in the pack")
            continue
        pack["items"].append(item)
        have.add(title)
        added += 1
        if added % 10 == 0:
            json.dump(pack, open(path, "w"), indent=2, ensure_ascii=False)
            print(f"   … {added} added so far")
        time.sleep(0.2)

    json.dump(pack, open(path, "w"), indent=2, ensure_ascii=False)
    open(path, "a").write("\n")
    print(f"{pack_id}: added {added}, now {len(pack['items'])}")
    for line in skipped[:20]:
        print("   skipped", line)
    print(f"   skipped {len(skipped)} in total")


if __name__ == "__main__":
    main()
