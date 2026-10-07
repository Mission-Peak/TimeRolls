#!/usr/bin/env python3
"""Give every pack subject a description somebody would want to read.

A round shows a photograph and a name. If the name means nothing to you — and for a
thousand landmarks it often will — the round teaches you nothing and the card you turn
over is blank. This fetches the opening of each subject's Wikipedia article, which is
written to be the answer to "what is this", and is the one piece of text about a landmark
that is reliably both accurate and short.

Taken from Wikipedia rather than written here, for the same reason the photographs are
taken from Commons rather than drawn: a fact about a real place has to come from somewhere
that can be checked, and a sentence invented to fill a field is worse than an empty field.

  python3 Tools/PackBuilder/add_descriptions.py --subjects landmarks
"""

import argparse, json, re, os, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")


def fetch(url, tries=4):
    wait = 3.0
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except Exception as error:
            if attempt == tries - 1:
                print(f"  ! {type(error).__name__} {error}")
                return None
            time.sleep(wait)
            wait *= 1.8
    return None


def english_titles(ids):
    """The English Wikipedia article for each Wikidata item, where there is one."""
    out = {}
    for start in range(0, len(ids), 50):
        batch = ids[start:start + 50]
        data = fetch("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(batch),
            "props": "sitelinks", "sitefilter": "enwiki", "format": "json"}))
        if data is None:
            continue
        for qid, entity in (data.get("entities") or {}).items():
            link = (entity.get("sitelinks") or {}).get("enwiki")
            if link:
                out[qid] = link["title"]
        time.sleep(0.3)
        print(f"  found {len(out)} articles for {min(start + 50, len(ids))} subjects",
              flush=True)
    return out


HATNOTE = re.compile(r"^(?:(?:See |For (?:other|the) |Not to be confused|This article is about"
                     r"|\"[^\"]+\" redirects here)[^.]*\.\s*)+")


# A pronunciation is for reading, not for being read aloud: "(LOO-thər; German: [ˈmaʁtiːn
# ˈlʊtɐ])" opened Martin Luther's card. Wikipedia's plain-text extracts often strip the IPA
# and leave the brackets behind — "The osprey (; Pandion haliaetus)" — so both go.
PRONUNCIATION = re.compile(
    r"\s*\((?=[^()]*(?:\[[^\]]*\]|/[^/]+/|[ˈˌəɐʁɪʊæɛɔŋθðʃʒ]|\b[A-Z][a-z]+:\s))[^()]*\)")
DEBRIS = re.compile(r"^\s*(?:[;,]|or\b|also\b|$)|\b(?:US|UK):\s*(?:[,;]|$)|[;,]\s*$")
SPOKEN_ONLY = re.compile(r"(?:or|also|and|US:?|UK:?)(?:\s+(?:or|US:?|UK:?))*")


def tidy_pronunciation(text):
    text = PRONUNCIATION.sub("", text)

    def keep_what_is_real(match):
        parts = [p.strip() for p in re.split(r"[;,]", match.group(1))]
        parts = [re.sub(r"^(?:or|also)\s+", "", p) for p in parts
                 if p and not SPOKEN_ONLY.fullmatch(p)]
        return f" ({'; '.join(parts)})" if parts else ""

    for _ in range(3):
        text = re.sub(r"\s*\(([^()]*)\)",
                      lambda m: keep_what_is_real(m) if DEBRIS.search(m.group(1)) else m.group(0),
                      text)
    text = re.sub(r"\s+([,.;:])", r"\1", text)
    return re.sub(r"\s{2,}", " ", text).strip()


# Full stops that do not end a sentence. Splitting on every ". " cut St Paul's Church off
# at "…replaced by St." and 120-odd other facts at an abbreviation or the initial of a
# species name — "the American alligator (A." — mid-thought, on a card read aloud.
ABBREVIATIONS = {
    "st", "mt", "mts", "ft", "pt", "dr", "mr", "mrs", "ms", "jr", "sr", "gen", "col", "lt",
    "sgt", "capt", "rev", "prof", "no", "nos", "co", "inc", "ltd", "corp", "vs", "ste",
    "hon", "gov", "sen", "rep", "pres", "bros", "approx", "ca", "c", "fl", "b", "d", "est",
    "ave", "blvd", "rd", "dept", "univ", "vol", "op", "syn", "var", "subsp", "sp", "spp",
    "cf", "al", "etc", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept",
    "oct", "nov", "dec",
}


def ends_sentence(before, after):
    """Whether the full stop between `before` and `after` ends a sentence."""
    word = re.search(r"([A-Za-z.]+)$", before)
    word = word.group(1) if word else ""
    bare = word.rstrip(".").lower()
    if bare in ABBREVIATIONS:
        return False
    # A lone initial — "B. taurus", "J. R. R. Tolkien", "U.S. Army" — or "e.g", "i.e".
    if re.fullmatch(r"[A-Za-z]", word) or "." in word:
        return False
    # The next thing has to look like a sentence starting.
    return bool(re.match(r"[A-Z0-9\"'“(]", after))


def split_sentences(text):
    out, start = [], 0
    for match in re.finditer(r"[.!?](?=\s+)", text):
        end = match.end()
        rest = text[end:].lstrip()
        if match.group() == "." and not ends_sentence(text[start:match.start()], rest):
            continue
        out.append(text[start:end].strip())
        start = end
    tail = text[start:].strip()
    if tail:
        out.append(tail)
    return out


def shorten(text, sentences=2, limit=340):
    """The first sentence or two, which is where an encyclopedia puts the answer."""
    text = " ".join((text or "").split())
    # A hatnote is a signpost to another article, not a sentence about this one. Three car
    # cards opened "See Mercedes-Benz S-Class for a complete overview of all S-Class
    # models." — read aloud, as the first thing said about a 1955 Mercedes.
    text = HATNOTE.sub("", text)
    text = tidy_pronunciation(text)
    if not text:
        return None
    # Whole sentences only. Cutting at a character count left the Mona Lisa's card ending
    # "The painting's novel…", which is worse than saying less: a card that stops mid-
    # thought reads as broken, and this one is meant to be read aloud.
    out = []
    for part in split_sentences(text):
        candidate = " ".join(out + [part]).strip()
        if out and (len(candidate) > limit or len(out) >= sentences):
            break
        out.append(part)
    joined = " ".join(out).strip()
    if not joined:
        return None
    if not joined.endswith("."):
        joined += "."
    # One long first sentence is still better cut than dropped, but this is the last
    # resort rather than the ordinary case.
    if len(joined) > limit + 80:
        joined = joined[:limit].rsplit(" ", 1)[0].rstrip(",;:") + "…"
    return joined


def intros(titles):
    """The opening of each article, twenty at a time."""
    out = {}
    names = list(titles)
    for start in range(0, len(names), 20):
        batch = names[start:start + 20]
        data = fetch("https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode({
            "action": "query", "prop": "extracts", "exintro": 1, "explaintext": 1,
            "titles": "|".join(batch), "format": "json", "redirects": 1}))
        if data is None:
            continue
        for page in (data.get("query", {}).get("pages") or {}).values():
            if summary := shorten(page.get("extract")):
                out[page.get("title", "")] = summary
        time.sleep(0.4)
        print(f"  described {len(out)} of {min(start + 20, len(names))}", flush=True)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--subjects", required=True)
    args = parser.parse_args()

    path = os.path.join(ROOT, "build", "subjects", f"{args.subjects}.json")
    subjects = json.load(open(path))
    want = [s for s in subjects if not s.get("fact")]
    print(f"{len(want)} of {len(subjects)} {args.subjects} still need a description")

    articles = english_titles([s["id"] for s in want])
    summaries = intros(sorted(set(articles.values())))

    described = 0
    for subject in subjects:
        title = articles.get(subject["id"])
        if title and (summary := summaries.get(title)):
            subject["fact"] = summary
            subject["factSource"] = f"https://en.wikipedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}"
            described += 1

    with open(path, "w") as handle:
        json.dump(subjects, handle, indent=1, ensure_ascii=False)
    have = sum(1 for s in subjects if s.get("fact"))
    print(f"\n{have} of {len(subjects)} now have a description ({described} added)")
    for subject in subjects[:3]:
        if subject.get("fact"):
            print(f"\n  {subject['name']}\n    {subject['fact']}")


if __name__ == "__main__":
    main()
