# The themes model

The app bundles **SigLIP 2 base patch16-224** (`google/siglip2-base-patch16-224`),
Apache-2.0, image tower only, converted to Core ML and quantised to 8-bit weights:
176 MB → 88 MB.

Only the image side ships. `embed_themes.py` runs the text side once on a Mac to turn
`themes.json`, `concepts.json` and `scenes.json` into vectors; the app compares
photographs against those tables, so no tokenizer and no text model is in the bundle.

## Why this model

Measured against the model it replaced (OpenAI CLIP ViT-B/32) on 120 photographs from our
own packs, where we already know the answer:

| | animal class (40) | place or person (80) |
|---|---|---|
| CLIP ViT-B/32 | 37 (92%) | 71 (89%) |
| SigLIP base | 38 (95%) | 75 (94%) |
| **SigLIP 2 base** | 37 (92%) | **80 (100%)** |

The second column is the one that mattered: it is the gate that decides whether a
photograph can be asked "which photo is from North Carolina". CLIP read the Matterhorn,
Christ the Redeemer and the Hoover Dam as photographs of *people*, which is how portraits
and landscapes ended up in the same round.

After conversion and quantisation the shipped model scores 37/40 and 79/80 — the loss is
one landmark, and the bundle is the same size as before.

Apple's MobileCLIP is smaller and stronger again, and cannot be used: its weights are
research-only.

## Re-measuring after a model change

Similarity scales differ between models — a good match is about 0.08 here where CLIP's
was about 0.28 — so every threshold in `PhotoThemeIndex` is measured against a labelled
set rather than carried over. The benchmark and calibration scripts live in the session
scratch directory; the numbers they produced are written beside the thresholds they set.

## Changing what the app understands

Edit a sentence in `themes.json`, `concepts.json` or `scenes.json`, run:

    python3 Tools/Themes/embed_themes.py

and copy the three `*-vectors.json` files into `TimeRolls/Themes/`.
