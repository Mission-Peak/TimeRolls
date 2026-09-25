#!/usr/bin/env python3
"""Fill in where each landmark actually is.

595 of the 983 landmarks shipped with no place, no country and no coordinates, which kept
every one of them out of the Places game: `PlacesCurator` needs a name and a coordinate
before a photograph can be an answer or a distractor. Three fifths of the pack was
unusable for the game it was built for.

Landmarks carry no `subjectID`, so each has to be found by its title — and a title is a
far weaker key than a QID. There are churches called "Santa Maria delle Grazie" in Milan,
Brescia and Vicovaro; "Saint Sophia Cathedral" is in Kyiv, in Polotsk and in northern
Cyprus. Two rules keep those apart:

  The pack's own paragraph decides. Every landmark ships with the opening of its
  Wikipedia article, and that paragraph says where the thing is — "a Roman Catholic
  church in Milan, northern Italy". A candidate whose town is named in that paragraph is
  the right candidate, whatever else scores well. Ranking by how many language editions
  write about a place looked sensible and put the Basilica of San Lorenzo in Florence
  while the pack's own text said Milan.

  Fame breaks ties, and only ties. Where the paragraph names no candidate's town, the
  best-known candidate is nearly always the one a pack of famous landmarks means.

The place name is then climbed to something a person would recognise. P131 gives the
smallest administrative unit, which for the Panthéon is "Quartier de la Sorbonne" and for
Sacré-Cœur is "Clignancourt" — nobody is being asked which photograph is from
Clignancourt. The chain is walked upwards until it reaches a name the article uses, or
something that calls itself a city.

Anything that cannot be settled this way is left with no place and reported. A landmark
with no place is merely unused; a landmark with the wrong place makes the game tell
somebody something untrue.

  python3 Tools/PackBuilder/landmark_places.py           # report only
  python3 Tools/PackBuilder/landmark_places.py --write
"""

import json, os, re, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACK = os.path.join(ROOT, "TimeRolls", "Packs", "travel-landmarks",
                    "travel-landmarks.pack.json")
CANDIDATES = os.path.join(ROOT, "build", "landmark-candidates.json")
PLACES = os.path.join(ROOT, "build", "landmark-admin.json")

AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib")

NOT_A_PLACE = ("film", "song", "album", "band", "novel", "painting", "given name",
               "surname", "family name", "musical", "video game", "genus", "species",
               "television series", "footballer", "singer", "politician", "writer")

# Administrative units too fine to ask by. A quartier, an arrondissement or a city
# district is where a place is, not where anybody would say it is: nobody is being asked
# which photograph is from Clignancourt when they mean Montmartre, in Paris.
TOO_FINE = ("quartier", "arrondissement", "district of", "city district", "borough",
            "neighbourhood", "neighborhood", "ward of", "quarter of", "subdistrict",
            "locality", "civil parish", "raion", "municipal district")

# The same test against the name itself. A description is not always written, and
# "5th arrondissement of Paris" says what it is in its own label.
TOO_FINE_NAME = ("arrondissement", "quartier", " raion", "city district",
                 "municipal district", "district of")

# Names that are not names. Several thousand places are called "Old Town" or "Central
# District", and a question asking which photograph is from Central District is asking
# nothing at all.
NOT_A_NAME = {"old town", "new town", "city centre", "city center", "central district",
              "old city", "downtown", "historic centre", "historic center", "centre",
              "center", "district", "old quarter"}

CITY_LIKE = ("city", "town", "capital", "municipality", "commune", "village")


def get(url, tries=4):
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except Exception as error:
            # A rate limit is not an answer. Reading a refusal as "this landmark has no
            # location" is how a pack ends up with places quietly missing for ever.
            if attempt == tries - 1:
                raise RuntimeError("giving up on %s: %s" % (url, error))
            time.sleep(2 * (attempt + 1))


def search(title):
    url = ("https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json"
           "&language=en&uselang=en&type=item&limit=7&search="
           + urllib.parse.quote(title))
    return [hit["id"] for hit in (get(url).get("search") or [])]


def entities(qids):
    out = {}
    for start in range(0, len(qids), 40):
        url = ("https://www.wikidata.org/w/api.php?action=wbgetentities&format=json"
               "&props=claims|labels|descriptions|sitelinks&languages=en&ids="
               + "|".join(qids[start:start + 40]))
        out.update(get(url).get("entities") or {})
        time.sleep(0.15)
    return out


def claim_ids(entity, prop):
    out = []
    for claim in (entity.get("claims") or {}).get(prop, []):
        value = (claim.get("mainsnak", {}).get("datavalue") or {}).get("value") or {}
        if isinstance(value, dict) and value.get("id"):
            out.append(value["id"])
    return out


def coordinate(entity):
    for claim in (entity.get("claims") or {}).get("P625", []):
        value = (claim.get("mainsnak", {}).get("datavalue") or {}).get("value") or {}
        if "latitude" in value and "longitude" in value:
            return [round(value["latitude"], 4), round(value["longitude"], 4)]
    return None


def label(entity):
    return ((entity.get("labels") or {}).get("en") or {}).get("value")


def description(entity):
    return (((entity.get("descriptions") or {}).get("en") or {}).get("value") or "").lower()


def words(text):
    return {w for w in re.findall(r"[a-z]+", (text or "").lower()) if len(w) > 3}


def slim(qid, entity):
    return {"qid": qid, "label": label(entity), "desc": description(entity),
            "fame": len(entity.get("sitelinks") or {}), "coord": coordinate(entity),
            "p131": claim_ids(entity, "P131")[:2], "p17": claim_ids(entity, "P17")[:1]}


def gather(items):
    """Every candidate for every title, cached so the choosing can be redone for free."""
    cache = json.load(open(CANDIDATES)) if os.path.exists(CANDIDATES) else {}
    todo = [i for i in items if (i.get("title") or "") not in cache]
    print("  %d titles cached, %d to look up" % (len(cache), len(todo)))
    for number, item in enumerate(todo, 1):
        title = item.get("title") or ""
        if not title:
            continue
        try:
            found = entities(search(title)) if title else {}
        except RuntimeError as error:
            print("  ! %s — stopping, rerun to continue" % error)
            break
        cache[title] = [slim(q, e) for q, e in found.items()]
        if number % 25 == 0:
            json.dump(cache, open(CANDIDATES, "w"))
            print("  ...%d of %d" % (number, len(todo)))
    json.dump(cache, open(CANDIDATES, "w"))
    return cache


def usable(candidate, item):
    if not candidate.get("coord"):
        return False
    if any(bad in candidate["desc"] for bad in NOT_A_PLACE):
        return False
    name, title = (candidate.get("label") or "").lower(), (item.get("title") or "").lower()
    if not name:
        return False
    if name == title or words(name) == words(title):
        return True
    return bool(words(title)) and words(title) <= words(name)


def choose(candidates, item, admin):
    """The candidate the pack's own paragraph is about."""
    fact = (item.get("fact") or "").lower()
    good = [c for c in candidates if usable(c, item)]
    if not good:
        return None, "nothing usable"
    if fact:
        # The town named in the article beats everything. `admin` may not be filled in on
        # the first pass; the description carries the town too ("church in Milan"), and
        # that is enough to tell the candidates apart.
        named = []
        for candidate in good:
            towns = {admin.get(q, "") for q in candidate.get("p131") or []}
            towns.add(candidate["desc"].split(" in ")[-1].split(",")[0])
            if any(town and town.lower() in fact for town in towns):
                named.append(candidate)
        if named:
            return max(named, key=lambda c: c["fame"]), None
    return max(good, key=lambda c: c["fame"]), None


# Where the article says the thing is, in its own words. Wikipedia's opening sentence is
# written to a pattern — "in the Thuringian town of Arnstadt, Germany", "a church in
# Milan, northern Italy" — and where it names a town, that town is the answer.
TOWN_IN_FACT = [
    re.compile(r"\b(?:town|city|village|municipality|commune) of ([A-Z][\w'’\-]+(?: [A-Z][\w'’\-]+){0,2})"),
    re.compile(r"\bin (?:the )?([A-Z][\w'’\-]+(?: [A-Z][\w'’\-]+){0,2}), [A-Z]"),
]


def town_from_fact(fact):
    """The town the article names, if it names one plainly."""
    for pattern in TOWN_IN_FACT:
        found = pattern.search(fact or "")
        if found:
            name = found.group(1).strip()
            # "in the United States" and friends are countries, not towns.
            if name.lower() not in {"united", "north", "south", "east", "west", "old",
                                    "new", "the"}:
                return name
    return None


# Wikidata files cities under their administrative name — "Athens Municipality",
# "Stockholm Municipality", "Wellington Region". Nobody says that, and the question wants
# the word people use.
ADMIN_SUFFIX = re.compile(
    r"\s+(?:Municipality|Municipal District|Region|Province|County|Prefecture|"
    r"Metropolitan City|City Municipality|Urban District|Rural District)$", re.I)


def tidy_town(name):
    """"Athens Municipality" -> "Athens"."""
    if not name:
        return name
    shorter = ADMIN_SUFFIX.sub("", name).strip()
    # Only where something is left that is still a name: "Central Region" must not
    # become "Central".
    return shorter if len(shorter) > 3 else name


def recognisable(name, desc, country):
    """Whether this is a name worth putting in a question."""
    if not name:
        return False
    low = name.lower()
    if low in NOT_A_NAME:
        return False
    if any(f in low for f in TOO_FINE_NAME):
        return False
    if any(f in desc for f in TOO_FINE):
        return False
    # "Germany, Germany", "State Of Palestine, Palestine" — the chain climbed all the way
    # to the country, which is already being printed beside it. Containment rather than
    # equality, because the two often differ only in the formal wording.
    if country:
        other = country.lower()
        if low == other or low in other or other in low:
            return False
    return True


def place_name(candidate, item, admin, parents):
    """A town a person would recognise, and the country."""
    fact = (item.get("fact") or "").lower()
    country = next((admin[q] for q in candidate.get("p17") or [] if q in admin), None)

    # Walk up from the smallest unit until the name is one the article uses, or one that
    # calls itself a city.
    seen, queue = set(), list(candidate.get("p131") or [])
    best = None
    for _ in range(4):
        nxt = []
        for qid in queue:
            if qid in seen or qid not in admin:
                continue
            seen.add(qid)
            name, desc = admin[qid], parents.get(qid, {}).get("desc", "")
            if recognisable(name, desc, country):
                # The article's own word for where this is, which beats everything.
                if fact and name.lower() in fact:
                    return tidy_town(name), country
                if best is None and any(c in desc for c in CITY_LIKE):
                    best = name
            nxt.extend(parents.get(qid, {}).get("p131") or [])
        queue = nxt
    if best:
        return tidy_town(best), country
    # Nothing that calls itself a city on the way up: the smallest unit that is at least
    # a name somebody could be asked about.
    for qid in candidate.get("p131") or []:
        if qid in admin and recognisable(admin[qid], parents.get(qid, {}).get("desc", ""),
                                         country):
            return tidy_town(admin[qid]), country
    # No town worth naming. The country alone still makes a fair question — "which photo
    # is from Palestine" — and is better than a district nobody has heard of.
    return None, country


def resolve_admin(candidates):
    """Labels and parents for every administrative unit any candidate points at."""
    store = json.load(open(PLACES)) if os.path.exists(PLACES) else {}
    wanted = set()
    for rows in candidates.values():
        for c in rows:
            wanted.update(c.get("p131") or [])
            wanted.update(c.get("p17") or [])
    for _ in range(4):
        missing = sorted(q for q in wanted if q not in store)
        if not missing:
            break
        print("  naming %d administrative units" % len(missing))
        for q, e in entities(missing).items():
            store[q] = {"label": label(e), "desc": description(e),
                        "p131": claim_ids(e, "P131")[:2]}
        json.dump(store, open(PLACES, "w"))
        for q in missing:
            wanted.update(store.get(q, {}).get("p131") or [])
    json.dump(store, open(PLACES, "w"))
    return store


def main(write):
    pack = json.load(open(PACK))
    items = pack["items"]
    todo = [i for i in items if not (i.get("place") or "").strip()]
    print("%d landmarks, %d with no place" % (len(items), len(todo)))

    candidates = gather(todo)
    parents = resolve_admin(candidates)
    admin = {q: row["label"] for q, row in parents.items() if row.get("label")}

    written, refused, disagreed = 0, {}, 0
    for item in todo:
        rows = candidates.get(item.get("title") or "")
        if not rows:
            refused[item["id"]] = "nothing found"
            continue
        best, why = choose(rows, item, admin)
        if not best:
            refused[item["id"]] = why
            continue
        town, country = place_name(best, item, admin, parents)

        # The article names a town and we picked a different one. That is not a near
        # miss, it is the wrong building: "Church of Our Lady" is in Arnstadt according
        # to the pack's own paragraph, and the best-known church of that name is in
        # Dresden. Leaving it unplaced costs one landmark; writing Dresden makes the game
        # tell somebody something untrue.
        said = town_from_fact(item.get("fact") or "")
        if said and town and said.lower() not in town.lower() \
                and town.lower() not in said.lower():
            refused[item["id"]] = "article says %s, match says %s" % (said, town)
            continue

        place = ", ".join(p for p in (town, country) if p)
        if not place:
            refused[item["id"]] = "no name for its location"
            continue
        fact = (item.get("fact") or "").lower()
        if town and fact and town.lower() not in fact:
            disagreed += 1
        if write:
            item["place"] = place
            item["country"] = country
            item["latitude"], item["longitude"] = best["coord"]
        written += 1

    print("  placed %d, could not place %d" % (written, len(refused)))
    print("  %d of those name a town the article does not mention" % disagreed)
    if write:
        json.dump(pack, open(PACK, "w"), indent=1, ensure_ascii=False)
        done = sum(1 for i in items if (i.get("place") or "").strip())
        print("  written — %d of %d landmarks now have a place" % (done, len(items)))
    return candidates, admin, parents, refused


if __name__ == "__main__":
    main("--write" in sys.argv)
