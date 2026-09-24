#!/usr/bin/env python3
"""Sort an enumerated species list into animals and plants, and say what kind each is.

The species query asked Wikidata for taxa at species rank, which is every living thing, so
the "animals" list came back led by lion, maize, tiger, tomato, onion and potato.

Two attempts at fixing this with SPARQL both failed the same way. Asking for everything
under Animalia walks the whole tree of life and times out at the gateway. Pinning the
candidates with VALUES and walking up from each was meant to bound the work, and it still
returned 504s for hours without classifying a single one.

So this does not ask SPARQL at all. Every taxon records its parent, and the ordinary
Wikidata API hands back fifty items' claims in one call. Climbing one rung at a time, fifty
at a time, reaches the kingdom in about a dozen rounds — plain lookups that do not time out.

  python3 Tools/PackBuilder/split_species.py
"""

import json, os, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")

ANIMALS, PLANTS, FUNGI = "Q729", "Q756", "Q764"
# What kind of creature, for the hint a round shows. "Which photo has a pangolin in it?" is
# a hard question cold and a fair one as "it's a mammal".
GROUPS = {
    "Q5113": "a bird", "Q152": "a fish", "Q1390": "an insect", "Q1358": "a spider",
    "Q10811": "a reptile", "Q10908": "a frog or toad", "Q7377": "a mammal",
    "Q25326": "a shellfish", "Q2725857": "a starfish or urchin",
}
# Stop at the first recognisable animal group rather than climbing all the way to the
# kingdom. A lion's chain runs Panthera leo -> Panthera -> Felinae -> Felidae -> ... and
# then through a long run of unranked clades; forty rungs did not reach Animalia and the
# climb gave up on lion, tiger, grey wolf, red fox, cheetah and giraffe while settling
# goldfish. Nothing under Mammalia is in any doubt about being an animal, so there is no
# reason to keep climbing once we are there.
ANIMAL_GROUPS = {
    "Q7377",     # mammals
    "Q5113",     # birds
    "Q152",      # fish
    "Q10811",    # reptiles
    "Q10908",    # amphibians
    "Q1390",     # insects
    "Q1358",     # arachnids
    "Q25326",    # molluscs
    "Q1310",     # arthropods
    "Q25314",    # chordates
    "Q10876",    # bacteria is not one — kept out deliberately
} - {"Q10876"}
PLANT_GROUPS = {"Q27133", "Q25814", "Q756"}
STOP = {ANIMALS, PLANTS, FUNGI, "Q2382443", "Q19088"} | ANIMAL_GROUPS | PLANT_GROUPS


def parents(ids):
    """Each taxon's parent, and which ones were actually looked at.

    The two are different and conflating them is what broke the first two runs of this.
    A batch that times out returns nothing, which read as "these taxa have no parent" —
    so the chain was recorded as ending there, and the species was filed as neither animal
    nor plant. It lost lion, tiger, grey wolf, red fox, cheetah and giraffe while keeping
    goldfish, which is the signature of a lookup failure rather than of a real taxonomy.

    Same mistake as reading a rate limit as an empty search. A refusal to answer is not an
    answer, and the only safe thing to do with one is try again.
    """
    out, looked_at = {}, set()
    for start in range(0, len(ids), 50):
        batch = [q for q in ids[start:start + 50] if q]
        if not batch:
            continue
        url = "https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(batch),
            "props": "claims", "format": "json"})
        wait = 3.0
        for attempt in range(4):
            try:
                request = urllib.request.Request(url, headers={"User-Agent": AGENT})
                with urllib.request.urlopen(request, timeout=90) as response:
                    data = json.load(response)
                looked_at.update(batch)
                break
            except Exception:
                if attempt == 3:
                    data = {}      # and `batch` stays out of `looked_at`
                else:
                    time.sleep(wait)
                    wait *= 1.8
        for qid, entity in (data.get("entities") or {}).items():
            claims = (entity.get("claims") or {}).get("P171") or []
            for claim in claims:
                value = (((claim.get("mainsnak") or {}).get("datavalue") or {})
                         .get("value") or {})
                if parent := value.get("id"):
                    out[qid] = parent
                    break
        time.sleep(0.25)
    return out, looked_at


def main():
    path = os.path.join(ROOT, "build", "subjects", "animals.json")
    species = json.load(open(path))
    print(f"climbing the taxonomy for {len(species)} species")

    # Where each species has got to so far, and the groups seen on the way up.
    standing = {s["id"]: s["id"] for s in species}
    group_of = {}
    settled = {}

    # Sixteen rungs was not enough. Animal taxonomy is deeper than plant taxonomy —
    # species, genus, tribe, subfamily, family, superfamily, order, class, subphylum,
    # phylum and several unranked clades between them — so a first attempt settled 540
    # plants and only 40 animals, and left 820 chains still climbing.
    for rung in range(80):
        climbing = [q for s, q in standing.items() if s not in settled and q]
        if not climbing:
            break
        found, looked_at = parents(sorted(set(climbing)))
        moved = 0
        for species_id, here in list(standing.items()):
            if species_id in settled or not here:
                continue
            up = found.get(here)
            if up is None:
                # Only a dead end if we actually got an answer about it. Otherwise leave
                # it where it is and try again on the next rung.
                if here in looked_at:
                    settled[species_id] = None
                continue
            if up in GROUPS and species_id not in group_of:
                group_of[species_id] = GROUPS[up]
            if up in STOP:
                settled[species_id] = up
            standing[species_id] = up
            moved += 1
        print(f"  rung {rung + 1}: {len(settled)} settled, {moved} still climbing",
              flush=True)
        if not moved:
            break

    out = {"animals": [], "plants": [], "neither": []}
    for entry in species:
        kingdom = settled.get(entry["id"])
        if kingdom in ANIMAL_GROUPS:
            kingdom = ANIMALS
        elif kingdom in PLANT_GROUPS:
            kingdom = PLANTS
        if kingdom == ANIMALS:
            if group := group_of.get(entry["id"]):
                entry["group"] = group
            out["animals"].append(entry)
        elif kingdom == PLANTS:
            out["plants"].append(entry)
        else:
            out["neither"].append(entry)

    # Keep the unsettled ones too. The first run of this wrote only the animals it had
    # classified over the species list it was reading from, which threw away the other
    # 1,360 and meant the list had to be fetched again.
    where = os.path.join(ROOT, "build", "subjects", "species-unsettled.json")
    with open(where, "w") as handle:
        json.dump(out["neither"], handle, indent=1, ensure_ascii=False)

    for kind in ("animals", "plants"):
        where = os.path.join(ROOT, "build", "subjects", f"{kind}.json")
        with open(where, "w") as handle:
            json.dump(out[kind], handle, indent=1, ensure_ascii=False)
        named = ", ".join(e["name"] for e in out[kind][:6])
        print(f"\n{kind}: {len(out[kind])} — {named}")
    have_group = sum(1 for e in out["animals"] if e.get("group"))
    print(f"\n{have_group} animals know what kind they are, for the hint")
    print(f"{len(out['neither'])} neither — fungi, algae, or a chain that ran out")


if __name__ == "__main__":
    main()
