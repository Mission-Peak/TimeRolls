#!/usr/bin/env python3
"""Give each famous face a hint saying what they are known for.

"Which one shows Louis Pasteur?" is a hard question asked cold and a fair one asked as
"he was a French chemist who invented pasteurisation" — a player who cannot put the name
to the face can still reason from the clothes, the era and the setting.

Taken from the opening of the encyclopedia article, which is written to answer exactly
this: almost every one begins "X was a French chemist and microbiologist who…". The name
is never repeated, because the question has already said it.

  python3 Tools/PackBuilder/face_hints.py
"""

import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACK = os.path.join(ROOT, "TimeRolls", "Packs", "famous-faces", "famous-faces.pack.json")

# "… was a French chemist and microbiologist who …" — the phrase that says what somebody
# was. Stops at a clause boundary so the hint stays one readable line.
WAS_A = re.compile(
    r"\bwas (?:an?|the) ([A-Za-z][A-Za-z \-]{3,70}?)\b"
    r"(?=[,.;(]|\s+(?:who|which|best|known|famous|and one|from|in|of)\b)",
    re.I)


def hint_for(item):
    fact = " ".join((item.get("fact") or "").split())
    if not fact:
        return None
    found = WAS_A.search(fact)
    if not found:
        return None
    what = found.group(1).strip().rstrip(" and")
    # A hint that names the person answers its own question.
    surname = (item.get("title") or "").split()[-1].lower()
    if surname and surname in what.lower():
        return None
    # Four words at most. Longer and it stops being a hint and becomes the answer read
    # aloud — and it was truncating mid-word, leaving "the late Baroque perio".
    words = what.split()
    if len(words) > 4:
        words = words[:4]
    what = " ".join(words).rstrip(" ,;-")
    if len(what) < 4:
        return None
    # Every word has to appear whole in the description. Without this a hint could end
    # on a fragment — "a German composer and musici" — which reads as a broken app rather
    # than a clue.
    whole = set(re.findall(r"[A-Za-z\-]+", fact.lower()))
    while words and words[-1].lower() not in whole:
        words.pop()
    # And never end on a joining word, which is what dropping a fragment leaves behind:
    # "a German composer and" is no better than "a German composer and musici".
    # Never end on a word that is waiting for another one. Capping at four words cut
    # "the second Japanese woman to win the prize" down to "a second Japanese woman to",
    # which asks a question instead of answering one. These are the words that leave a
    # sentence hanging: articles, conjunctions, prepositions and the infinitive marker.
    HANGING = {"and", "or", "the", "of", "in", "a", "an", "for", "to", "with", "at",
               "on", "by", "from", "who", "that", "as", "into", "over", "under",
               "after", "before", "between", "during", "than", "whose", "which"}
    while words and words[-1].lower() in HANGING:
        words.pop()
    what = " ".join(words).rstrip(" ,;-")
    if len(words) < 1 or len(what) < 4:
        return None
    if what.lower().startswith(("a ", "an ", "the ")):
        return what
    # "a Italian explorer" is what happens when the article is assumed rather than read.
    return ("an " if what[0].lower() in "aeiou" else "a ") + what


def main():
    pack = json.load(open(PACK))
    described = 0
    for item in pack["items"]:
        item.pop("group", None)
        hint = hint_for(item)
        if hint:
            item["group"] = hint
            described += 1
    with open(PACK, "w") as handle:
        json.dump(pack, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("%d of %d faces now carry a hint" % (described, len(pack["items"])))
    for item in pack["items"][:6]:
        if item.get("group"):
            print("   %-26s It's %s." % (item["title"][:26], item["group"]))


if __name__ == "__main__":
    main()
