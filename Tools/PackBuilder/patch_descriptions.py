#!/usr/bin/env python3
"""Put descriptions onto a pack that was built before they were fetched.

Rebuilding the pack would work and would also re-download nine hundred photographs that
are already correct, for the sake of one text field. The subjects and the pack items share
a title, which is enough to join them.
"""

import argparse, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", required=True)
    parser.add_argument("--subjects", required=True)
    args = parser.parse_args()

    subjects = json.load(open(os.path.join(ROOT, "build", "subjects",
                                           f"{args.subjects}.json")))
    described = {s["name"].lower(): s for s in subjects if s.get("fact")}

    path = os.path.join(ROOT, "TimeRolls", "Packs", args.pack, f"{args.pack}.pack.json")
    pack = json.load(open(path))
    # A fact this tool wrote earlier is not a description. The first version of the
    # portraits pack filled the field with "Leonardo da Vinci was a artist, born in 1452."
    # — a restatement of the title and the date beside it, with a grammar mistake — and
    # because the field was not empty, the pass that fetched real descriptions skipped it.
    def is_generated(item):
        fact = item.get("fact") or ""
        return fact.startswith(item.get("title") or "\u0000") and " born in " in fact

    added = 0
    for item in pack["items"]:
        if item.get("fact") and not is_generated(item):
            continue
        match = described.get((item.get("title") or "").lower())
        if not match:
            continue
        item["fact"] = match["fact"]
        item["factSource"] = match.get("factSource")
        added += 1

    with open(path, "w") as handle:
        json.dump(pack, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    have = sum(1 for i in pack["items"] if i.get("fact"))
    print(f"{args.pack}: {have} of {len(pack['items'])} described ({added} added)")


if __name__ == "__main__":
    main()
