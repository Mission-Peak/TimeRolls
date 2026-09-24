#!/usr/bin/env python3
"""Stage the photo packs for OneBucket, and rewrite the manifests to point at them.

Spec §5 and §10: the packs live on Wasabi and reach the app through OneBucket. Until now
they have been hotlinked from Wikimedia Commons, which is fragile — a file renamed on
Commons is a blank card in somebody's round — and it means the photograph somebody vetted
is not necessarily the photograph that ships.

This copies the vetted images into the bucket layout and writes manifests that point at
them. It changes nothing in the app: the rewritten manifests land in build/onebucket and
only move into TimeRolls/Packs when --apply is passed, because switching the app over
before the bucket can be read would replace every pack photograph with a blank card.

The licence travels with the copy. Hosting our own copy of a CC BY photograph is allowed
precisely because the credit and the licence go with it, so every item gains a licenceURL
and a note that the copy was resized.
"""

import argparse, glob, hashlib, json, os, re, shutil, time, urllib.request

STAGING = "build/onebucket"

# Derived rather than listed.
#
# This was a table of eleven licences written when the packs used four. They now use
# twenty-seven, including ported ones like "CC BY-SA 3.0 de" that Creative Commons
# publishes at country-specific addresses, so thirty-two photographs were staged into the
# bucket with no link to their terms. A CC BY photograph may be used on condition it is
# attributed, and the attribution the licence asks for includes a pointer to the licence —
# so a missing URL is the app falling short of the one condition attached to the picture.
#
# The same rule lives in fix_licence_urls.py, which repairs the manifests in the app.
FIXED_LICENCES = {
    "cc0": "https://creativecommons.org/publicdomain/zero/1.0/",
    "public domain": "https://creativecommons.org/publicdomain/mark/1.0/",
    "no restrictions": "https://creativecommons.org/publicdomain/mark/1.0/",
    "attribution": "https://creativecommons.org/licenses/by/4.0/",
}


def licence_url(name):
    """The address of the terms this photograph is under, worked out from its name."""
    text = (name or "").strip().lower()
    if not text:
        return None
    if text in FIXED_LICENCES:
        return FIXED_LICENCES[text]
    found = re.match(r"cc (by(?:-sa)?) (\d\.\d)(?: ([a-z]{2}))?$", text)
    if not found:
        return None
    kind, version, country = found.groups()
    tail = f"{version}/{country}/" if country else f"{version}/"
    return f"https://creativecommons.org/licenses/{kind}/{tail}"


def cached_path(url):
    return "build/vet-cache/%s.jpg" % hashlib.sha256(url.encode()).hexdigest()[:20]


AGENT = ("TimeRolls-PackBuilder/1.1 (photo game for older adults; hanna@mission-peak.com) "
         "python-urllib/3")


def fetch(url, into):
    """Download a pack photograph we do not already hold a copy of.

    This used to stage only what a previous vetting run happened to leave in the cache,
    and simply count the rest as "not cached" — which read like a note and was actually a
    hole: a pack built today had none of its photographs in that cache, so none of them
    were staged, so none reached the bucket. The point of the bucket is to hold our own
    copy of every photograph we ship, and that cannot depend on which tool ran last.
    """
    os.makedirs(os.path.dirname(into), exist_ok=True)
    try:
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read()
        if len(data) < 2000:
            return False
        with open(into, "wb") as handle:
            handle.write(data)
        return True
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true",
                        help="move the rewritten manifests into the app (only once the "
                             "bucket can actually be read)")
    args = parser.parse_args()

    os.makedirs(f"{STAGING}/packs", exist_ok=True)
    catalog, staged, missing, unlicensed, fetched = [], 0, 0, 0, 0

    for path in sorted(glob.glob("TimeRolls/Packs/*/*.pack.json")):
        pack = json.load(open(path))
        folder = f"{STAGING}/packs/{pack['id']}"
        os.makedirs(folder, exist_ok=True)

        for item in pack["items"]:
            url = item.get("remoteURL")
            if not url:
                continue
            source = cached_path(url)
            if not os.path.exists(source):
                if not fetch(url, source):
                    missing += 1
                    continue
                fetched += 1
                # Wikimedia serves these from a CDN and is far more tolerant than the API,
                # but this is still thousands of requests from one address.
                time.sleep(0.3)
            shutil.copy(source, f"{folder}/{item['id']}.jpg")
            staged += 1
            # Keep a pointer to the original. Losing it would leave a photograph whose
            # credit names somebody with no way to check what they are credited for.
            item.setdefault("originalURL", url)
            # The key, not a URL. The app asks OneBucket for this object; where OneBucket
            # answers is configured in the app rather than baked into every manifest, so
            # the address can change without rebuilding the packs.
            item["remoteKey"] = f"packs/{pack['id']}/{item['id']}.jpg"
            # The original stays as the fallback, so manifests can ship before the
            # endpoint is live without turning every pack photograph into a blank card.
            item["remoteURL"] = url
            item["isResizedCopy"] = True
            if url_for := licence_url(item.get("license")):
                item["licenseURL"] = url_for
            elif item.get("license"):
                unlicensed += 1

        years = [i["year"] for i in pack["items"] if i.get("year")]
        catalog.append({
            "id": pack["id"], "title": pack.get("title", pack["id"]),
            "blurb": pack.get("blurb", ""), "license": pack.get("license", ""),
            "photoCount": len(pack["items"]),
            "earliestYear": min(years) if years else None,
            "latestYear": max(years) if years else None,
            "manifest": f"packs/{pack['id']}/{pack['id']}.pack.json",
        })
        with open(f"{folder}/{pack['id']}.pack.json", "w") as out:
            json.dump(pack, out, indent=2, ensure_ascii=False)
            out.write("\n")
        if args.apply:
            shutil.copy(f"{folder}/{pack['id']}.pack.json", path)

    with open(f"{STAGING}/packs/catalog.json", "w") as out:
        json.dump({"formatVersion": 1, "packs": catalog}, out, indent=2, ensure_ascii=False)
        out.write("\n")

    print(f"{staged} photographs staged in {STAGING}/packs"
          + (f", {fetched} downloaded just now" if fetched else "")
          + (f", {missing} could not be fetched at all" if missing else ""))
    if unlicensed:
        print(f"{unlicensed} photographs have a licence this script has no URL for — add it")
    print("applied to the app" if args.apply
          else "manifests left in staging — pass --apply once the bucket can be read")


if __name__ == "__main__":
    main()
