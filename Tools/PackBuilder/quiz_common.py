"""What the four quiz packs — Geography, Cars, Film Stars, Sports Stars — share.

Each pack is built by its own script (`build_geography.py`, `build_cars.py`,
`build_film_stars.py`, `build_sports_stars.py`), and every one of them has to clear the same
bar the older packs do. Kept here so the bar is written once:

* **Licence.** Public domain, CC0, CC BY or CC BY-SA, and nothing marked NC or ND. Commons
  does not accept non-commercial licences, but a builder that only trusted that would be one
  mirror away from shipping one.
* **Facts.** Every item carries the opening of its own English Wikipedia article and a link
  to it. An item with no article does not ship: a card that turns over blank is a broken
  card, and a question about something with no article is a question nobody can check.
* **The picture shows the thing.** Checked with the same SigLIP image tower the app ships
  (`PhotoThemes.mlpackage`), against sentences, and for people with Apple's own face
  detector (`face_count.swift`) — the same one the app runs.
* **No two that look alike.** Within a pack, a photograph whose nearest neighbour is almost
  the same picture is dropped, keeping the other of the pair.
* **Never shrink a pack by accident.** A run Commons refuses looks exactly like a run that
  found nothing, so a write that would make a pack smaller is refused unless asked for.

Item schema, on top of the format every pack already uses (see `PublicPacks.swift`):

    "facts":   {"continent": ["Europe"], "borders": ["France", "Spain"]}
               A key that is present is *known*, even when its list is empty — "has won no
               Oscar" is a fact. A key that is absent is unknown, and an item with an
               unknown key can never be a distractor for a question about it: absence of
               evidence is not evidence of absence.
    "cluster": what a fair distractor shares with the answer — "US state", "pony car",
               "American football". Rounds prefer distractors from the same cluster.
    "family":  cars only — the model line, "Ford Mustang", for "which one is the 2020
               Ford Mustang?" rounds across generations.
    "years":   cars only — [first, last] model year of the generation shown.
    "askYear": cars only — the model year the question names.

Pack schema adds "questions": [{"id", "ask", "exclude", "prompt"}] — ask about a value from
facts[ask], and rule out any distractor whose facts[exclude] contains it.
"""

import hashlib, json, os, subprocess, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PACKS = os.path.join(ROOT, "TimeRolls", "Packs")
CACHE = os.path.join(ROOT, "build", "quiz-cache")
SIGLIP = os.path.join(ROOT, "TimeRolls", "Themes", "PhotoThemes.mlpackage")
AGENT = ("TimeRolls-PackBuilder/1.2 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")

ALLOWED = ("public domain", "pd-", "pd ", "cc0", "no restrictions", "cc by", "cc-by",
           "attribution")
# Checked before ALLOWED, because "CC BY-NC 2.0" contains "cc by".
REFUSED = ("-nc", " nc", "noncommercial", "non-commercial", "-nd", " nd", "noderiv",
           "fair use", "non-free", "copyrighted")


def licence_ok(licence):
    text = (licence or "").lower()
    if not text or any(word in text for word in REFUSED):
        return False
    return any(word in text for word in ALLOWED)


# MARK: - Network

def fetch_json(url, tries=5, data=None):
    wait = 3.0
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, data=data, headers={
                "User-Agent": AGENT, "Accept": "application/json"})
            with urllib.request.urlopen(request, timeout=90) as response:
                return json.load(response)
        except Exception as error:
            if attempt == tries - 1:
                print(f"  ! {type(error).__name__}: {error}", file=sys.stderr)
                return None
            time.sleep(wait)
            wait *= 2
    return None


def sparql(query):
    """Rows of a Wikidata query, each a dict of plain strings."""
    data = fetch_json("https://query.wikidata.org/sparql?" + urllib.parse.urlencode(
        {"query": query, "format": "json"}))
    if data is None:
        return None
    rows = []
    for binding in data["results"]["bindings"]:
        rows.append({key: value["value"] for key, value in binding.items()})
    return rows


def qid(uri):
    return uri.rsplit("/", 1)[-1]


def entities(ids, props="claims|labels|sitelinks"):
    """Wikidata items, fifty at a time."""
    out = {}
    ids = list(dict.fromkeys(ids))
    for start in range(0, len(ids), 50):
        batch = ids[start:start + 50]
        data = fetch_json("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(batch), "props": props,
            "languages": "en|mul", "format": "json"}))
        if data:
            out.update(data.get("entities") or {})
        time.sleep(0.4)
    return out


def label(entity):
    """The English label, or the language-neutral one. Wikidata has been moving labels
    that read the same in every language — Forrest Gump, Meryl Streep — to "mul", and an
    English-only lookup finds nothing for them."""
    labels = entity.get("labels") or {}
    return (labels.get("en") or labels.get("mul") or {}).get("value")


def claim_ids(entity, prop):
    """The item ids a statement points at, preferred rank first, deprecated never."""
    out = []
    for statement in (entity.get("claims") or {}).get(prop, []):
        if statement.get("rank") == "deprecated":
            continue
        value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if isinstance(value, dict) and "id" in value:
            out.append(value["id"])
    return out


def claim_values(entity, prop):
    out = []
    for statement in (entity.get("claims") or {}).get(prop, []):
        if statement.get("rank") == "deprecated":
            continue
        value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if value is not None:
            out.append(value)
    return out


def claim_year(entity, prop):
    for value in claim_values(entity, prop):
        if isinstance(value, dict) and "time" in value:
            try:
                return int(value["time"][1:5])
            except ValueError:
                pass
    return None


def sitelink_count(entity):
    return len(entity.get("sitelinks") or {})


# MARK: - Commons

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


def commons_files(names, width=1200):
    """Licence, credit and a 1200px copy for each Commons file, by file name."""
    out = {}
    titles = [n if n.startswith("File:") else "File:" + n for n in names]
    for start in range(0, len(titles), 40):
        batch = titles[start:start + 40]
        data = fetch_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
            "action": "query", "titles": "|".join(batch), "prop": "imageinfo",
            "iiprop": "url|size|extmetadata|mime", "iiurlwidth": width, "format": "json"}))
        time.sleep(1.0)
        if not data:
            continue
        normalised = {n["to"]: n["from"] for n in (data["query"].get("normalized") or [])}
        for page in (data["query"].get("pages") or {}).values():
            info = (page.get("imageinfo") or [{}])[0]
            if not info:
                continue
            meta = info.get("extmetadata") or {}
            name = normalised.get(page["title"], page["title"]).removeprefix("File:")
            out[name] = {
                "file": page["title"],
                "url": info.get("thumburl") or info.get("url"),
                "width": info.get("width", 0),
                "height": info.get("height", 0),
                "mime": info.get("mime", ""),
                "license": strip_html((meta.get("LicenseShortName") or {}).get("value", "")),
                "licenseURL": strip_html((meta.get("LicenseUrl") or {}).get("value", "")),
                "credit": strip_html((meta.get("Artist") or {}).get("value", ""))[:140],
                "sourceURL": info.get("descriptionurl", ""),
                "description": strip_html(
                    (meta.get("ImageDescription") or {}).get("value", ""))[:300],
            }
    return out


def commons_category_files(category, limit=60):
    """File names in one Commons category (not its subcategories)."""
    data = fetch_json("https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "list": "categorymembers", "cmtitle": "Category:" + category,
        "cmtype": "file", "cmlimit": limit, "format": "json"}))
    time.sleep(0.8)
    if not data:
        return []
    return [m["title"].removeprefix("File:")
            for m in data.get("query", {}).get("categorymembers", [])]


def usable_photo(info, min_side=500):
    """A bitmap, freely licensed, big enough to fill a tile."""
    if not info or not licence_ok(info["license"]):
        return False
    if info["mime"] not in ("image/jpeg", "image/png", "image/webp", "image/tiff"):
        return False
    return min(info["width"], info["height"]) >= min_side


def download(url):
    """A local copy, cached by URL."""
    os.makedirs(CACHE, exist_ok=True)
    key = hashlib.sha256(url.encode()).hexdigest()[:24]
    path = os.path.join(CACHE, key + ".jpg")
    if os.path.exists(path) and os.path.getsize(path) > 4096:
        return path
    try:
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        data = urllib.request.urlopen(request, timeout=90).read()
        open(path, "wb").write(data)
        time.sleep(0.5)
        return path if len(data) > 4096 else None
    except Exception:
        return None


# MARK: - Facts

def wikipedia_intros(qids):
    """{qid: (sentence or two, article URL)} from each item's English article."""
    sys.path.insert(0, HERE)
    import add_descriptions as ad
    titles = ad.english_titles(list(qids))
    summaries = ad.intros(sorted(set(titles.values())))
    out = {}
    for item, title in titles.items():
        if summary := summaries.get(title):
            out[item] = (summary, "https://en.wikipedia.org/wiki/"
                         + urllib.parse.quote(title.replace(" ", "_")))
    return out


# MARK: - Looking at the pictures

def face_counts(paths):
    """{path: {"faces": n, "largest": share}} from Apple's detector."""
    out = {}
    paths = [p for p in paths if p]
    for start in range(0, len(paths), 40):
        result = subprocess.run(
            ["swift", os.path.join(HERE, "face_count.swift"), *paths[start:start + 40]],
            capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            out.update(json.loads(result.stdout.strip().splitlines()[-1]))
    return out


class Siglip:
    """The app's own image tower, plus the matching text tower, for vetting on a Mac."""

    def __init__(self):
        sys.path.insert(0, HERE)
        import vet_pack
        self.text = vet_pack.model_and_processor()
        self.image = vet_pack.image_embedder(SIGLIP)

    def images(self, paths):
        import numpy as np
        vectors = {}
        for path in paths:
            try:
                vectors[path] = self.image(path)
            except Exception:
                pass
        return vectors

    def prefers(self, vector, good, bad):
        """Whether the picture is closer to any of `good` than to every one of `bad`."""
        import numpy as np
        good_scores = self.text(good) @ vector
        bad_scores = self.text(bad) @ vector
        return float(good_scores.max()) > float(bad_scores.max()), float(good_scores.max())


def near_duplicates(vectors, threshold=0.92):
    """Keys to drop so no two kept pictures are closer than `threshold`."""
    import numpy as np
    keys = list(vectors)
    if len(keys) < 2:
        return set()
    stack = np.vstack([vectors[k] for k in keys])
    similarity = stack @ stack.T
    np.fill_diagonal(similarity, -1)
    drop = set()
    for i, key in enumerate(keys):
        if key in drop:
            continue
        for j in np.where(similarity[i] >= threshold)[0]:
            if keys[j] not in drop and j > i:
                drop.add(keys[j])
    return drop


# MARK: - Writing

def write_pack(pack_id, meta, items, force=False):
    folder = os.path.join(PACKS, pack_id)
    path = os.path.join(folder, f"{pack_id}.pack.json")
    if os.path.exists(path) and not force:
        existing = len(json.load(open(path)).get("items", []))
        if len(items) < existing:
            print(f"REFUSING TO WRITE: {len(items)} items, and {existing} on disk. "
                  "Pass --force if the pack really should shrink.")
            return False
    os.makedirs(folder, exist_ok=True)
    out = {"formatVersion": 2, "id": pack_id, **meta,
           "license": "Public domain, CC0, CC BY, CC BY-SA",
           "builtAt": time.strftime("%Y-%m-%d"), "items": items}
    with open(path, "w") as handle:
        json.dump(out, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"written {len(items)} items to {path}")
    return True
