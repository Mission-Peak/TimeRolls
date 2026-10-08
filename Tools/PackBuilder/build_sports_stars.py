#!/usr/bin/env python3
"""Build the Sports Stars pack: one photograph each of about two hundred athletes.

Candidates come from Wikidata (people with a sport or a sports occupation, a picture and a
birth date), ranked by how many Wikipedias write about them, with a nudge for Hall of
Famers and MVPs. Each sport has a quota, so the pack leans American — football, baseball
and basketball first — the way its players do.

Facts, and where each one comes from:

* `teams`     — P54 member of sports team, kept only for notable professional clubs
                (20+ sitelinks), never national, college, youth or reserve sides. Stored the
                way English says it after "Who played for": "the New York Yankees", but
                "Real Madrid".
* `teamsAny`  — what rules a wrong option out of a team round: every P54 team of any
                notability (only national and youth sides left out), plus the franchise's
                other names — Wikidata's replaces / replaced by / owner / parent links, its
                aliases, and for North American clubs any notable club of the same sport and
                nickname. Babe Ruth's "Boston Braves" is an item of its own that links to
                nothing, and the nickname is what keeps him out of an Atlanta Braves round.
* `position`  — P413, said the way a fan says it, and only the player's one primary
                position: the preferred-rank statement, or the only one listed. Several
                equal positions, or a vague one ("guard"), and the key is left out.
* `positionAny` — what rules a wrong option out: every position listed, a vague one
                counted as everything it could mean ("guard" is point guard and shooting
                guard). Left out if a listed position is one the tables do not know.
* `honours`   — a short curated list of MVP-style awards. Wikidata's award statements are
                patchy, so each award is the union of P166 and the English Wikipedia
                category of its winners; present (possibly empty) for every athlete of a
                sport the awards belong to.
* `hallOfFame`— the sport's own Hall of Fame, same union (Wikidata P166/P463 and the
                Wikipedia inductee category). Wikidata alone lists barely a third of the
                baseball Hall, and missed Michael Jordan.

  python3 Tools/PackBuilder/build_sports_stars.py            # build and write
  python3 Tools/PackBuilder/build_sports_stars.py --dry-run  # build, report, write nothing
"""

import argparse, json, os, re, sys, time, unicodedata, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import quiz_common as q
from build_named_pack import NOT_THE_SUBJECT
from face_hints import hint_for

PACK_ID = "sports-stars"

# sport → (occupations, P641 sports, sitelink floor for the query, quota in the pack)
SPORTS = {
    "American football": (["Q19204627"], ["Q41323"], 6, 58),
    "baseball": (["Q10871364"], ["Q5369"], 8, 47),
    "basketball": (["Q3665646"], ["Q5372"], 25, 47),
    "ice hockey": (["Q11774891"], ["Q41466"], 25, 19),
    "soccer": (["Q937857"], ["Q2736"], 70, 19),
    "tennis": (["Q10833314"], ["Q847"], 35, 15),
    "golf": (["Q11303721", "Q490253"], ["Q5377", "Q7248073"], 8, 12),
    "boxing": (["Q11338576"], ["Q32112"], 25, 14),
}

# Each sport's Hall: Wikidata item and English Wikipedia inductee category.
HALLS = {
    "American football": ("Pro Football Hall of Fame", "Q778412",
                          "Pro Football Hall of Fame inductees"),
    "baseball": ("National Baseball Hall of Fame", "Q809892",
                 "National Baseball Hall of Fame inductees"),
    "basketball": ("Naismith Basketball Hall of Fame", "Q290922",
                   "Naismith Memorial Basketball Hall of Fame inductees"),
    "ice hockey": ("Hockey Hall of Fame", "Q1136687", "Hockey Hall of Fame inductees"),
    "tennis": ("International Tennis Hall of Fame", "Q52454",
               "International Tennis Hall of Fame inductees"),
    "golf": ("World Golf Hall of Fame", "Q258851", "World Golf Hall of Fame inductees"),
    "boxing": ("International Boxing Hall of Fame", "Q572227",
               "International Boxing Hall of Fame inductees"),
}

# Honours, phrased to read in "Who was named {value}?":
# value → (sport, Wikidata award items, English Wikipedia winner categories)
HONOURS = {
    "Super Bowl MVP": ("American football", ["Q1079382"], ["Super Bowl MVPs"]),
    "NFL MVP": ("American football", ["Q289678", "Q28455235"],
                ["NFL Most Valuable Player winners"]),
    "World Series MVP": ("baseball", ["Q1372040"],
                         ["World Series Most Valuable Player Award winners"]),
    "MLB MVP": ("baseball", ["Q1514249"],
                ["American League Most Valuable Player Award winners",
                 "National League Most Valuable Player Award winners"]),
    "NBA Finals MVP": ("basketball", ["Q739499"], []),
    "NBA MVP": ("basketball", ["Q222047"], ["NBA Most Valuable Player Award winners"]),
    "the Conn Smythe Trophy winner": ("ice hockey", ["Q176834"], ["Conn Smythe Trophy winners"]),
    "the Hart Trophy winner": ("ice hockey", ["Q678383"], ["Hart Memorial Trophy winners"]),
    "the Ballon d'Or winner": ("soccer", ["Q166177", "Q2291862"], ["Ballon d'Or winners"]),
}
HONOUR_SPORTS = {sport for sport, _, _ in HONOURS.values()}
TEAM_SPORTS = {"American football", "baseball", "basketball", "ice hockey", "soccer"}
NORTH_AMERICA = {"Q30", "Q16"}

# P413 label → what a fan says. None = too vague to rule anyone out (the key is dropped
# if that is all a player has). Labels missing from the table are treated like None and
# printed, so the table can grow.
POSITIONS = {
    "American football": {
        "quarterback": ["quarterback"], "running back": ["running back"],
        "halfback": ["running back"], "fullback": ["fullback", "running back"],
        "wide receiver": ["wide receiver"], "tight end": ["tight end"],
        "linebacker": ["linebacker"], "middle linebacker": ["linebacker"],
        "outside linebacker": ["linebacker"], "inside linebacker": ["linebacker"],
        "cornerback": ["cornerback"], "safety": ["safety"], "free safety": ["safety"],
        "strong safety": ["safety"], "defensive end": ["defensive end"],
        "defensive tackle": ["defensive tackle"], "nose tackle": ["defensive tackle"],
        "offensive tackle": ["offensive tackle"], "tackle": ["offensive tackle"],
        "offensive guard": ["guard"], "guard": ["guard"], "center": ["center"],
        "placekicker": ["kicker"], "kicker": ["kicker"], "punter": ["punter"],
        "return specialist": None, "kick returner": None, "punt returner": None,
        "defensive back": None, "offensive lineman": None, "defensive lineman": None,
        "lineman": None, "end": None, "back": None, "wingback": None, "tailback": ["running back"],
        "split end": ["wide receiver"], "flanker": ["wide receiver"],
    },
    "baseball": {
        "pitcher": ["pitcher"], "starting pitcher": ["pitcher"], "relief pitcher": ["pitcher"],
        "closer": ["pitcher"], "catcher": ["catcher"], "first baseman": ["first base"],
        "second baseman": ["second base"], "third baseman": ["third base"],
        "shortstop": ["shortstop"], "outfielder": ["the outfield"],
        "left fielder": ["the outfield"], "center fielder": ["the outfield"],
        "centerfielder": ["the outfield"], "right fielder": ["the outfield"],
        "designated hitter": ["designated hitter"], "infielder": None,
        "utility player": None, "manager": None,
    },
    "basketball": {
        "point guard": ["point guard"], "shooting guard": ["shooting guard"],
        "small forward": ["small forward"], "power forward": ["power forward"],
        "center": ["center"], "centre": ["center"], "guard": None, "forward": None,
        "swingman": [], "point forward": [], "combo guard": [], "forward-center": None,
        "forward–center": None, "guard-forward": None,
    },
    "ice hockey": {
        "goaltender": ["goaltender"], "goalkeeper": ["goaltender"], "defenceman": ["defense"],
        "defenseman": ["defense"], "defender": ["defense"], "centre": ["center"],
        "center": ["center"], "left wing": ["left wing"], "left winger": ["left wing"],
        "right wing": ["right wing"], "right winger": ["right wing"], "winger": None,
        "forward": None, "wing": None, "rover": None,
    },
    "soccer": {
        "goalkeeper": ["goalkeeper"], "defender": ["defense"], "centre-back": ["defense"],
        "center-back": ["defense"], "full-back": ["defense"], "fullback": ["defense"],
        "wing-back": ["defense"], "sweeper": ["defense"], "libero": ["defense"],
        "left-back": ["defense"], "right-back": ["defense"],
        "midfielder": ["midfield"], "defensive midfielder": ["midfield"],
        "attacking midfielder": ["midfield"], "central midfielder": ["midfield"],
        "wide midfielder": ["midfield"], "wing half": ["midfield"], "half-back": ["midfield"],
        "playmaker": ["midfield"], "forward": ["forward"], "striker": ["forward"],
        "centre-forward": ["forward"], "center forward": ["forward"],
        "winger": ["forward"], "second striker": ["forward"], "inside forward": ["forward"],
        "false nine": ["forward"], "outside forward": ["forward"],
    },
}

TEAM_NOT_PRO = ("national", "olympic", "under-", "under ", "u-1", "u-2", "u1", "u2",
                "college", "university", "youth", "reserve", "academy", "junior",
                "atlètic", "castilla", "all-star", "high school", " men's", " women's",
                "free agent")
KIND_NOT_PRO = ("national", "olympic", "college", "university", "youth", "reserve",
                "academy", "junior", "under-")
# A second or third side: "FC Barcelona B", "Real Madrid Castilla", "Bayern Munich II".
TEAM_SECOND_SIDE = re.compile(r"\s(?:b|c|ii|iii)$", re.I)
TEAM_SUFFIXES = (" F.C.", " FC", " A.F.C.", " C.F.", " S.C.", " Club de Fútbol",
                 " Football Club")

# Left out on purpose. Aaron Hernandez is remembered for a murder conviction more than for
# football — not a face for a game played for pleasure.
LEFT_OUT = {"Q302091", "Q44473"}  # Aaron Hernandez; O. J. Simpson, for the same reason

GOOD = ["a photograph of an athlete", "a photograph of a sports player"]
BAD = ["a statue or sculpture", "a drawing, a diagram or a page of text",
       "a trading card or a poster", "a group of people", "a stadium or a crowd"]


# What a vague position could mean, for ruling a wrong option out (never for asking).
BROAD = {
    "American football": {
        "defensive back": ["cornerback", "safety"],
        "offensive lineman": ["offensive tackle", "guard", "center"],
        "defensive lineman": ["defensive end", "defensive tackle"],
        "lineman": ["offensive tackle", "guard", "center", "defensive end", "defensive tackle"],
        "end": ["wide receiver", "tight end", "defensive end"],
        "back": ["quarterback", "running back", "fullback", "cornerback", "safety"],
        "wingback": ["running back", "wide receiver"],
        "return specialist": [], "kick returner": [], "punt returner": [],
    },
    "baseball": {
        "infielder": ["first base", "second base", "third base", "shortstop"],
        "utility player": ["first base", "second base", "third base", "shortstop",
                           "the outfield", "catcher"],
        "two-way player": ["pitcher", "the outfield", "first base", "designated hitter"],
        "manager": [],
    },
    "basketball": {
        "guard": ["point guard", "shooting guard"], "forward": ["small forward", "power forward"],
        "swingman": ["shooting guard", "small forward"],
        "point forward": ["small forward", "power forward", "point guard"],
        "combo guard": ["point guard", "shooting guard"],
        "stretch four": ["power forward"],
        "forward-center": ["small forward", "power forward", "center"],
        "forward–center": ["small forward", "power forward", "center"],
        "guard-forward": ["point guard", "shooting guard", "small forward", "power forward"],
    },
    "ice hockey": {
        "winger": ["left wing", "right wing"], "wing": ["left wing", "right wing"],
        "forward": ["center", "left wing", "right wing"], "rover": [],
    },
}


# MARK: - Cache

def cache_path(name):
    os.makedirs(q.CACHE, exist_ok=True)
    return os.path.join(q.CACHE, f"sports-stars-{name}.json")


def cached(name, make):
    path = cache_path(name)
    if os.path.exists(path):
        return json.load(open(path))
    value = make()
    if value is None:
        sys.exit(f"could not fetch {name} — try again later (nothing written)")
    with open(path, "w") as handle:
        json.dump(value, handle, ensure_ascii=False)
    return value


def retry(call, what, tries=4):
    wait = 30
    for attempt in range(tries):
        out = call()
        if out is not None:
            return out
        print(f"  {what} refused; waiting {wait}s", flush=True)
        time.sleep(wait)
        wait *= 2
    return None


# MARK: - Candidates

def candidates():
    out = {}
    for sport, (occs, sports, floor, _) in SPORTS.items():
        query = """SELECT ?x ?n WHERE {
          { ?x wdt:P106 ?o . VALUES ?o { %s } } UNION { ?x wdt:P641 ?s . VALUES ?s { %s } }
          ?x wdt:P31 wd:Q5 ; wdt:P18 ?img ; wdt:P569 ?b ; wikibase:sitelinks ?n .
          FILTER(?n >= %d) }""" % (" ".join("wd:" + o for o in occs),
                                   " ".join("wd:" + s for s in sports), floor)
        rows = retry(lambda: q.sparql(query), f"candidates for {sport}")
        if rows is None:
            return None
        out[sport] = {q.qid(r["x"]): int(r["n"]) for r in rows}
        print(f"  {sport}: {len(out[sport])} candidates", flush=True)
        time.sleep(2)
    return out


def trim(entity):
    keep = ("P18", "P569", "P54", "P413", "P166", "P463", "P641", "P106", "P31", "P17",
            "P1365", "P1366", "P127", "P749")
    return {"labels": entity.get("labels") or {},
            "aliases": [a["value"] for a in (entity.get("aliases") or {}).get("en", [])],
            "claims": {p: v for p, v in (entity.get("claims") or {}).items() if p in keep},
            "sitelinks": {k: 1 for k in (entity.get("sitelinks") or {})}}


def mul_labels(ids):
    """Wikidata now keeps many people's names only as the language-neutral "mul" label,
    with no "en" one — Roger Federer among them — and `entities` asks for English only."""
    out = {}
    for start in range(0, len(ids), 50):
        data = q.fetch_json("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(ids[start:start + 50]),
            "props": "labels", "languages": "en|mul", "format": "json"}))
        for k, v in ((data or {}).get("entities") or {}).items():
            labels = v.get("labels") or {}
            found = labels.get("en") or labels.get("mul")
            if found:
                out[k] = found["value"]
        time.sleep(0.4)
    return out


def with_names(name, ents):
    """Fill in missing English labels from "mul", and save the cache if any changed."""
    nameless = [k for k, v in ents.items() if not q.label(v)]
    if nameless:
        found = mul_labels(nameless)
        for k, value in found.items():
            ents[k]["labels"] = {"en": {"language": "en", "value": value}}
        json.dump(ents, open(cache_path(name), "w"), ensure_ascii=False)
        print(f"  {len(found)} of {len(nameless)} named from the 'mul' label")
    return ents


def fetch_entities(ids, props="claims|labels|sitelinks"):
    got = q.entities(ids, props)
    missing = [i for i in ids if i not in got]
    if missing:
        time.sleep(20)
        got.update(q.entities(missing, props))
    return {k: trim(v) for k, v in got.items() if "missing" not in v}


# MARK: - Award and Hall rolls

def category_qids(category):
    out, cont = set(), {}
    while True:
        params = {"action": "query", "generator": "categorymembers",
                  "gcmtitle": "Category:" + category, "gcmnamespace": 0, "gcmlimit": 500,
                  "prop": "pageprops", "ppprop": "wikibase_item", "format": "json", **cont}
        data = retry(lambda: q.fetch_json("https://en.wikipedia.org/w/api.php?"
                                          + urllib.parse.urlencode(params)), category)
        if data is None:
            return None
        for page in (data.get("query", {}).get("pages") or {}).values():
            item = (page.get("pageprops") or {}).get("wikibase_item")
            if item:
                out.add(item)
        if "continue" not in data:
            break
        cont = data["continue"]
        time.sleep(0.5)
    time.sleep(0.5)
    return sorted(out)


def wikidata_holders(items, props=("P166", "P463")):
    values = " ".join("wd:" + i for i in items)
    paths = "|".join("wdt:" + p for p in props)
    rows = retry(lambda: q.sparql(
        "SELECT DISTINCT ?x WHERE { ?x %s ?a . VALUES ?a { %s } }" % (paths, values)),
        "award holders")
    time.sleep(1.5)
    return None if rows is None else sorted(q.qid(r["x"]) for r in rows)


def rolls():
    out = {}
    for sport, (name, item, category) in HALLS.items():
        a, b = wikidata_holders([item]), category_qids(category)
        if a is None or b is None:
            return None
        out[name] = sorted(set(a) | set(b))
        print(f"  {name}: {len(a)} in Wikidata, {len(b)} in Wikipedia, "
              f"{len(out[name])} together", flush=True)
    for value, (sport, items, categories) in HONOURS.items():
        holders = wikidata_holders(items, ("P166",))
        if holders is None:
            return None
        found = set(holders)
        for category in categories:
            more = category_qids(category)
            if more is None:
                return None
            found |= set(more)
        out[value] = sorted(found)
        print(f"  {value}: {len(found)}", flush=True)
    return out


# MARK: - Helpers

def slug(text):
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch)).lower()
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")


def birth(entity):
    for value in q.claim_values(entity, "P569"):
        if isinstance(value, dict) and "time" in value:
            try:
                year = int(value["time"][1:5])
            except ValueError:
                continue
            month = int(value["time"][6:8]) if value.get("precision", 0) >= 10 else 0
            return year, month if 1 <= month <= 12 else 6
    return None, None


def primary_sport(entity, seen_in):
    occs = q.claim_ids(entity, "P106")
    sports = q.claim_ids(entity, "P641")
    for occ in occs:
        for sport, (o, _, _, _) in SPORTS.items():
            if occ in o and sport in seen_in:
                return sport
    for s in sports:
        for sport, (_, ss, _, _) in SPORTS.items():
            if s in ss and sport in seen_in:
                return sport
    return seen_in[0]


def file_ok(file_title):
    title = file_title.lower().removeprefix("file:").rsplit(".", 1)[0]
    parts = set("".join(ch if ch.isalnum() else " " for ch in title).split())
    for unwanted in NOT_THE_SUBJECT:
        if (" " in unwanted and unwanted in title) or unwanted in parts:
            return False
    return True


def team_name(label):
    for suffix in TEAM_SUFFIXES:
        if label.endswith(suffix):
            label = label[: -len(suffix)]
    return label.strip()


def said_team(entity):
    """A club as English says it after "Who played for": "the New York Yankees", "the
    Montreal Canadiens", but "Real Madrid", "Inter Miami CF", "HC CSKA Moscow"."""
    label = q.label(entity) or ""
    name = team_name(label)
    american = set(q.claim_ids(entity, "P17")) & NORTH_AMERICA
    clubby = re.search(r"\b(?:FC|SC|CF|F\.C\.|S\.C\.|C\.F\.|Club|Football Club)\b", label)
    if american and not clubby and not name.lower().startswith("the "):
        return "the " + name
    return name


def national_or_youth(entity, labels_of):
    name = (q.label(entity) or "").lower()
    kinds = " ".join((labels_of.get(k) or "").lower() for k in q.claim_ids(entity, "P31"))
    text = name + " | " + kinds
    return bool(re.search(r"national|olympic|under-?\s?\d|\bu-?\d{2}\b|youth|junior|academy",
                          text))


def nickname(entity):
    """The last word of a North American club's name: "Braves", "Dodgers"."""
    if not set(q.claim_ids(entity, "P17")) & NORTH_AMERICA:
        return None
    words = team_name(q.label(entity) or "").split()
    return words[-1].lower() if len(words) > 1 else None


def is_pro_team(entity, labels_of):
    name = (q.label(entity) or "").lower()
    if not name or q.sitelink_count(entity) < 20:
        return False
    # The name is held to every word; the kinds only to the ones that mean "not a
    # professional club". Wikidata calls FC Barcelona and Manchester United a "men's
    # association football team", and holding kinds to " men's" lost both.
    kinds = " ".join((labels_of.get(k) or "").lower() for k in q.claim_ids(entity, "P31"))
    return (not any(word in " " + name for word in TEAM_NOT_PRO)
            and not any(word in kinds for word in KIND_NOT_PRO)
            and not TEAM_SECOND_SIDE.search(name))


def is_team(entity, labels_of):
    """A club rather than its owner: Fenway Sports Group and Hal Steinbrenner are linked
    from the Red Sox and the Yankees as owners, and are not names a round could ask."""
    kinds = " ".join((labels_of.get(k) or "").lower() for k in q.claim_ids(entity, "P31"))
    # Kinds only: owners such as Silvio Berlusconi carry a sport (P641) of their own.
    return "Q5" not in q.claim_ids(entity, "P31") and any(
        word in kinds for word in ("team", "club", "franchise"))


SPORT_WORDS = {
    "American football": r"football|quarterback|linebacker|running back|wide receiver"
                         r"|gridiron|\bNFL\b",
    "baseball": r"baseball|pitcher|\bMLB\b",
    "basketball": r"basketball|\bNBA\b",
    "ice hockey": r"hockey|goaltender|\bNHL\b",
    "soccer": r"footballer|soccer|(?<!American )(?<!Canadian )football",
    "tennis": r"tennis",
    "golf": r"golf",
    "boxing": r"boxer|boxing|pugilist|prizefighter",
}

# Somebody whose article names one of these *before* the sport is mainly that, and played
# on the side: "an American professional wrestler and former football player" (Bill
# Goldberg), "an American actor and former football player". "Businessman" is not here:
# Michael Jordan's article puts it first.
OTHER_CALLINGS = r"wrestl|actor|actress|sprinter|track and field|athlete|politician|singer|" \
                 r"rapper|broadcaster|commentator|television|model|bodybuilder|" \
                 r"mixed martial|basketball|baseball|hockey|tennis|golf|boxer|football"


def plays(sport, fact):
    """Whether the article's opening calls this person, first of all, a player of this
    sport."""
    fact = " ".join(fact.split())
    found = re.search(r"\b(?:is|was) (?:an?|the) (.{0,200}?)(?:[.;(]| who | whose "
                      r"| known | best | widely )", fact)
    if not found:
        return False
    role = found.group(1)
    mine = re.search(SPORT_WORDS[sport], role, re.I)
    if not mine:
        return False
    before = role[: mine.start()]
    return re.search(OTHER_CALLINGS, before, re.I) is None


def table_elsewhere(sport):
    return {name for other, table in POSITIONS.items() if other != sport for name in table}


# MARK: - Build

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    reject = {k: 0 for k in ("no P18 file / licence / size", "file title not the subject",
                             "download failed", "faces != 1 or too small",
                             "SigLIP prefers bad", "near-duplicate", "no fact",
                             "duplicate person", "article says not mainly this sport",
                             "left out by hand")}

    print("candidates…")
    cands = cached("candidates", candidates)
    seen = {}
    for sport, people in cands.items():
        for person in people:
            seen.setdefault(person, []).append(sport)
    # Take the best-known few hundred per sport; everyone else is too obscure to ask about.
    pool = set()
    for sport, people in cands.items():
        quota = SPORTS[sport][3]
        pool |= set(sorted(people, key=lambda p: -people[p])[: quota * 5])
    print(f"  {len(pool)} people in the pool")

    print("entities…")
    ents = with_names("entities", cached("entities", lambda: fetch_entities(sorted(pool))))

    print("Hall of Fame and award rolls…")
    roll = {k: set(v) for k, v in cached("rolls", rolls).items()}

    # Teams and positions: labels, sitelinks, kinds, and each franchise's other names.
    team_ids = sorted({t for e in ents.values() for t in q.claim_ids(e, "P54")})
    print(f"teams ({len(team_ids)})…")
    teams = with_names("teams", cached("teams", lambda: fetch_entities(
        team_ids, "claims|labels|sitelinks|aliases")))
    links = ("P1365", "P1366", "P127", "P749")
    for depth in range(4):
        more = sorted({x for e in teams.values() for p in links for x in q.claim_ids(e, p)}
                      - set(teams))
        if not more:
            break
        print(f"  following {len(more)} franchise links…")
        teams.update(fetch_entities(more, "claims|labels|sitelinks|aliases"))
        json.dump(teams, open(cache_path("teams"), "w"), ensure_ascii=False)
        teams = with_names("teams", teams)
    kind_ids = sorted({k for e in teams.values() for k in q.claim_ids(e, "P31")})
    pos_ids = sorted({p for e in ents.values() for p in q.claim_ids(e, "P413")})
    lab = cached("labels", lambda: {})
    if missing := [i for i in kind_ids + pos_ids if i not in lab]:
        lab.update(mul_labels(missing))
        lab.update({i: None for i in missing if i not in lab})
        json.dump(lab, open(cache_path("labels"), "w"), ensure_ascii=False)
    pro_teams = {t: said_team(e) for t, e in teams.items() if is_pro_team(e, lab)}

    # Every name a franchise goes by.
    def linked(t, seen_ids=None):
        seen_ids = seen_ids or {t}
        for p in links:
            for x in q.claim_ids(teams.get(t) or {}, p):
                if x in teams and x not in seen_ids:
                    seen_ids.add(x)
                    linked(x, seen_ids)
        return seen_ids
    # Keyed by sport: "Boston Braves" is also an old name of the Washington Commanders.
    by_alias, by_nickname = {}, {}
    for t, name in pro_teams.items():
        e = teams[t]
        for sport, (_, sports, _, _) in SPORTS.items():
            if not set(q.claim_ids(e, "P641")) & set(sports):
                continue
            for alias in [q.label(e) or ""] + e.get("aliases", []):
                by_alias.setdefault((sport, alias.lower()), set()).add(name)
            if nick := nickname(e):
                by_nickname.setdefault((sport, nick), set()).add(name)

    def any_names(t, sport):
        e = teams[t]
        out = {said_team(teams[x]) for x in linked(t)
               if q.label(teams[x]) and is_team(teams[x], lab)}
        for alias in [q.label(e) or ""] + e.get("aliases", []):
            out |= by_alias.get((sport, alias.lower()), set())
        nick = nickname(e)
        if nick and sport != "soccer":
            out |= by_nickname.get((sport, nick), set())
        return out

    # People → records.
    unmapped = {}
    people = []
    for person, entity in ents.items():
        title = q.label(entity)
        if not title or person not in seen:
            continue
        sport = primary_sport(entity, seen[person])
        year, month = birth(entity)
        if not year:
            continue
        facts = {}
        if sport in TEAM_SPORTS:
            mine = [t for t in q.claim_ids(entity, "P54") if t in teams]
            names = list(dict.fromkeys(pro_teams[t] for t in mine if t in pro_teams))
            if names:
                facts["teams"] = names
            anyway = set(names)
            for t in mine:
                if not national_or_youth(teams[t], lab):
                    anyway |= any_names(t, sport)
            if anyway:
                facts["teamsAny"] = sorted(anyway)
        if sport in POSITIONS:
            table, broad = POSITIONS[sport], BROAD.get(sport, {})
            known, every, complete = [], [], True
            for statement in (entity.get("claims") or {}).get("P413", []):
                rank = statement.get("rank")
                value = ((statement.get("mainsnak") or {}).get("datavalue") or {}).get("value")
                if rank == "deprecated" or not isinstance(value, dict):
                    continue
                name = (lab.get(value["id"]) or "").lower()
                if table.get(name):
                    every += table[name]
                elif name in broad:
                    every += broad[name]
                elif name in table_elsewhere(sport):
                    continue  # a second sport's position: Jordan's "outfielder"
                else:
                    unmapped[(sport, name)] = unmapped.get((sport, name), 0) + 1
                    complete = False
                known.append((rank, name))
            preferred = [n for r, n in known if r == "preferred"]
            primary = preferred if preferred else [n for _, n in known]
            if len(primary) == 1 and table.get(primary[0]):
                facts["position"] = list(dict.fromkeys(table[primary[0]]))
            if every and complete:
                facts["positionAny"] = sorted(set(every))
        if sport in HONOUR_SPORTS:
            facts["honours"] = [v for v, (s, _, _) in HONOURS.items()
                                if s == sport and person in roll[v]]
        if sport in HALLS:
            hall = HALLS[sport][0]
            facts["hallOfFame"] = [hall] if person in roll[hall] else []
        files = q.claim_values(entity, "P18")
        bonus = (15 if facts.get("hallOfFame") else 0) + (10 if facts.get("honours") else 0)
        people.append({"qid": person, "title": title, "sport": sport, "year": year,
                       "month": month, "facts": facts, "file": files[0] if files else None,
                       "knownBy": q.sitelink_count(entity),
                       "rank": q.sitelink_count(entity) + bonus})
    if unmapped:
        print("positions not in the table (treated as vague):",
              sorted(unmapped.items(), key=lambda kv: -kv[1])[:30])

    # Facts first: the article's opening is also how a politician who once played college
    # football (Gerald Ford) or a physicist who kept goal (Niels Bohr) is told apart from
    # an athlete.
    print("facts…")
    reading = []
    for sport, (_, _, _, quota) in SPORTS.items():
        mine = sorted((p for p in people if p["sport"] == sport), key=lambda p: -p["rank"])
        reading += mine[: quota * 5]
    intros = cached("intros", lambda: {})
    missing = [p["qid"] for p in reading if p["qid"] not in intros]
    if missing:
        fetched = retry(lambda: q.wikipedia_intros(missing) or None, "Wikipedia intros")
        intros.update({k: list(v) for k, v in (fetched or {}).items()})
        # Remember the ones with no article too, so a rerun does not ask again.
        for k in missing:
            intros.setdefault(k, None)
        json.dump(intros, open(cache_path("intros"), "w"), ensure_ascii=False)

    shortlist = []
    for sport, (_, _, _, quota) in SPORTS.items():
        mine = [p for p in reading if p["sport"] == sport]
        athletes = []
        for p in mine:
            if not intros.get(p["qid"]):
                reject["no fact"] += 1
                continue
            if not plays(sport, intros[p["qid"]][0]):
                reject["article says not mainly this sport"] += 1
                continue
            athletes.append(p)
        shortlist += athletes[: quota * 3]
    print(f"{len(shortlist)} on the shortlist")

    print("Commons files…")
    names = sorted({p["file"] for p in shortlist if p["file"]})
    info = cached("commons", lambda: {})
    asked = set(cached("commons-asked", lambda: []))
    missing = [n for n in names if n not in asked]
    if missing:
        info.update(q.commons_files(missing))
        asked |= set(missing)
        json.dump(info, open(cache_path("commons"), "w"), ensure_ascii=False)
        json.dump(sorted(asked), open(cache_path("commons-asked"), "w"), ensure_ascii=False)
    keep = []
    for p in shortlist:
        meta = info.get(p["file"] or "") or info.get((p["file"] or "").replace("_", " "))
        if not q.usable_photo(meta):
            reject["no P18 file / licence / size"] += 1
            continue
        if not file_ok(meta["file"]):
            reject["file title not the subject"] += 1
            continue
        p["meta"] = meta
        keep.append(p)

    print(f"downloading {len(keep)}…")
    for p in keep:
        p["path"] = q.download(p["meta"]["url"])
    reject["download failed"] += sum(1 for p in keep if not p["path"])
    keep = [p for p in keep if p["path"]]

    print("faces…")
    faces = q.face_counts([p["path"] for p in keep])
    ok = []
    for p in keep:
        f = faces.get(p["path"])
        if not f or int(f["faces"]) != 1 or f["largest"] < 0.01:
            reject["faces != 1 or too small"] += 1
            continue
        ok.append(p)
    keep = ok

    print("SigLIP…")
    siglip = q.Siglip()
    vectors = siglip.images([p["path"] for p in keep])
    ok = []
    for p in keep:
        v = vectors.get(p["path"])
        if v is None or not siglip.prefers(v, GOOD, BAD)[0]:
            reject["SigLIP prefers bad"] += 1
            continue
        ok.append(p)
    keep = ok

    # Best known first, so a near-duplicate pair keeps the better-known picture. Checked
    # only against what is actually going in, so a picture is never lost to one that is
    # itself left out by its sport's quota.
    keep.sort(key=lambda p: -p["rank"])
    chosen, have, count, shipped = [], set(), {s: 0 for s in SPORTS}, []
    for p in keep:
        if p["qid"] in LEFT_OUT:
            reject["left out by hand"] += 1
            continue
        if p["qid"] in have:
            reject["duplicate person"] += 1
            continue
        if count[p["sport"]] >= SPORTS[p["sport"]][3]:
            continue
        twin = max(((float(vectors[o["path"]] @ vectors[p["path"]]), o["title"])
                    for o in shipped), default=(0.0, None))
        if twin[0] >= 0.98:
            reject["near-duplicate"] += 1
            print(f"  near-duplicate: {p['title']} ~ {twin[1]} ({twin[0]:.3f})")
            continue
        shipped.append(p)
        have.add(p["qid"])
        count[p["sport"]] += 1
        fact, source = intros[p["qid"]]
        meta = p["meta"]
        item = {
            "id": f"{PACK_ID}-{slug(p['title'])}",
            "subjectID": p["qid"],
            "title": p["title"],
            "objectTags": [],
            "remoteURL": meta["url"],
            "year": p["year"],
            "month": p["month"],
            "credit": meta["credit"] or "Wikimedia Commons contributor",
            "source": "Wikimedia Commons",
            "sourceURL": meta["sourceURL"],
            "license": meta["license"],
            "licenseURL": meta["licenseURL"],
            "isResizedCopy": True,
            "knownBy": p["knownBy"],
            "creator": None,
            "creatorDied": None,
            "latitude": None,
            "longitude": None,
            "fact": fact,
            "factSource": source,
            "cluster": p["sport"],
            "facts": p["facts"],
        }
        # A hint that does not name the sport misleads more than it helps: Michael Jordan's
        # article opens "an American businessman, former professional basketball player…".
        hint = hint_for(item)
        item["group"] = hint if hint and re.search(SPORT_WORDS[p["sport"]], hint, re.I) else None
        chosen.append(item)

    # Same order every run: by sport, then best known.
    order = list(SPORTS)
    chosen.sort(key=lambda i: (order.index(i["cluster"]), -i["knownBy"], i["title"]))
    ids = [i["id"] for i in chosen]
    assert len(ids) == len(set(ids)), "duplicate ids"

    print("\nper sport:", {s: c for s, c in count.items()})
    print("total:", len(chosen))
    print("rejections:", reject)
    keys = ("teams", "position", "honours", "hallOfFame")
    rule_out = {"teams": "teamsAny", "position": "positionAny"}
    print("with each key:", {k: sum(1 for i in chosen if k in i["facts"])
                             for k in keys + ("teamsAny", "positionAny")})
    print("with group:", sum(1 for i in chosen if i["group"]))
    print("\nplayable values (≥1 holder and ≥3 same-sport others known without it):")
    for sport in SPORTS:
        mine = [i for i in chosen if i["cluster"] == sport]
        line = []
        for k in keys:
            x = rule_out.get(k, k)
            values = {v for i in mine for v in i["facts"].get(k, [])}
            playable = [v for v in values if sum(
                1 for i in mine if x in i["facts"] and v not in i["facts"][x]) >= 3]
            line.append(f"{k} {len(playable)}/{len(values)}")
        print(f"  {sport:<18}", ", ".join(line))

    meta = {
        "title": "Sports Stars",
        "blurb": "Legends of the field, the court and the ring.",
        "themes": ["sports"],
        "namedSubjectPrompt": "Which person is {name}?|Which athlete is {name}?",
        "questions": [
            {"id": "team", "ask": "teams", "exclude": "teamsAny",
             "prompt": "Who played for {value}?|Which player played for {value}?", "sameCluster": True},
            {"id": "position", "ask": "position", "exclude": "positionAny",
             "prompt": "Who played {value}?|Which player played {value}?", "sameCluster": True},
            {"id": "honour", "ask": "honours", "exclude": "honours",
             "prompt": "Who was named {value}?|Which athlete was named {value}?", "sameCluster": True},
            {"id": "hall", "ask": "hallOfFame", "exclude": "hallOfFame",
             "prompt": "Which person is in the {value}?|Which athlete is in the {value}?", "sameCluster": True},
        ],
    }
    json.dump(chosen, open(cache_path("result"), "w"), ensure_ascii=False, indent=1)
    if args.dry_run:
        print("dry run — nothing written")
        return
    q.write_pack(PACK_ID, meta, chosen, force=args.force)


if __name__ == "__main__":
    main()
