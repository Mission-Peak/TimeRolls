"""Turns the written themes, concepts and scenes into vectors, once, on a Mac.

The app ships SigLIP 2's image tower and these tables. The text tower runs only here, so
neither it nor a tokenizer is in the bundle.

    python3 Tools/Themes/embed_themes.py

Writes theme-vectors.json, concept-vectors.json and scene-vectors.json next to this
script; copy them into TimeRolls/Themes/.
"""
import json
import os
import numpy as np
import torch
from transformers import AutoModel, AutoProcessor

MODEL_ID = "google/siglip2-base-patch16-224"
HERE = os.path.dirname(os.path.abspath(__file__))

model = AutoModel.from_pretrained(MODEL_ID).eval()
processor = AutoProcessor.from_pretrained(MODEL_ID)

def embed(prompts):
    """One vector per entry: the phrasings averaged, then normalised."""
    inputs = processor(text=prompts, padding="max_length", return_tensors="pt")
    with torch.no_grad():
        features = model.get_text_features(**inputs)
    features = features / features.norm(dim=-1, keepdim=True)
    stacked = features.mean(dim=0).numpy()
    return stacked / np.linalg.norm(stacked)

for source, destination, extra in [("themes.json", "theme-vectors.json", ["question"]),
                                   ("concepts.json", "concept-vectors.json", []),
                                   ("scenes.json", "scene-vectors.json", [])]:
    entries = json.load(open(os.path.join(HERE, source)))
    vectors = {}
    for entry in entries:
        prompts = entry.get("prompts") or [entry["prompt"]]
        vector = embed(prompts)
        record = {"title": entry["title"], "vector": [round(float(v), 5) for v in vector]}
        for key in extra:
            record[key] = entry[key]
        vectors[entry["id"]] = record
    json.dump(vectors, open(os.path.join(HERE, destination), "w"))
    print("embedded", len(vectors), "into", destination)
