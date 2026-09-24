#!/usr/bin/env python3
"""Enumerate pack subjects from Wikidata, ranked by how well known they are.

Hand-written subject lists got the packs to about four hundred each and then stopped, for
the obvious reason: somebody has to think of every name. A thousand landmarks is not a
list anybody writes by hand, and a list written by hand has a second problem — it is only
as good as what one person happens to remember, which skews to wherever they grew up.

Wikidata answers this directly. It knows what things are, when people were born, and which
Commons file is the representative image, and the number of Wikipedia language editions an
item appears in is a decent, unglamorous proxy for "would somebody recognise this". Sorting
by that and taking the top thousand gets a better list than hand-writing one, and gets the
dates right, which matters because Famous Faces asks who was born first.

  python3 Tools/PackBuilder/from_wikidata.py --subjects people --limit 1200
  python3 Tools/PackBuilder/from_wikidata.py --subjects landmarks --limit 1200 --write
"""

import argparse, json, os, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")
ENDPOINT = "https://query.wikidata.org/sparql"

# Ranking by sitelinks inside the query is what made it time out: sorting every painting
# on Wikidata by how many Wikipedias cover it is an expensive sort over a large set, and
# the gateway gives up at sixty seconds. So the work is split. The query does the cheap
# part — what is this, where is its picture, when was it made — with no ordering at all,
# paged through with LIMIT and OFFSET. Notability is then read in a second pass from the
# ordinary Wikidata API, fifty items at a time, which is a plain lookup rather than a sort.
QUERIES = {
    "people": """
        SELECT ?item ?name ?image ?born WHERE {
          ?item wdt:P31 wd:Q5 ; wdt:P569 ?born ; wdt:P18 ?image ; rdfs:label ?name .
          FILTER(LANG(?name) = "en")
          FILTER(YEAR(?born) > 1300 && YEAR(?born) < 2005)
        } LIMIT %(limit)d OFFSET %(offset)d
    """,
    # Country and coordinates are not optional extras here. Landmarks is a Places pack,
    # and a Places round names the country and keeps its photographs 120km apart — so a
    # landmark with neither cannot be used at all. The first run of this query fetched
    # neither, and 612 of the 1000 landmarks it produced were unusable.
    #
    # The kinds are also queried one at a time rather than as one VALUES list. Asking for
    # all of them at once returned churches almost exclusively — Wikidata has far more
    # church buildings than castles — and a Places round of four cathedrals is not a round.
    "landmarks": """
        SELECT ?item ?name ?image ?country ?coord WHERE {
          ?item wdt:P31 %(kind)s ; wdt:P18 ?image ; wdt:P17 ?country ;
                wdt:P625 ?coord ; rdfs:label ?name .
          FILTER(LANG(?name) = "en")
        } LIMIT %(limit)d OFFSET %(offset)d
    """,
    "animals": """
        SELECT ?item ?name ?image WHERE {
          ?item wdt:P31 wd:Q16521 ; wdt:P105 wd:Q7432 ; wdt:P18 ?image ; rdfs:label ?name .
          FILTER(LANG(?name) = "en")
        } LIMIT %(limit)d OFFSET %(offset)d
    """,
    "artworks": """
        SELECT ?item ?name ?image ?inception WHERE {
          ?item wdt:P31 wd:Q3305213 ; wdt:P18 ?image ; wdt:P571 ?inception ;
                rdfs:label ?name .
          FILTER(LANG(?name) = "en")
        } LIMIT %(limit)d OFFSET %(offset)d
    """,
}


def notability(ids):
    """How many Wikipedia language editions cover each item.

    An unglamorous proxy for "would somebody recognise this", and the best one available
    without asking people. Read here rather than in the query, because sorting on it
    inside SPARQL is what made the query time out.
    """
    out = {}
    for start in range(0, len(ids), 50):
        batch = ids[start:start + 50]
        url = "https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(batch),
            "props": "sitelinks", "format": "json"})
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = json.load(response)
        except Exception:
            continue
        for qid, entity in (data.get("entities") or {}).items():
            out[qid] = len(entity.get("sitelinks") or {})
        time.sleep(0.4)
    return out


def ask(query):
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": query, "format": "json"})
    wait = 5.0
    for attempt in range(5):
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": AGENT, "Accept": "application/sparql-results+json"})
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.load(response)["results"]["bindings"]
        except Exception as error:
            if attempt == 4:
                print(f"  ! {type(error).__name__} {error}")
                return None
            time.sleep(wait)
            wait *= 2
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--subjects", required=True, choices=sorted(QUERIES))
    parser.add_argument("--pages", type=int, default=12,
                        help="pages of 500 to pull before ranking")
    parser.add_argument("--keep", type=int, default=1200,
                        help="how many of the best-known to keep")
    parser.add_argument("--floor", type=int, default=10,
                        help="fewest Wikipedia language editions to accept")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    # One kind at a time for landmarks, so no single kind can crowd out the rest.
    kinds = ["wd:Q570116", "wd:Q23413", "wd:Q4989906", "wd:Q12518", "wd:Q839954",
             "wd:Q33506", "wd:Q16970", "wd:Q811979", "wd:Q2065736", "wd:Q1107656",
             "wd:Q12280", "wd:Q22698"] if args.subjects == "landmarks" else [None]

    rows, seen = [], set()
    for kind in kinds:
      for page in range(args.pages if kind is None else max(args.pages // len(kinds), 2)):
        query = QUERIES[args.subjects] % {"limit": 500, "offset": page * 500,
                                          "kind": kind or ""}
        batch = ask(query)
        if batch is None:
            print(f"  page {page + 1}: Commons refused — stopping here, "
                  f"which is not the same as there being nothing left")
            break
        if not batch:
            break
        for row in batch:
            qid = row["item"]["value"].rsplit("/", 1)[-1]
            name = row.get("name", {}).get("value", "")
            if not name or qid in seen:
                continue
            seen.add(qid)
            entry = {"id": qid, "name": name,
                     "image": row.get("image", {}).get("value", "")}
            if country := row.get("country", {}).get("value"):
                entry["countryID"] = country.rsplit("/", 1)[-1]
            if coord := row.get("coord", {}).get("value"):
                # "Point(long lat)" — Wikidata puts longitude first.
                inside = coord.strip().removeprefix("Point(").rstrip(")").split()
                if len(inside) == 2:
                    try:
                        entry["longitude"] = float(inside[0])
                        entry["latitude"] = float(inside[1])
                    except ValueError:
                        pass
            for key in ("born", "inception"):
                if value := row.get(key, {}).get("value"):
                    entry["year"] = int(value[:4]) if value[:4].lstrip("-")[:4].isdigit() else None
            rows.append(entry)
        print(f"  {kind or args.subjects} page {page + 1}: {len(rows)} gathered", flush=True)
        time.sleep(1.0)

    if not rows:
        print("nothing gathered")
        return

    print(f"ranking {len(rows)} by how many Wikipedias cover them...", flush=True)
    ranks = notability([r["id"] for r in rows])
    for row in rows:
        row["sitelinks"] = ranks.get(row["id"], 0)
    rows = [r for r in rows if r["sitelinks"] >= args.floor]
    rows.sort(key=lambda r: -r["sitelinks"])
    rows = rows[:args.keep]

    print(f"\n{len(rows)} {args.subjects} above {args.floor} language editions")
    for row in rows[:6]:
        print(f"   {row['sitelinks']:>4}  {row['name'][:52]}")
    if len(rows) > 6:
        print("   ...")
        for row in rows[-3:]:
            print(f"   {row['sitelinks']:>4}  {row['name'][:52]}")

    if args.write:
        os.makedirs(os.path.join(ROOT, "build", "subjects"), exist_ok=True)
        path = os.path.join(ROOT, "build", "subjects", f"{args.subjects}.json")
        with open(path, "w") as handle:
            json.dump(rows, handle, indent=1, ensure_ascii=False)
        print(f"\n  -> {path}")


if __name__ == "__main__":
    main()
