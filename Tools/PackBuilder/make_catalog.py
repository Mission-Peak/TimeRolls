#!/usr/bin/env python3
"""
make_catalog.py — writes the catalog the app fetches to discover downloadable packs.

The delivery layout is deliberately plain objects rather than an archive, so the bucket
stays browsable and a pack can be corrected one photo at a time:

    <bucket>/packs/catalog.json
    <bucket>/packs/<pack-id>/<pack-id>.pack.json
    <bucket>/packs/<pack-id>/<pack-id>-001.jpg
    …

A downloaded pack lands on the device in exactly the same shape as a bundled one, so
nothing downstream needs to know where a pack came from. This is the pack file format
left open in spec §12.

Usage:
    python3 make_catalog.py --packs ../../PacksForDownload --out ../../../build/remote
"""

import argparse, json, os, shutil, sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--packs", required=True, help="directory holding the built packs")
    parser.add_argument("--out", required=True, help="where to assemble the uploadable tree")
    parser.add_argument("--exclude", nargs="*", default=[],
                        help="pack ids that ship inside the app and need no download")
    args = parser.parse_args()

    packs_root = os.path.abspath(args.packs)
    out_root = os.path.abspath(args.out)
    packs_out = os.path.join(out_root, "packs")
    if os.path.exists(out_root):
        shutil.rmtree(out_root)
    os.makedirs(packs_out)

    entries = []
    for pack_id in sorted(os.listdir(packs_root)):
        source = os.path.join(packs_root, pack_id)
        manifest_path = os.path.join(source, f"{pack_id}.pack.json")
        if not os.path.isdir(source) or not os.path.exists(manifest_path):
            continue
        if pack_id in args.exclude:
            print(f"  skipping {pack_id} (ships in the app)")
            continue

        with open(manifest_path) as handle:
            manifest = json.load(handle)

        images = [name for name in os.listdir(source) if name.endswith(".jpg")]
        total_bytes = sum(os.path.getsize(os.path.join(source, name)) for name in images)
        shutil.copytree(source, os.path.join(packs_out, pack_id))

        years = [item["year"] for item in manifest["items"]]
        entries.append({
            "id": manifest["id"],
            "title": manifest["title"],
            "blurb": manifest["blurb"],
            "license": manifest.get("license", "CC0"),
            "photoCount": len(manifest["items"]),
            "bytes": total_bytes,
            "earliestYear": min(years) if years else None,
            "latestYear": max(years) if years else None,
            "manifest": f"packs/{pack_id}/{pack_id}.pack.json",
        })
        print(f"  {manifest['title']}: {len(manifest['items'])} photos, "
              f"{total_bytes / 1_000_000:.1f} MB")

    catalog = {"formatVersion": 1, "packs": entries}
    with open(os.path.join(packs_out, "catalog.json"), "w") as handle:
        json.dump(catalog, handle, indent=2)

    print(f"\nAssembled {len(entries)} downloadable packs in {out_root}")
    print("Upload the contents of that directory to the bucket root.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
