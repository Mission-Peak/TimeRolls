"""Vets a pack: keeps the photographs that survive, writes the rest to a rejects file.

The packs are assembled from Wikipedia lead images, which are chosen by an editor to
illustrate an article — not to be one of four cards in a game. That leaves two failures
this catches, both reported from real rounds:

  * A photograph that does not show what it claims. The label says turtle; the picture is
    a museum case, a diagram, a distant speck.
  * A photograph that is not distinctive. "Which one is from Shibuya" beside three
    anonymous city streets that could all be Shibuya is not a question.

Both are answerable by comparing the photograph against sentences, which is what the app
does at play time — so the same model does the vetting here, once, on a Mac, and only the
survivors ship.

    python3 Tools/PackBuilder/vet_pack.py --pack animals --apply
    python3 Tools/PackBuilder/vet_pack.py --pack landmarks           # dry run

Needs the converted SigLIP image tower and PyTorch for the text side.
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PACKS = os.path.join(ROOT, "TimeRolls", "Packs")
UA = "TimeRolls-vetting/1.0 (hanna@attimis.co)"
MODEL_ID = "google/siglip2-base-patch16-224"

CLASS_PROMPTS = {
    "class-mammal": "a photograph of a mammal, an animal with fur or hair",
    "class-bird": "a photograph of a bird with feathers and a beak",
    "class-reptile": "a photograph of a reptile with scales: a lizard, snake, turtle or crocodile",
    "class-amphibian": "a photograph of an amphibian: a frog, toad, newt or salamander",
    "class-fish": "a photograph of a fish with fins and gills",
    "class-insect": "a photograph of an insect with six legs",
}

# What a photograph has to beat to count as showing anything at all.
NOTHING = [
    "a photograph",
    "an ordinary photograph of something else",
    "a diagram, a drawing, a map or a page of text",
    "a museum display case or an exhibit label",
]

# What a place photograph has to beat to count as *that* place rather than anywhere.
ANYWHERE = [
    "a generic city street that could be anywhere",
    "an ordinary building with nothing distinctive about it",
    "a nondescript view of a town",
]


def model_and_processor():
    import torch
    from transformers import AutoModel, AutoProcessor
    model = AutoModel.from_pretrained(MODEL_ID).eval()
    processor = AutoProcessor.from_pretrained(MODEL_ID)

    def embed_text(prompts):
        inputs = processor(text=prompts, padding="max_length", return_tensors="pt")
        with torch.no_grad():
            features = model.get_text_features(**inputs)
        features = features / features.norm(dim=-1, keepdim=True)
        return features.numpy()

    return embed_text


def image_embedder(package):
    import coremltools as ct
    from PIL import Image
    coreml = ct.models.MLModel(package, compute_units=ct.ComputeUnit.CPU_ONLY)

    def embed(path):
        image = Image.open(path).convert("RGB").resize((224, 224), Image.BICUBIC)
        vector = np.array(coreml.predict({"image": image})["embedding"]).reshape(-1)
        return vector / np.linalg.norm(vector)

    return embed


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 2048:
        return True
    try:
        request = urllib.request.Request(url, headers={"User-Agent": UA})
        open(path, "wb").write(urllib.request.urlopen(request, timeout=90).read())
        return True
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack", choices=["animals", "landmarks"], required=True)
    parser.add_argument("--model", default=os.environ.get("SIGLIP_PACKAGE", ""))
    parser.add_argument("--cache", default=os.environ.get("VET_CACHE", ""))
    parser.add_argument("--alike", type=float, default=0.90,
                        help="how close two pack photographs may look before one goes")
    parser.add_argument("--rank", type=int, default=1,
                        help="how far down its own name may rank and still be kept")
    parser.add_argument("--apply", action="store_true",
                        help="rewrite the pack with only the survivors")
    arguments = parser.parse_args()

    pack_id = "animals" if arguments.pack == "animals" else "travel-landmarks"
    path = os.path.join(PACKS, pack_id, f"{pack_id}.pack.json")
    pack = json.load(open(path))
    os.makedirs(arguments.cache, exist_ok=True)

    embed_text = model_and_processor()
    embed_image = image_embedder(arguments.model)

    nothing = embed_text(NOTHING)
    anywhere = embed_text(ANYWHERE)

    keep, reject, unsure = [], [], []

    # Vetting by retrieval, not by threshold.
    #
    # Comparing "a photograph of Big Ben, London" against "a generic city street" asks
    # which sentence the model likes more, and it likes the short generic one — which is
    # how a perfect photograph of the Golden Gate Bridge came to be rejected as "could be
    # anywhere". The question that actually matters is different and scale-free: out of
    # every subject in this pack, does this photograph match its own?
    #
    # A photograph that matches some other entry better is exactly the one that breaks a
    # round — the anonymous Shibuya street that could equally be any of the others.
    names = []
    for item in pack["items"]:
        title = item["title"]
        bare = title
        for article in ("A ", "An ", "The "):
            if bare.startswith(article):
                bare = bare[len(article):]
        if arguments.pack == "animals":
            names.append(f"a photograph of a {bare}")
        else:
            where = item.get("place", "")
            names.append(f"a photograph of {bare}, {where}" if where
                         else f"a photograph of {bare}")
    catalogue = np.vstack([embed_text(names[i:i + 32]) for i in range(0, len(names), 32)])

    ranks = []
    vectors = {}
    for index, item in enumerate(pack["items"]):
        title = item["title"]
        key = hashlib.sha256(item["remoteURL"].encode()).hexdigest()[:20]
        file = os.path.join(arguments.cache, f"{key}.jpg")
        if not fetch(item["remoteURL"], file):
            reject.append((title, "could not be fetched"))
            continue
        try:
            vector = embed_image(file)
        except Exception as error:
            reject.append((title, f"unreadable ({type(error).__name__})"))
            continue

        if arguments.pack == "animals":
            # A species can be named from a photograph, and this model does it well:
            # 334 of 379 rank their own name first. So the test is retrieval — does the
            # picture match its own animal better than any of the other three hundred?
            scores = catalogue @ vector
            order = np.argsort(-scores)
            rank = int(np.where(order == index)[0][0]) + 1
            ranks.append((rank, title, pack["items"][int(order[0])]["title"]))
            if rank > arguments.rank:
                reject.append((title, f"looks more like "
                                      f"{pack['items'][int(order[0])]['title']}"
                                      f" (its own name ranks {rank} of {len(names)})"))
                continue
        else:
            # A landmark cannot be named this way, and it is worth being clear why
            # rather than pretending otherwise: measured on the ten most recognisable
            # buildings on earth, this model picks the right name 3 times in 10. Telling
            # the Eiffel Tower from the Colosseum is fine-grained instance recognition,
            # which is not what an embedding model of this size does. Identity here
            # comes from the Wikipedia editor who chose the article's lead image.
            #
            # What the model *can* judge is whether a photograph looks like every other
            # photograph — and that is the failure being chased: "which one is from
            # Shibuya" beside three anonymous streets that could all be Shibuya. So the
            # test is picture against picture, which needs no prompt and no threshold
            # pulled out of the air.
            vectors[index] = vector
            keep.append(item)
            continue

        if arguments.pack == "animals":
            tags = item.get("objectTags") or []
            declared = next((t for t in tags if t in CLASS_PROMPTS), None)
            if not declared:
                reject.append((title, "no class tag"))
                continue
            classes = list(CLASS_PROMPTS)
            class_scores = embed_text([CLASS_PROMPTS[c] for c in classes]) @ vector
            best = classes[int(np.argmax(class_scores))]
            if best != declared:
                unsure.append((title, f"looks more like {best.replace('class-', '')} "
                                      f"than {declared.replace('class-', '')}"))
        keep.append(item)

    if vectors and arguments.pack != "animals":
        # Every kept photograph against every other. A photograph whose nearest
        # neighbour is very close is a generic view: it would serve as a distractor for
        # the place it resembles, and be indistinguishable from it in a round.
        order = sorted(vectors)
        stack = np.vstack([vectors[i] for i in order])
        similarity = stack @ stack.T
        np.fill_diagonal(similarity, -1)
        nearest = similarity.max(axis=1)
        pairs = similarity.argmax(axis=1)
        print(f"   picture-to-picture closeness: median {np.median(nearest):.3f}, "
              f"90th {np.percentile(nearest, 90):.3f}, max {nearest.max():.3f}")
        crowded = []
        for position, index in enumerate(order):
            if nearest[position] >= arguments.alike:
                twin = pack["items"][order[int(pairs[position])]]["title"]
                crowded.append((pack["items"][index]["title"], twin,
                                float(nearest[position])))
        crowded.sort(key=lambda row: -row[2])
        if crowded:
            print(f"   {len(crowded)} look like another photograph in the pack "
                  f"(at or above {arguments.alike}):")
            for title, twin, score in crowded[:20]:
                print(f"      ~ {title} ≈ {twin} ({score:.3f})")
            # One of each pair, not both. Himeji and Nagoya Castle are a fair round
            # apart and an unfair one together; keeping the first of the two loses
            # nothing but the confusion.
            drop, seen = set(), set()
            for title, twin, score in crowded:
                if twin in drop or title in drop:
                    continue
                if twin in seen:
                    drop.add(title)
                seen.add(title)
            keep = [item for item in keep if item["title"] not in drop]
            reject += [(title, f"looks like {twin} ({score:.3f})")
                       for title, twin, score in crowded if title in drop]
            print(f"   dropping {len(drop)} of them, keeping the other of each pair")

    if ranks:
        values = np.array([r[0] for r in ranks])
        print(f"   own name ranked first for {(values == 1).sum()} of {len(values)}; "
              f"top three for {(values <= 3).sum()}; median rank {int(np.median(values))}")

    print(f"{pack_id}: {len(keep)} kept, {len(reject)} rejected, "
          f"of {len(pack['items'])}")
    if unsure:
        print(f"   {len(unsure)} kept but worth a look on the contact sheet:")
        for title, why in unsure[:15]:
            print(f"      ? {title}: {why}")
    for title, why in reject:
        print(f"   - {title}: {why}")

    if arguments.apply:
        pack["items"] = keep
        json.dump(pack, open(path, "w"), indent=2, ensure_ascii=False)
        open(path, "a").write("\n")
        print(f"   written: {path}")
    else:
        print("   dry run — pass --apply to rewrite the pack")


if __name__ == "__main__":
    main()
