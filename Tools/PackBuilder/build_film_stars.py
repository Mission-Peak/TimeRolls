#!/usr/bin/env python3
"""Build the Film Stars quiz pack: one photograph each of famous film actors and actresses.

Candidates come from Wikidata (humans whose occupation is actor or film actor, with a
picture and a birth date), ranked by how many Wikipedias cover them, with acting Oscar
winners and nominees nudged up. The pack is balanced across three eras of birth and
between actresses and actors, so a round always has fair distractors in the same cluster.

Facts carried per item (see quiz_common's docstring):

  films          every film Wikidata lists them in the cast of — the exclusion set
  notableFilms   up to six of those that are safe to ask about (>= 25 sitelinks and
                 >= 8 cast members on Wikidata, so the cast list is reasonably complete)
  oscarFor       films they won an acting Academy Award for (empty list = won none)
  firstOscarFor  the film of their earliest acting Oscar, or an empty list

Every intermediate step is cached in build/quiz-cache/film-stars-*.json, so a run that
Wikidata or Commons cuts short resumes where it stopped.

  python3 Tools/PackBuilder/build_film_stars.py            # build and write
  python3 Tools/PackBuilder/build_film_stars.py --dry-run  # build, print, write nothing
"""

import argparse, json, os, re, sys, time, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from quiz_common import (CACHE, sparql, entities, claim_ids, claim_year, label,
                         sitelink_count, commons_files, usable_photo, licence_ok, download,
                         wikipedia_intros, face_counts, Siglip, near_duplicates, write_pack,
                         qid, fetch_json)
import urllib.parse
from build_named_pack import NOT_THE_SUBJECT
from face_hints import hint_for

PACK_ID = "film-stars"

META = {
    "title": "Film Stars",
    "blurb": "Screen legends from the golden age of Hollywood to today.",
    "themes": ["film"],
    "namedSubjectPrompt": "Which person is {name}?|Which film star is {name}?",
    "questions": [
        {"id": "starred", "ask": "notableFilms", "exclude": "films",
         "prompt": "Who starred in {value}?|Which film star was in {value}?"},
        {"id": "firstOscar", "ask": "firstOscarFor", "exclude": "oscarFor",
         "prompt": "Who won their first Oscar for {value}?|Which star won their first Oscar for {value}?"},
    ],
}

# How many of each era ship, split evenly between actresses and actors: about 40 / 30 / 30.
QUOTA = {"golden age": 92, "mid-century": 69, "modern": 69}
POOL_PER_CLUSTER = 170          # how deep into each cluster's ranking we look at all
MIN_FILMS = 8                   # fewer cast credits than this is not a film star
MIN_SITELINKS = 30

# Hand-checked exceptions to the ranking, each with its reason.
SKIP = {
    # 224 sitelinks — more than DiCaprio — mostly bot-made stubs from early in Wikipedia's
    # life; he ranked first among modern actors and is known for one TV film series.
    "Q4617": "Corbin Bleu",
    # Not "film stars" to an older audience: famous for something else, or for teen films.
    "Q193426": "Nancy Reagan",
    "Q83287": "Selena Gomez",
    "Q151892": "Ariana Grande",
    "Q23359": "Taylor Lautner",
    "Q19794": "Josh Duhamel",
    "Q272935": "Estelle Harris",
}

FEMALE, MALE = "Q6581072", "Q6581097"
ACTING_OSCARS = {"Q103916", "Q103618", "Q106291", "Q106301"}

GOOD = ["a photograph of a person", "a portrait photograph of an actor"]
BAD = ["a statue or sculpture", "a drawing, a diagram or a page of text",
       "a poster or a magazine cover", "a group of people"]


# MARK: - Cache

def cache_path(name):
    os.makedirs(CACHE, exist_ok=True)
    return os.path.join(CACHE, f"film-stars-{name}.json")


def cached(name, default):
    path = cache_path(name)
    if os.path.exists(path):
        return json.load(open(path))
    return default


def save(name, value):
    path = cache_path(name)
    with open(path + ".tmp", "w") as handle:
        json.dump(value, handle, ensure_ascii=False)
    os.replace(path + ".tmp", path)


def patient_sparql(query, what):
    """A query, retried with long rests: a refusal must not become a thinner pack."""
    wait = 60
    for attempt in range(6):
        rows = sparql(query)
        if rows is not None:
            return rows
        print(f"  Wikidata refused {what}; resting {wait}s", flush=True)
        time.sleep(wait)
        wait = min(wait * 2, 600)
    sys.exit(f"Wikidata kept refusing {what} — stopping rather than writing a thinner pack")


# MARK: - Helpers

def era_of(year):
    if year < 1930:
        return "golden age"
    if year < 1960:
        return "mid-century"
    return "modern"


def slug(name):
    folded = unicodedata.normalize("NFKD", name.lower())
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", "-", folded).strip("-")


def film_string(title, year):
    return f"{title} ({year})" if title and year else None


def birth_month(entity):
    for statement in (entity.get("claims") or {}).get("P569", []):
        if statement.get("rank") == "deprecated":
            continue
        value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if isinstance(value, dict) and "time" in value:
            if value.get("precision", 0) >= 10:
                try:
                    month = int(value["time"][6:8])
                    if 1 <= month <= 12:
                        return month
                except ValueError:
                    pass
            return 6
    return 6


def earliest_year(entity, prop="P577"):
    years = []
    for statement in (entity.get("claims") or {}).get(prop, []):
        if statement.get("rank") == "deprecated":
            continue
        value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if isinstance(value, dict) and "time" in value:
            try:
                years.append(int(value["time"][1:5]))
            except ValueError:
                pass
    return min(years) if years else None


def trim(entity):
    """Keep only what the build reads, so the cache stays small."""
    claims = entity.get("claims") or {}
    return {"labels": {"en": (entity.get("labels") or {}).get("en")} if label(entity) else {},
            "sitelinks": {k: 1 for k in (entity.get("sitelinks") or {})},
            "claims": {p: claims[p] for p in ("P21", "P569", "P18", "P166", "P1411", "P577",
                                               "P106") if p in claims}}


IS_A = re.compile(r"\b(?:is|was) (?:an?|the)\b(.{0,140})", re.I)


# Occupations that, named before "actor", say acting was the sideline: Madonna is "an
# American singer, songwriter, and actress", Eva Peron "an Argentine politician, activist,
# actress". Comedian, dancer and model are not here: Groucho Marx was a comedian first and
# a film star all the same.
OTHER_CALLINGS = re.compile(
    r"\b(?:singer|songwriter|singer-songwriter|rapper|musician|pianist|chansonnier|bard|"
    r"politician|activist|first lady|host|presenter|broadcaster|personality|socialite|"
    r"filmmaker|director|producer|screenwriter|writer|poet|novelist|playwright|dramatist|"
    r"businessman|businesswoman|entrepreneur|wrestler|footballer|boxer|media)\b", re.I)


def called_an_actor(fact, oscar_nominee=False):
    """Whether the article's defining clause says actor or actress — first, before any
    other calling, unless an acting Oscar nomination settles it (Sinatra, Crosby, Cher).
    Wikidata lists "actor" for anybody with a cameo — Trump, Hitchcock, Pele — and the
    article does not."""
    found = IS_A.search(fact or "")
    if not found:
        return False
    clause = found.group(1)
    acting = re.search(r"\bact(?:or|ress)\b", clause, re.I)
    if not acting:
        return False
    if oscar_nominee:
        return True
    other = OTHER_CALLINGS.search(clause)
    return not other or acting.start() < other.start()


def not_the_subject(file_title):
    """build_named_pack's rule: a statue, grave, stamp or waxwork is not the person."""
    title = unicodedata.normalize("NFKD", file_title.lower())
    title = "".join(ch for ch in title if not unicodedata.combining(ch))
    title = title.removeprefix("file:").rsplit(".", 1)[0]
    words = set("".join(ch if ch.isalnum() else " " for ch in title).split())
    for unwanted in NOT_THE_SUBJECT:
        if (" " in unwanted and unwanted in title) or unwanted in words:
            return unwanted
    return None


# MARK: - Steps

def candidates():
    found = cached("candidates", None)
    if found:
        return found
    rows = patient_sparql(f"""
        SELECT ?item ?n ?b ?g WHERE {{
          VALUES ?occ {{ wd:Q33999 wd:Q10800557 }}
          ?item wdt:P106 ?occ ; wikibase:sitelinks ?n .
          FILTER(?n >= {MIN_SITELINKS})
          ?item wdt:P31 wd:Q5 ; wdt:P18 ?img ; wdt:P569 ?b ; wdt:P21 ?g .
          FILTER(YEAR(?b) >= 1885 && YEAR(?b) <= 2000)
        }}""", "the candidate list")
    out = {}
    for row in rows:
        item = qid(row["item"])
        gender = qid(row["g"])
        entry = out.setdefault(item, {"n": int(row["n"]), "born": int(row["b"][:4]),
                                      "genders": []})
        if gender not in entry["genders"]:
            entry["genders"].append(gender)
    save("candidates", out)
    return out


def pool(found):
    """The top of each cluster by sitelinks — all we will ever look deeper at."""
    clusters = {}
    for item, entry in found.items():
        if entry["genders"] not in ([FEMALE], [MALE]):
            continue
        noun = "actress" if entry["genders"] == [FEMALE] else "actor"
        clusters.setdefault(f"{noun} {era_of(entry['born'])}", []).append(item)
    chosen = []
    for members in clusters.values():
        members.sort(key=lambda q: -found[q]["n"])
        chosen.extend(members[:POOL_PER_CLUSTER])
    return chosen


def people(ids):
    have = cached("people", {})
    missing = [q for q in ids if q not in have]
    if missing:
        print(f"fetching {len(missing)} people from Wikidata", flush=True)
        for start in range(0, len(missing), 200):
            batch = missing[start:start + 200]
            got = entities(batch)
            have.update({q: trim(e) for q, e in got.items() if "missing" not in e})
            save("people", have)
    return have


def filmographies(ids):
    """{actor: [[film qid, label, year, sitelinks], ...]} — every film they are cast in."""
    have = cached("films", {})
    missing = [q for q in ids if q not in have]
    for start in range(0, len(missing), 20):
        batch = missing[start:start + 20]
        print(f"  filmographies {start + len(batch)}/{len(missing)}", flush=True)
        rows = patient_sparql(f"""
            SELECT ?actor ?film ?fn (MIN(YEAR(?d)) AS ?y) (SAMPLE(?l) AS ?label) WHERE {{
              VALUES ?actor {{ {' '.join('wd:' + q for q in batch)} }}
              ?film wdt:P161 ?actor ; wdt:P31 ?t ; wikibase:sitelinks ?fn .
              ?t wdt:P279* wd:Q11424 .
              OPTIONAL {{ ?film wdt:P577 ?d }}
              OPTIONAL {{ ?film rdfs:label ?l FILTER(LANG(?l) = "en") }}
            }} GROUP BY ?actor ?film ?fn""", "a filmography batch")
        for q in batch:
            have[q] = []
        seen = set()
        for row in rows:
            key = (row["actor"], row["film"])
            if key in seen:
                continue
            seen.add(key)
            have[qid(row["actor"])].append([
                qid(row["film"]), row.get("label"),
                int(row["y"]) if row.get("y") else None, int(row["fn"])])
        save("films", have)
        time.sleep(1.5)
    return have


def cast_sizes(film_ids):
    have = cached("cast", {})
    missing = [f for f in film_ids if f not in have]
    for start in range(0, len(missing), 150):
        batch = missing[start:start + 150]
        print(f"  cast sizes {start + len(batch)}/{len(missing)}", flush=True)
        rows = patient_sparql(f"""
            SELECT ?film (COUNT(DISTINCT ?c) AS ?n) WHERE {{
              VALUES ?film {{ {' '.join('wd:' + f for f in batch)} }}
              ?film wdt:P161 ?c .
            }} GROUP BY ?film""", "a cast-size batch")
        for f in batch:
            have[f] = 0
        for row in rows:
            have[qid(row["film"])] = int(row["n"])
        save("cast", have)
        time.sleep(1.5)
    return have


def english_labels(ids):
    """Labels in English, or Wikidata's language-neutral "mul" label where the English one
    has been folded into it — Forrest Gump and Iron Man have only "mul" now, and
    `entities` asks for English alone."""
    have = cached("labels", {})
    missing = [q for q in dict.fromkeys(ids) if q not in have]
    for start in range(0, len(missing), 50):
        batch = missing[start:start + 50]
        data = fetch_json("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(batch), "props": "labels",
            "languages": "en|mul", "format": "json"}))
        if data is None:
            sys.exit("Wikidata refused a label lookup — stopping rather than guessing")
        for q in batch:
            labels = ((data.get("entities") or {}).get(q) or {}).get("labels") or {}
            have[q] = ((labels.get("en") or labels.get("mul")) or {}).get("value")
        save("labels", have)
        time.sleep(0.4)
    return have


def voice_or_cameo(ids):
    """{actor: [film qids]} where Wikidata marks the part as voice-only or a cameo.

    Voice parts are mostly recorded with P725 "voice actor" on the film (often alongside a
    P161 cast entry); cameo and uncredited parts show up, rarely, as a P161 qualifier —
    P2868 "subject has role", P453 "character role" or P4633 "name of the character role".
    """
    have = cached("roles", {})
    missing = [q for q in ids if q not in have]
    for start in range(0, len(missing), 25):
        batch = missing[start:start + 25]
        print(f"  voice / cameo parts {start + len(batch)}/{len(missing)}", flush=True)
        rows = patient_sparql(f"""
            SELECT DISTINCT ?film ?actor WHERE {{
              VALUES ?actor {{ {' '.join('wd:' + q for q in batch)} }}
              {{ ?film wdt:P725 ?actor . }}
              UNION
              {{ ?film p:P161 ?st . ?st ps:P161 ?actor ; pq:P2868|pq:P453 ?r .
                 ?r rdfs:label ?l .
                 FILTER(LANG(?l) = "en" && REGEX(?l, "voice|cameo|uncredited", "i")) }}
              UNION
              {{ ?film p:P161 ?st . ?st ps:P161 ?actor ; pq:P4633 ?l .
                 FILTER(REGEX(STR(?l), "voice|cameo|uncredited", "i")) }}
            }}""", "a voice/cameo batch")
        for q in batch:
            have[q] = []
        for row in rows:
            have[qid(row["actor"])].append(qid(row["film"]))
        save("roles", have)
        time.sleep(1.5)
    return have


ACTING = re.compile(r"\bact(?:or|ress)\b", re.I)
SIDE_CALLINGS = re.compile(OTHER_CALLINGS.pattern[:-3] +
                           r"|comedian|dancer|artist|mogul|model|entertainer)\b",
                           re.I)


def acting_hint(hint, noun):
    """The mined hint, unless it names some other calling before acting — "an American
    singer" for Sinatra — in which case "an American actor", keeping the nationality."""
    if not hint:
        return hint
    acting = ACTING.search(hint)
    other = SIDE_CALLINGS.search(hint)
    if acting and (not other or acting.start() < other.start()):
        return hint
    words = hint.split()[1:]
    nationality = []
    for word in words:
        if not word[:1].isupper():
            break
        nationality.append(word)
    phrase = " ".join(nationality + [noun])
    return ("an " if phrase[0].lower() in "aeiou" else "a ") + phrase


def oscar_wins(entity):
    """[(film qid, year of the award or None)] for every acting Oscar won."""
    out = []
    for statement in (entity.get("claims") or {}).get("P166", []):
        if statement.get("rank") == "deprecated":
            continue
        value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if not (isinstance(value, dict) and value.get("id") in ACTING_OSCARS):
            continue
        qualifiers = statement.get("qualifiers") or {}
        works = [((s.get("datavalue") or {}).get("value") or {}).get("id")
                 for s in qualifiers.get("P1686", [])]
        when = None
        for s in qualifiers.get("P585", []):
            v = (s.get("datavalue") or {}).get("value")
            if isinstance(v, dict) and "time" in v:
                when = int(v["time"][1:5])
        for work in works:
            if work:
                out.append((work, when))
    return out


def nominated(entity):
    return any(q in ACTING_OSCARS for q in claim_ids(entity, "P1411"))


def film_entities(ids):
    have = cached("oscar-films", {})
    missing = [q for q in ids if q not in have]
    if missing:
        got = entities(missing, props="labels|claims")
        for q, e in got.items():
            have[q] = [label(e), earliest_year(e)]
        save("oscar-films", have)
    return have


def photo_infos(files):
    have = cached("commons", {})
    missing = [f for f in files if f not in have]
    if missing:
        print(f"fetching {len(missing)} Commons file records", flush=True)
        for start in range(0, len(missing), 200):
            got = commons_files(missing[start:start + 200])
            for name in missing[start:start + 200]:
                have[name] = got.get(name)
            save("commons", have)
    return have


def intros(ids):
    have = cached("intros", {})
    missing = [q for q in ids if q not in have]
    if missing:
        print(f"fetching {len(missing)} Wikipedia intros", flush=True)
        got = wikipedia_intros(missing)
        for q in missing:
            have[q] = list(got[q]) if q in got else None
        save("intros", have)
    return have


def faces(paths):
    have = cached("faces", {})
    missing = [p for p in paths if p not in have]
    if missing:
        print(f"counting faces in {len(missing)} photographs", flush=True)
        have.update(face_counts(missing))
        save("faces", have)
    return have


# MARK: - Build

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dup-threshold", type=float, default=0.92)
    args = parser.parse_args()

    found = candidates()
    print(f"{len(found)} candidate actors with >= {MIN_SITELINKS} sitelinks")
    ids = pool(found)
    print(f"{len(ids)} in the pool")
    folks = people(ids)
    films = filmographies(ids)
    texts = intros([q for q in ids if len(films.get(q, [])) >= MIN_FILMS])

    # Rank: sitelinks, nudged up for an acting Oscar win or nomination.
    ranked = []
    rejected = {}
    def reject(rule, who):
        rejected.setdefault(rule, []).append(who)

    names = english_labels([q for q in ids if folks.get(q) and not label(folks[q])])
    unlabelled = [f[0] for q in ids for f in films.get(q, []) if not f[1]]
    film_labels = english_labels(unlabelled)
    for q in ids:
        for f in films.get(q, []):
            if not f[1]:
                f[1] = film_labels.get(f[0])
    for q in ids:
        e = folks.get(q)
        name = (label(e) or names.get(q)) if e else None
        if not name:
            reject("no English label", q)
            continue
        if q in SKIP:
            reject("hand-skipped (see SKIP)", name)
            continue
        if len(films.get(q, [])) < MIN_FILMS:
            reject(f"fewer than {MIN_FILMS} films on Wikidata", name)
            continue
        if not texts.get(q):
            reject("6 no Wikipedia fact", name)
            continue
        if not called_an_actor(texts[q][0], bool(oscar_wins(e)) or nominated(e)):
            reject("0 Wikipedia does not call them an actor", name)
            continue
        genders = claim_ids(e, "P21")
        if genders not in ([FEMALE], [MALE]):
            reject("gender not plainly female/male", name)
            continue
        born = claim_year(e, "P569")
        # 1885 rather than 1890, or Charlie Chaplin (1889) is not a film star.
        if not born or not 1885 <= born <= 2000:
            reject("birth year outside 1885-2000", name)
            continue
        wins = oscar_wins(e)
        score = sitelink_count(e) * (1.25 if wins else 1.1 if nominated(e) else 1.0)
        noun = "actress" if genders == [FEMALE] else "actor"
        ranked.append({"q": q, "name": name, "born": born, "score": score,
                       "cluster": f"{noun} {era_of(born)}", "wins": wins, "entity": e})
    ranked.sort(key=lambda r: -r["score"])

    # Facts for everybody still in the running.
    film_ids = sorted({f[0] for r in ranked for f in films[r["q"]] if f[3] >= 25})
    casts = cast_sizes(film_ids)
    sidelines = voice_or_cameo([r["q"] for r in ranked])
    oscar_film_ids = sorted({w for r in ranked for w, _ in r["wins"]})
    oscar_films = film_entities(oscar_film_ids)
    oscar_labels = english_labels([f for f, v in oscar_films.items() if not v[0]])
    for f, v in oscar_films.items():
        if not v[0]:
            v[0] = oscar_labels.get(f)
    known_films = {f[0]: (f[1], f[2]) for r in ranked for f in films[r["q"]]}

    def film_name(f):
        title, year = known_films.get(f) or tuple(oscar_films.get(f) or (None, None))
        return film_string(title, year)

    for r in ranked:
        mine = films[r["q"]]
        r["films"] = sorted({s for f in mine if (s := film_string(f[1], f[2]))})
        # A voice part or a cameo is not "starring": those films stay in `films` (so the
        # person is still never a wrong answer for them) but are never asked about.
        skip_roles = set(sidelines.get(r["q"], []))
        notable = [f for f in mine if f[3] >= 25 and casts.get(f[0], 0) >= 8
                   and f[0] not in skip_roles
                   and film_string(f[1], f[2])]
        notable.sort(key=lambda f: -f[3])
        picked = []
        for f in notable:
            s = film_string(f[1], f[2])
            if s not in picked:
                picked.append(s)
            if len(picked) == 6:
                break
        r["notable"] = picked
        wins = []
        for work, when in r["wins"]:
            s = film_name(work)
            if s:
                year = when or (known_films.get(work) or oscar_films.get(work) or
                                [None, None])[1] or 9999
                wins.append((year, s))
        wins.sort()
        r["oscarFor"] = list(dict.fromkeys(s for _, s in wins))
        r["firstOscarFor"] = [wins[0][1]] if wins else []
        # Sitelinks flatter pop stars and teen-TV actors, whose names travel further than
        # their films. Weigh in how widely their best-known film is covered, so the pack
        # leans to people known *for films*.
        best_film = max((f[3] for f in mine if f[3] >= 25 and casts.get(f[0], 0) >= 8),
                        default=0)
        r["score"] *= 0.6 + 0.4 * min(1.0, best_film / 80)

    for r in [r for r in ranked if not r["notable"] and not r["firstOscarFor"]]:
        reject("nothing to ask: no notable film, no Oscar", r["name"])
    ranked = [r for r in ranked if r["notable"] or r["firstOscarFor"]]
    ranked.sort(key=lambda r: -r["score"])

    # Photographs: the P18 file, through Commons and the licence check.
    first_file = {}
    for r in ranked:
        files = [v for v in (claim_ids_values(r["entity"], "P18")) if isinstance(v, str)]
        if files:
            first_file[r["q"]] = files[0]
    infos = photo_infos(sorted(set(first_file.values())))

    siglip = None
    vector_store = load_vectors()
    vectors_cache = {}
    face_cache = cached("faces", {})
    passed = {c: [] for c in {r["cluster"] for r in ranked}}
    want = {}
    for era, n in QUOTA.items():
        want[f"actress {era}"] = n // 2
        want[f"actor {era}"] = n - n // 2
    margin = 6  # passes beyond the quota, to absorb near-duplicate drops

    by_cluster = {}
    for r in ranked:
        by_cluster.setdefault(r["cluster"], []).append(r)

    for cluster, members in sorted(by_cluster.items()):
        queue = list(members)
        while queue and len(passed[cluster]) < want.get(cluster, 0) + margin:
            chunk, queue = queue[:40], queue[40:]
            ready = []
            for r in chunk:
                file = first_file.get(r["q"])
                info = infos.get(file) if file else None
                if not file or not info:
                    reject("1 no usable P18 file", r["name"])
                    continue
                if not usable_photo(info) or not licence_ok(info["license"]):
                    reject("1 licence / size / format", f"{r['name']} ({info['license']}, "
                           f"{info['width']}x{info['height']})")
                    continue
                if (word := not_the_subject(info["file"])):
                    reject("2 file title says not the subject", f"{r['name']}: "
                           f"{info['file']} [{word}]")
                    continue
                if not texts.get(r["q"]):
                    reject("6 no Wikipedia fact", r["name"])
                    continue
                path = download(info["url"])
                if not path:
                    reject("1 download failed", r["name"])
                    continue
                r["info"], r["path"] = info, path
                ready.append(r)
            missing = [r["path"] for r in ready if r["path"] not in face_cache]
            if missing:
                face_cache.update(face_counts(missing))
                save("faces", face_cache)
            for r in ready:
                count = face_cache.get(r["path"])
                if not count:
                    reject("3 face detector could not read", r["name"])
                    continue
                if count["faces"] != 1:
                    reject("3 not exactly one face", f"{r['name']} ({int(count['faces'])})")
                    continue
                if count["largest"] < 0.02:
                    reject("3 face too small", f"{r['name']} ({count['largest']:.3f})")
                    continue
                if siglip is None:
                    print("loading SigLIP", flush=True)
                    siglip = Siglip()
                vector = vector_store.get(os.path.basename(r["path"]))
                if vector is None:
                    vector = siglip.images([r["path"]]).get(r["path"])
                    if vector is not None:
                        vector_store[os.path.basename(r["path"])] = vector
                if vector is None:
                    reject("4 SigLIP could not read", r["name"])
                    continue
                good, _ = siglip.prefers(vector, GOOD, BAD)
                if not good:
                    reject("4 SigLIP: not a photograph of a person", r["name"])
                    continue
                vectors_cache[r["q"]] = vector
                passed[cluster].append(r)
        print(f"  {cluster:<22} {len(passed[cluster])} passed (want {want.get(cluster)})",
              flush=True)

    save_vectors(vector_store)

    # Near-duplicates across everyone who passed, then the quotas.
    # Ordered best-known first, so of any pair the better-known star is the one kept.
    candidates_passed = sorted((r for c in passed.values() for r in c),
                               key=lambda r: -r["score"])
    dupes = near_duplicates({r["q"]: vectors_cache[r["q"]] for r in candidates_passed},
                            args.dup_threshold)
    import numpy as np
    for r in candidates_passed:
        if r["q"] in dupes:
            twin = max((o for o in candidates_passed if o["q"] not in dupes and o is not r),
                       key=lambda o: float(np.dot(vectors_cache[o["q"]],
                                                  vectors_cache[r["q"]])))
            similarity = float(np.dot(vectors_cache[twin["q"]], vectors_cache[r["q"]]))
            reject("5 near-duplicate photograph",
                   f"{r['name']} ~ {twin['name']} ({similarity:.3f})")

    items, seen = [], set()
    for cluster in sorted(passed):
        kept = [r for r in passed[cluster] if r["q"] not in dupes]
        for r in kept[:want.get(cluster, 0)]:
            if r["q"] in seen:
                reject("7 duplicate person", r["name"])
                continue
            seen.add(r["q"])
            items.append(make_item(r, folks[r["q"]], texts[r["q"]]))
    items.sort(key=lambda i: -i["knownBy"])

    save("rejections", rejected)
    print("\nREJECTIONS (all of them: build/quiz-cache/film-stars-rejections.json)")
    for rule in sorted(rejected):
        print(f"  {len(rejected[rule]):4}  {rule}")
        for example in rejected[rule][:(12 if rule.startswith("5") else 4)]:
            print(f"          e.g. {example}")

    print(f"\n{len(items)} items")
    for cluster in sorted(passed):
        print(f"  {cluster:<22} {sum(1 for i in items if i['cluster'] == cluster)}")
    print(f"  with notableFilms: {sum(1 for i in items if i['facts']['notableFilms'])}")
    print(f"  with an acting Oscar: {sum(1 for i in items if i['facts']['oscarFor'])}")
    print(f"  with a group hint: {sum(1 for i in items if i.get('group'))}")

    for cluster in sorted(passed):
        print(f"\n{cluster}: " + ", ".join(i["title"] for i in items
                                            if i["cluster"] == cluster))
    if not args.dry_run:
        write_pack(PACK_ID, META, items, force=args.force)


def load_vectors():
    import numpy as np
    path = cache_path("vectors").replace(".json", ".npz")
    if not os.path.exists(path):
        return {}
    data = np.load(path)
    return {key: data[key] for key in data.files}


def save_vectors(store):
    import numpy as np
    path = cache_path("vectors").replace(".json", ".npz")
    np.savez(path, **store)


def claim_ids_values(entity, prop):
    out = []
    for statement in (entity.get("claims") or {}).get(prop, []):
        if statement.get("rank") == "deprecated":
            continue
        value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if value is not None:
            out.append((statement.get("rank") != "preferred", value))
    # Preferred rank first.
    return [value for _, value in sorted(out, key=lambda pair: pair[0])]


def make_item(r, entity, text):
    info = r["info"]
    fact, source = text
    item = {
        "id": f"{PACK_ID}-{slug(r['name'])}",
        "subjectID": r["q"],
        "title": r["name"],
        "objectTags": [],
        "remoteURL": info["url"],
        "year": r["born"],
        "month": birth_month(entity),
        "credit": info["credit"] or "Wikimedia Commons contributor",
        "source": "Wikimedia Commons",
        "sourceURL": info["sourceURL"],
        "license": info["license"],
        "licenseURL": info["licenseURL"],
        "isResizedCopy": True,
        "knownBy": sitelink_count(entity),
        "creator": None,
        "creatorDied": None,
        "latitude": None,
        "longitude": None,
        "fact": fact,
        "factSource": source,
    }
    item["group"] = acting_hint(hint_for(item), r["cluster"].split()[0])
    item["cluster"] = r["cluster"]
    item["facts"] = {
        "films": r["films"],
        "notableFilms": r["notable"],
        "oscarFor": r["oscarFor"],
        "firstOscarFor": r["firstOscarFor"],
    }
    return item


if __name__ == "__main__":
    main()
