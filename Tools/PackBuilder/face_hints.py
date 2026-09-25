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
# was, taken whole.
#
# "is" as well as "was": Wikipedia writes the living in the present tense, and only
# accepting "was" made the miner skip a living person's opening sentence and pick up some
# later one. That is how Barack Obama's hint came from "was the first African American to
# serve as president" instead of "is an American retired politician".
WAS_A = re.compile(
    r"\b(?:was|is) (?:an?|the) ([A-Za-z][A-Za-z \-]{3,70}?)\b"
    r"(?=[,.;(]|\s+(?:who|whose|which|that|best|known|well-known|noted|"
    r"famous|remembered|celebrated|and one|"
    r"at|from|during|between|before|after|until|while)\b)",
    re.I)

# Words a phrase cannot end on, because each one is waiting for another. An article, a
# conjunction, a preposition or the infinitive marker all leave a sentence hanging:
# "a German composer and" says no more than "a German composer and musici" did.
HANGING = {"and", "or", "the", "of", "in", "a", "an", "for", "to", "with", "at",
           "on", "by", "from", "who", "that", "as", "into", "over", "under",
           "after", "before", "between", "during", "than", "whose", "which"}

# A phrase that begins by ranking somebody has to say what they were first *at*:
# "the second Japanese woman" is not a fact about anybody until the sentence finishes.
# These are kept only when the whole phrase survives, and dropped when it would be cut.
RANKING = {"first", "second", "third", "fourth", "fifth", "last", "only", "oldest",
           "youngest", "earliest", "leading", "foremost", "principal", "chief"}

# As long as a hint may run before it stops being a clue and becomes the answer read out.
# A limit in characters rather than words, and a phrase over it is dropped rather than
# cut: cutting to four words is what turned "an American track and field athlete" into
# "an American track and field", and "an American writer and civil rights activist" into
# "an American writer and civil".
LONGEST = 52

# A full stop does not always end a sentence. "an American former world No. 1 tennis
# player" stops the phrase dead at "No", and "an American former world No" is not a
# description of anybody. A phrase ending on one of these was cut at an abbreviation
# rather than at a boundary, so it is dropped.
ABBREVIATIONS = {"no", "dr", "st", "mt", "jr", "sr", "mr", "mrs", "ms", "vs", "co"}


def hint_for(item):
    fact = " ".join((item.get("fact") or "").split())
    if not fact:
        return None
    found = WAS_A.search(fact)
    if not found:
        return None
    # `.rstrip(" and")` was here, and it strips *characters* — every space, a, n and d
    # from the end of the string. "English mathematician" came back as "English
    # mathematici", the whole-word check below threw that away, and Alan Turing's hint
    # was "an English".
    what = re.sub(r"\s+(?:and|or)$", "", found.group(1).strip(), flags=re.I)

    # A hint that names the person answers its own question.
    surname = (item.get("title") or "").split()[-1].lower()
    if surname and surname in what.lower():
        return None

    words = what.split()
    # Every word has to appear whole in the description, so a hint can never end on a
    # fragment of one.
    whole = set(re.findall(r"[A-Za-z\-]+", fact.lower()))
    if any(word.lower().strip(",;-") not in whole for word in words):
        return None
    while words and words[-1].lower() in HANGING:
        words.pop()
    if words and words[-1].lower().strip(".") in ABBREVIATIONS:
        return None
    what = " ".join(words).rstrip(" ,;-")
    if len(words) < 2 or len(what) < 4:
        # One word on its own is almost always a nationality with its noun cut off —
        # "an English", "a French" — or a noun with nothing to hold it up: "a member".
        return None
    if len(what) > LONGEST:
        return None
    # A ranking that lost its ending says nothing. "a second Japanese woman" was a real
    # hint in a shipped build, and it is not a fact about Naoko Yamazaki or anybody else.
    if words[0].lower() in RANKING and not re.search(
            r"\b(?:to|who|of|in|at)\b", " ".join(words[1:]), re.I):
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
    # Printed the way the app says it. A person is "they", not "it" — the app picks by
    # whether the pack's dates are birthdays, and Famous Faces' are.
    for item in pack["items"][:6]:
        if item.get("group"):
            print("   %-26s They were %s." % (item["title"][:26], item["group"]))


if __name__ == "__main__":
    main()
