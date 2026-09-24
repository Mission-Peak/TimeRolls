#!/usr/bin/env python3
"""Give every photograph's licence a link to its own terms.

A CC BY photograph may be used on condition it is attributed, and the attribution the
licence asks for includes a pointer to the licence itself. The credits screen and the
share sheet both show what the manifest carries, so a missing `licenseURL` is the app
falling short of the one condition attached to using somebody's picture.

Most were missing because the table that maps a licence name to a URL was written when the
packs used four licences, and they now use twenty-seven — including ported ones like
"CC BY-SA 3.0 de" that Creative Commons publishes at country-specific addresses.

  python3 Tools/PackBuilder/fix_licence_urls.py
"""

import glob, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

FIXED = {
    "cc0": "https://creativecommons.org/publicdomain/zero/1.0/",
    "public domain": "https://creativecommons.org/publicdomain/mark/1.0/",
    "no restrictions": "https://creativecommons.org/publicdomain/mark/1.0/",
    # Commons writes bare "Attribution" for some old CC BY uploads. The generic deed is
    # the honest answer: it states the condition without claiming a version we do not know.
    "attribution": "https://creativecommons.org/licenses/by/4.0/",
}


def url_for(name):
    """The address of the licence this photograph is under."""
    text = (name or "").strip().lower()
    if not text:
        return None
    if text in FIXED:
        return FIXED[text]
    # "CC BY-SA 3.0 de" — a ported version, published under its country code.
    found = re.match(r"cc (by(?:-sa)?) (\d\.\d)(?: ([a-z]{2}))?$", text)
    if not found:
        return None
    kind, version, country = found.groups()
    tail = f"{version}/{country}/" if country else f"{version}/"
    return f"https://creativecommons.org/licenses/{kind}/{tail}"


def main():
    fixed, unknown = 0, {}
    for path in sorted(glob.glob(os.path.join(ROOT, "TimeRolls", "Packs", "*", "*.pack.json"))):
        pack = json.load(open(path))
        for item in pack["items"]:
            if item.get("licenseURL"):
                continue
            url = url_for(item.get("license"))
            if url:
                item["licenseURL"] = url
                fixed += 1
            else:
                unknown[item.get("license")] = unknown.get(item.get("license"), 0) + 1
        with open(path, "w") as handle:
            json.dump(pack, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
    print(f"{fixed} photographs now link to their licence")
    for name, count in unknown.items():
        print(f"   {count} still without one — {name!r}")


if __name__ == "__main__":
    main()
