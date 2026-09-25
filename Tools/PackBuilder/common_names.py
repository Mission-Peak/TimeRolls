#!/usr/bin/env python3
"""English common names for the plant and animal packs.

Both packs are titled with whatever Wikidata calls the subject, and for a taxon that is
usually the scientific name: 500 of the 540 plants are binomials. "Which photo has
Aesculus hippocastanum in it?" is not a question anybody can answer, and the name is not
even a clue — it is the one part of the card a reader will skip.

Three sources, best first:

  P1843  taxon common name, English. Curated, and what a field guide would print.
  enwiki The Wikipedia article title, when it is not itself the binomial. English
         Wikipedia titles the horse chestnut article "Aesculus hippocastanum" but the
         oak one "Quercus robur" and the maize one "Maize" — worth asking.
  lead   The article's first sentence, which nearly always says "commonly known as the
         horse chestnut" or "also called conker tree" when a common name exists.

A subject with no common name from any of the three keeps its scientific name and is
marked so the app can leave it out of the questions rather than ask by a name nobody
knows.
"""
import json, re, sys, time, urllib.parse, urllib.request

AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib")


def get(url, tries=4):
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except Exception as error:
            # A rate limit is not an answer. Reading a refusal as "this subject has no
            # common name" is how a pack ends up full of binomials that do have names.
            if attempt == tries - 1:
                raise RuntimeError("giving up on %s: %s" % (url, error))
            time.sleep(2 * (attempt + 1))


def entities(qids):
    """P1843 common names and the English Wikipedia title, in batches of 50."""
    out = {}
    for start in range(0, len(qids), 50):
        batch = qids[start:start + 50]
        url = ("https://www.wikidata.org/w/api.php?action=wbgetentities&format=json"
               "&props=claims|sitelinks&sites=enwiki&ids=" + "|".join(batch))
        data = get(url)
        for qid, entity in (data.get("entities") or {}).items():
            claims = entity.get("claims") or {}
            names = []
            for claim in claims.get("P1843", []):
                value = (claim.get("mainsnak", {}).get("datavalue") or {}).get("value") or {}
                if value.get("language") == "en" and value.get("text"):
                    names.append(value["text"].strip())
            # P225 is the scientific name itself, stated by Wikidata rather than guessed
            # from the shape of the words. A regex cannot tell "Iberian lynx" from
            # "Papilio demodocus" — it reads both as a capitalised word and a lowercase
            # one — and reading a common name as Latin threw good names away.
            taxon = None
            for claim in claims.get("P225", []):
                value = (claim.get("mainsnak", {}).get("datavalue") or {}).get("value")
                if isinstance(value, str) and value.strip():
                    taxon = value.strip()
                    break
            title = ((entity.get("sitelinks") or {}).get("enwiki") or {}).get("title")
            out[qid] = {"p1843": names, "enwiki": title, "taxon": taxon}
        time.sleep(0.2)
    return out


# "Aesculus hippocastanum, the horse chestnut, is a species of flowering plant…"
# "Zea mays, also known as corn, is a tall stout grass…"
LEAD = re.compile(
    r"(?:commonly |also |otherwise |variously )?"
    r"(?:known as|called|named)\s+(?:the\s+)?([a-z][a-z' -]{2,40})", re.I)


def from_lead(fact):
    if not fact:
        return None
    # The first sentence only. Later ones talk about other species.
    first = re.split(r"(?<=[a-z]{2})\.\s", fact)[0]
    match = LEAD.search(first)
    if not match:
        return None
    name = match.group(1).strip().strip(",;")
    # A trailing conjunction means the sentence ran on into something else.
    name = re.sub(r"\s+(and|or|in|of|from|by|with|the|a|an)$", "", name).strip()
    return name or None


def looks_scientific(name):
    """A binomial: a capitalised genus and a lowercase epithet, and nothing else."""
    return bool(re.fullmatch(r"[A-Z][a-z]+(?:\s*[x×]\s*)?\s[a-z-]+(\s[a-z-]+)?", name or ""))



# Words that stay capitalised inside a species name because they are somewhere or
# somebody: "Jerusalem artichoke", "African sage", "Norway spruce". Everything else in a
# common name is a common noun, whatever case Wikidata happened to store it in.
PROPER = {
    "african", "american", "andean", "antarctic", "arabian", "arctic", "asian",
    "atlantic", "australian", "austrian", "balkan", "baltic", "bengal", "bohemian",
    "bolivian", "brazilian", "british", "burmese", "california", "californian",
    "canada", "canadian", "cape", "carolina", "caucasian", "chilean", "chinese",
    "colombian", "corsican", "cretan", "cuban", "cyprus", "danish", "dutch",
    "egyptian", "english", "ethiopian", "eurasian", "european", "florida", "french",
    "german", "greek", "greenland", "guinea", "himalayan", "hungarian", "iberian",
    "iceland", "icelandic", "india", "indian", "indochinese", "iranian", "irish",
    "italian", "jamaican", "japanese", "java", "javan", "jerusalem", "kashmir",
    "kenyan", "korean", "lebanon", "levant", "madagascar", "malabar", "malay",
    "maltese", "manchurian", "mediterranean", "mexican", "mongolian", "moroccan",
    "nepalese", "nile", "norfolk", "norway", "norwegian", "oregon", "oriental",
    "pacific", "patagonian", "persian", "peruvian", "philippine", "polish",
    "portuguese", "pyrenean", "roman", "russian", "sahara", "saharan", "scotch",
    "scots", "scottish", "serbian", "siberian", "sicilian", "spanish", "sumatran",
    "swedish", "swiss", "syrian", "tasmanian", "texas", "tibetan", "turkish",
    "ural", "virginia", "welsh", "yemen", "zealand", "zanzibar",
}


def tidy(name):
    """A common name the way a field guide prints it.

    Wikidata stores these however the contributor typed them — "Red Flowering Currant",
    "creeping bentgrass", "Poor Man's Pepper" — and a question reading "Which photo has
    Red Flowering Currant in it?" looks like a brand rather than a plant. Lowercase
    throughout, except for the places and people a name is built on.
    """
    words = name.split()
    out = []
    for index, word in enumerate(words):
        bare = word.strip("()'\"").lower()
        # "New" belongs to what follows it: New Zealand, New Guinea, New England.
        nextBare = words[index + 1].strip("()'\"").lower() if index + 1 < len(words) else ""
        if bare == "new" and (nextBare in PROPER or nextBare in {"england", "guinea"}):
            out.append("New")
            continue
        if bare in {"england", "guinea"} and index and words[index - 1].lower() == "new":
            out.append(word[0].upper() + word[1:])
            continue
        # A hyphenated compound keeps the rule on each half: "New-Zealand flax".
        if bare in PROPER or bare.split("-")[0] in PROPER:
            out.append(word[0].upper() + word[1:])
        else:
            out.append(word.lower())
    tidied = " ".join(out)
    return tidied[0].upper() + tidied[1:] if tidied[:1].isupper() else tidied


def main(paths):
    for path in paths:
        pack = json.load(open(path))
        items = pack["items"]
        qids = sorted({i["subjectID"] for i in items if i.get("subjectID")})
        print("%s — %d photographs, %d subjects" % (pack["id"], len(items), len(qids)))
        found = entities(qids)

        # One name per subject, so two photographs of the same plant agree.
        names, sources = {}, {}
        for qid in qids:
            entry = found.get(qid, {})
            title = next((i.get("title") for i in items if i.get("subjectID") == qid), None)
            fact = next((i.get("fact") for i in items if i.get("subjectID") == qid), None)

            taxon = entry.get("taxon")

            # Latin, as Wikidata records it — the taxon name itself, or, where it records
            # none, a two-word name shaped like one.
            def scientific(candidate):
                if not candidate:
                    return False
                if taxon:
                    return candidate.strip().lower() == taxon.strip().lower()
                return looks_scientific(candidate)

            name = next((n for n in entry.get("p1843", []) if not scientific(n)), None)
            source = "P1843"
            if not name:
                wiki = entry.get("enwiki")
                if wiki and not scientific(wiki) and "(" not in wiki:
                    name, source = wiki, "enwiki"
            if not name:
                mined = from_lead(fact)
                if mined and not scientific(mined):
                    name, source = mined, "lead"
            if not name and title and not scientific(title):
                name, source = title, "title"
            if name:
                names[qid] = tidy(name)
                sources[qid] = source

        latin = {qid: (found.get(qid) or {}).get("taxon") for qid in qids}
        for item in items:
            qid = item.get("subjectID")
            item["commonName"] = names.get(qid)
            # The Latin, for the back of the card. Only where it is not simply the name
            # the question already used.
            taxon = latin.get(qid)
            item["scientificName"] = (
                taxon if taxon and taxon.lower() != (names.get(qid) or "").lower() else None)

        tally = {}
        for qid in qids:
            tally[sources.get(qid, "none")] = tally.get(sources.get(qid, "none"), 0) + 1
        print("  named: %d of %d — %s" % (len(names), len(qids), tally))
        missing = [q for q in qids if q not in names]
        if missing:
            titles = [next(i["title"] for i in items if i.get("subjectID") == q)
                      for q in missing[:8]]
            print("  still scientific:", titles)
        json.dump(pack, open(path, "w"), indent=1, ensure_ascii=False)
        print("  written", path)


if __name__ == "__main__":
    main(sys.argv[1:])
