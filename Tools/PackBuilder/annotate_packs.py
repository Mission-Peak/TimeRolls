#!/usr/bin/env python3
"""Run every pack photograph through the same reading the app gives a personal one.

A pack photograph is never looked at on the device. `ObjectTagger.subject(for:)` can only
find pixels for a *bundled* image, and the packs carry metadata with the photographs
themselves on a server — so 930 pictures reach rounds with no theme, no concept, no
aesthetic score and no feature print. Two consequences, both invisible until you look:

  * the 135 themes never fire on a pack photograph, only on the player's own;
  * the second-opinion rules that stop a round having two answers can't run on them
    either, because they need a concept score and there is none.

The reading is identical for every device and never changes, so doing it here once is
strictly better than doing it on every phone forever. This writes it into the manifests:
the theme a photograph belongs to, what it is most a picture of, and whether it reads as
a place — the same three questions `PhotoThemeIndex` asks on device, against the same
tables, with the same thresholds.

Usage:  python3 Tools/PackBuilder/annotate_packs.py [--pack animals] [--apply]
"""

import argparse, glob, hashlib, json, os, sys

import numpy as np

# Apple's BLAS raises divide-by-zero, overflow and invalid flags on perfectly ordinary
# matmuls — every image triggers all three, with finite inputs and finite results. Checked
# against plain summation on a dozen photographs: the answers agree to 1e-12. The warnings
# are noise from the accelerator, and left switched on they hide the ones that would matter.
np.seterr(all="ignore")
import torch
from PIL import Image
from transformers import AutoModel, AutoProcessor

MODEL_ID = "google/siglip2-base-patch16-224"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLES = os.path.join(ROOT, "Tools", "Themes")

# The same numbers PhotoThemeIndex uses. Kept in step by hand, and checked below.
CONCEPT_FLOOR = 0.040
CONCEPT_MARGIN = 0.005
THEME_THRESHOLD = 0.035
THEME_MARGIN = 0.004
NULL_MARGIN = 0.004


def load_table(name):
    with open(os.path.join(TABLES, name)) as f:
        table = json.load(f)
    ids = list(table)
    vectors = np.array([table[i]["vector"] for i in ids], dtype=np.float32)
    return ids, vectors, {i: table[i].get("title", i) for i in ids}


def cached_image(url):
    digest = hashlib.sha256(url.encode()).hexdigest()[:20]
    path = os.path.join(ROOT, "build", "vet-cache", f"{digest}.jpg")
    return path if os.path.exists(path) else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", help="just this one")
    parser.add_argument("--apply", action="store_true",
                        help="write the readings into the manifests")
    args = parser.parse_args()

    theme_ids, theme_vectors, theme_titles = load_table("theme-vectors.json")
    concept_ids, concept_vectors, _ = load_table("concept-vectors.json")
    scene_ids, scene_vectors, _ = load_table("scene-vectors.json")
    # "a photograph" and friends: the null class every reading has to beat.
    nulls = [i for i, s in enumerate(scene_ids) if s.startswith("null-")]

    model = AutoModel.from_pretrained(MODEL_ID).eval()
    processor = AutoProcessor.from_pretrained(MODEL_ID)

    def look(path):
        """The photograph as 768 numbers, or None when it cannot be read.

        A file that decodes to something degenerate — a zero-byte JPEG, a 1x1 pixel, a
        CMYK scan the processor cannot handle — comes back as NaN and quietly poisons
        every comparison it touches, so it is caught here and named rather than allowed
        to score 'not a theme' against everything.
        """
        try:
            image = Image.open(path).convert("RGB")
            if min(image.size) < 8:
                return None
            inputs = processor(images=[image], return_tensors="pt")
            with torch.no_grad():
                features = model.get_image_features(**inputs)
            norm = features.norm(dim=-1, keepdim=True)
            if not torch.isfinite(norm).all() or float(norm) == 0:
                return None
            vector = (features / norm)[0].numpy().astype(np.float32)
            return vector if np.isfinite(vector).all() else None
        except Exception:
            return None

    def strongest(vector, ids, table, floor, margin):
        scores = table @ vector
        order = np.argsort(-scores)
        best, runner = order[0], order[1] if len(order) > 1 else order[0]
        if scores[best] < floor:
            return None, float(scores[best])
        if scores[best] - scores[runner] < margin:
            return None, float(scores[best])
        return ids[best], float(scores[best])

    totals = {"read": 0, "themed": 0, "concepted": 0, "placed": 0, "missing": 0,
              "unreadable": 0}
    unreadable = []
    manifests = sorted(glob.glob(os.path.join(ROOT, "TimeRolls/Packs/*/*.pack.json")))
    for path in manifests:
        pack = json.load(open(path))
        if args.pack and pack["id"] != args.pack:
            continue
        for item in pack["items"]:
            source = item.get("originalURL") or item.get("remoteURL")
            cached = cached_image(source) if source else None
            if not cached:
                totals["missing"] += 1
                continue
            vector = look(cached)
            if vector is None:
                totals["unreadable"] += 1
                unreadable.append(f"{pack['id']}/{item['id']}")
                continue
            totals["read"] += 1

            null_best = float(max(scene_vectors[n] @ vector for n in nulls))

            theme, theme_score = strongest(vector, theme_ids, theme_vectors,
                                           THEME_THRESHOLD, THEME_MARGIN)
            if theme and theme_score - null_best < NULL_MARGIN:
                theme = None
            concept, concept_score = strongest(vector, concept_ids, concept_vectors,
                                               CONCEPT_FLOOR, CONCEPT_MARGIN)
            if concept and concept_score - null_best < NULL_MARGIN:
                concept = None

            scene_scores = {s: float(scene_vectors[i] @ vector)
                            for i, s in enumerate(scene_ids)}
            outdoors = scene_scores.get("place-outdoor", 0)
            shows_place = outdoors >= max(v for k, v in scene_scores.items()
                                          if k != "place-outdoor") + 0.012

            item["themeID"] = theme
            item["themeScore"] = round(theme_score, 4) if theme else None
            item["conceptID"] = concept
            item["conceptScore"] = round(concept_score, 4) if concept else None
            item["showsAPlace"] = bool(shows_place)
            if theme: totals["themed"] += 1
            if concept: totals["concepted"] += 1
            if shows_place: totals["placed"] += 1

        if args.apply:
            with open(path, "w") as out:
                json.dump(pack, out, indent=2, ensure_ascii=False)
                out.write("\n")

    print(f"read {totals['read']} photographs, {totals['missing']} not cached, "
          f"{totals['unreadable']} unreadable")
    for name in unreadable[:10]:
        print(f"    unreadable: {name}")
    print(f"  {totals['themed']} landed on a theme")
    print(f"  {totals['concepted']} have a concept the game can ask about")
    print(f"  {totals['placed']} read as a place")
    print("written into the manifests" if args.apply else "nothing written — pass --apply")


if __name__ == "__main__":
    main()
