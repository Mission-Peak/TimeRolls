#!/usr/bin/env python3
"""Check whether the *painting* is out of copyright, not whether the photograph is.

Commons licence tags describe the file, and for artworks that is the wrong thing. A
photograph of Guernica can be released CC BY-SA by the photographer while the painting
itself remains firmly in copyright — Picasso died in 1973. Trusting the file's tag put
Guernica, Campbell's Soup Cans and Nighthawks into a pack labelled public domain, three
works whose copyright status is anything but.

So the test here is about the artist. A work is taken as free when its creator died at
least seventy years ago, which is the term almost everywhere and the rule the PD-Art
position rests on. Where no creator is recorded, the work has to be old enough that no
living author is plausible.

  python3 Tools/PackBuilder/vet_artwork_rights.py
"""

import datetime, json, os, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")

TERM = 70
THIS_YEAR = datetime.date.today().year
# Seventy years after death. An artist who died in this year or earlier is safe.
SAFE_DEATH = THIS_YEAR - TERM
# With no creator recorded, the work has to be old enough that nobody who made it could
# still be inside the term — a painting from 1850 cannot have an author who died recently.
SAFE_ANONYMOUS = SAFE_DEATH - 80


def ask(query, tries=4):
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode(
        {"query": query, "format": "json"})
    wait = 5.0
    for attempt in range(tries):
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": AGENT,
                              "Accept": "application/sparql-results+json"})
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.load(response)["results"]["bindings"]
        except Exception as error:
            if attempt == tries - 1:
                print(f"  ! {type(error).__name__} {error}")
                return None
            time.sleep(wait)
            wait *= 1.8
    return None


def creators(ids):
    """Each work's creator and the year that creator died, where both are recorded."""
    out = {}
    for start in range(0, len(ids), 150):
        values = " ".join("wd:" + q for q in ids[start:start + 150])
        rows = ask(f"""
            SELECT ?item ?creator ?creatorLabel ?died WHERE {{
              VALUES ?item {{ {values} }}
              OPTIONAL {{ ?item wdt:P170 ?creator .
                          OPTIONAL {{ ?creator wdt:P570 ?died . }}
                          OPTIONAL {{ ?creator rdfs:label ?creatorLabel .
                                      FILTER(LANG(?creatorLabel) = "en") }} }}
            }}
        """)
        if rows is None:
            continue
        for row in rows:
            qid = row["item"]["value"].rsplit("/", 1)[-1]
            entry = out.setdefault(qid, {"creator": None, "died": None})
            if label := row.get("creatorLabel", {}).get("value"):
                entry["creator"] = label
            if died := row.get("died", {}).get("value"):
                year = died[:4].lstrip("-")
                if year.isdigit():
                    entry["died"] = int(year)
            # A work with a creator recorded but no death date is a living or
            # recently-dead artist often enough that it cannot be assumed either way.
            if row.get("creator") and entry["creator"] is None:
                entry["creator"] = "unnamed"
        print(f"  checked {min(start + 150, len(ids))} of {len(ids)}", flush=True)
        time.sleep(1.0)
    return out


def main():
    path = os.path.join(ROOT, "build", "subjects", "artworks.json")
    works = json.load(open(path))
    facts = creators([w["id"] for w in works])

    free, held, unknown = [], [], []
    for work in works:
        fact = facts.get(work["id"], {})
        died, creator = fact.get("died"), fact.get("creator")
        work["creator"], work["creatorDied"] = creator, died
        if died is not None:
            (free if died <= SAFE_DEATH else held).append(work)
        elif creator is None and (work.get("year") or 9999) <= SAFE_ANONYMOUS:
            free.append(work)
        else:
            unknown.append(work)

    print(f"\n{len(free)} free — the artist died in {SAFE_DEATH} or earlier")
    print(f"{len(held)} still in copyright — the artist died after {SAFE_DEATH}")
    for work in sorted(held, key=lambda w: -w.get("sitelinks", 0))[:8]:
        print(f"     {work['name'][:40]:<42} {work.get('creator')} d.{work.get('creatorDied')}")
    print(f"{len(unknown)} cannot be shown either way — no death date recorded")

    with open(path, "w") as handle:
        json.dump(free, handle, indent=1, ensure_ascii=False)
    print(f"\nkept only the free ones -> {path}")


if __name__ == "__main__":
    main()
