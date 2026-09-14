# Photo Chronology — v1 prototype

An iOS prototype of the Photo-Chronology concept, built to
`PhotoChronology_Prototype_Spec_v1` (Attimis, 10 Sep 2026). SwiftUI, iOS 26.5,
no third-party dependencies.

Open `Photo Chronology.xcodeproj` and run on a simulator or device.

## What plays today

Three themes are live. Chronology and Places need PhotoKit metadata only; Objects adds
on-device Vision classification:

- **Time** — "Which photo is older?" over 3–5 photos. Difficulty is the time-delta
  lever from spec §5.1: the library is bucketed into time windows and levels are
  sampled inside one of them. Gentle levels put ~11 years between the answer and
  the runner-up; the hardest close to ~10 months.
- **Places** — "Which photo was taken in [place]?" Coordinates are reverse-geocoded
  through MapKit, cached per ~11 km cluster on disk, and looked up once. Harder levels
  draw distractors from nearby towns, gentle ones from other continents.
- **Things** — "Which photo has a dog in it?" Photos are classified on the device by
  Apple's built-in Vision classifier against a curated 24-category allow-list (spec
  §6.3) — never open-ended object detection. A distractor is only used if the classifier
  saw no hint of the target category in it, so a level never has two defensible answers.
  Harder levels put the answer next to its own family: a cat and a horse against a dog.

Around that: errorless feedback (a wrong tap dims and you try again — no score, no
fail state, no visible clock), silent adaptive difficulty, a soft-gated caregiver
setup, on-device aggregate progress, and an anonymous engagement queue.

## Photo packs and the CC0 pipeline

`Tools/PackBuilder/build_pack.py` assembles a pack from CC0 sources and writes it in the
pack format the app loads — the same format a pack delivered over OneBucket would use,
which is the file-format question left open in spec §12.

```bash
python3 Tools/PackBuilder/build_pack.py --list
python3 Tools/PackBuilder/build_pack.py --pack landmarks --out "Photo Chronology/Packs"
```

**CC0 and nothing else.** The tool drops anything whose licence is not exactly CC0 and
prints the tally — a landmarks run rejects roughly 240 files to keep 21. That strictness
is the point: "public domain" depends on which country the viewer is in and the App Store
is global, while CC0 is a worldwide waiver with no attribution duty. Provenance is
recorded anyway and shown under Privacy → Photo credits.

**Sources.** `commons-geo` geosearches Wikimedia Commons around a landmark coordinate, so
those items carry real coordinates and can drive the Places theme. `smithsonian` pulls
from Open Access, which holds ~35k CC0 photographs with dates and is where historical
material comes from.

**The Smithsonian key.** The API needs one. `DEMO_KEY` is for exploration only — about 30
requests an hour, explicitly not for automated use — and a Decades build spends one request
per decade, so it runs out. A free key from <https://api.data.gov/signup/> raises the limit
to 1,000 requests an hour; pass it as `--si-key` or set `SI_API_KEY`. The key is used by
this build tool on a developer's Mac and never ships in the app: what ships is the
resulting CC0 images.

**Is the output shippable?** Yes. The Smithsonian states that CC0 assets may be used
commercially with no attribution, permission or fee. Two caveats that CC0 does not cover,
both worth a look before a public release: third-party rights the Smithsonian cannot waive
(trademark, privacy, publicity — relevant because these are photographs of identifiable
people, though the ones here are long-dead), and Smithsonian trademarks, which are excluded
from Open Access entirely and are not used here.

**What ships today**

| Pack | Items | Years | Source | Serves |
| --- | --- | --- | --- | --- |
| Travel Landmarks | 21 | 2005–2017 | Wikimedia Commons | Places (8 cities), Time |
| Decades | 12 | 1855–1953 | Smithsonian Open Access | Time |

The Decades pack is thin and skewed early because it was built on `DEMO_KEY`, which ran
out mid-build. The builder now issues one query per decade from the 1880s to the 1980s and
caps how many items any one decade may contribute, so a run with a real key should spread
much more evenly. A run that yields fewer photos than the pack already on disk refuses to
overwrite it.
| Everyday Life, Classic Holidays | 24 | 1948–2019 | Procedural placeholder art | all three |

**What the licence filter costs.** Strict CC0 buys legal clarity and loses the middle of
the twentieth century. CC0 material is bimodal: pre-1900 museum holdings and post-2010
photography, with 1940–1990 — precisely the era this audience remembers — thinly covered.
If mid-century nostalgia turns out to matter for the experience, that is an argument for
licensing a collection rather than for loosening the filter.

**A filter for photographs, not just images.** Geosearch returns whatever is pinned at a
coordinate (maps, diagrams, a webcam still, a video poster) and the Smithsonian returns
paintings, sketchbook folios and herbarium sheets. Both are filtered out — by MIME type
and title for Commons, by `object_type` for the Smithsonian.

Pack photographs are classified on device by the same Vision pass as personal photos, so
they work in the Things theme too. A pack that appears in a later build arrives switched
on rather than hidden.

## Together mode

The evidence spine's strongest cross-cutting finding is that solo delivery of
reminiscence-type activities underperforms caregiver co-use (spec §7). Together mode is
the cheapest way to act on that: a quiet strip on the play screen, for a companion
sitting in the same room. No pairing, no network, nothing stored — the companion can
offer a hint, and once the photos are open the app suggests something to ask about them.

Two rules govern what it says, both checked in the harness:

- **A hint narrows, it never points.** It works on a different axis from the question —
  a Places question gets a hint about what's in the picture or when it was taken — and it
  is only offered when it is true of exactly one photo in the set.
- **A pack photo is never prompted as a personal memory.** "What do you remember about
  it?" is reserved for the player's own photos; a stock photo only ever prompts about the
  player's life in general ("Have you ever been to Rome?").

It deliberately shows no score and keeps no per-item history. A live *remote* version —
a companion watching right/wrong from their own phone — is a different feature with a
real privacy cost, since guiding well means seeing the photos: see the note in
**Deliberately not built**.

## Design rules held in code

| Spec rule | Where it lives |
| --- | --- |
| Recognition only, never free recall | Every level is tap-to-select over a curated set |
| The answer is never a coin flip | `DifficultyKnob.chronologyDecisiveGap`, enforced in `ChronologyCurator`; Places allows exactly one photo from the target place |
| No visible time pressure | Duration is captured in `GameEngine.select` and used only by `DifficultyKnob.adaptToPace` |
| Photo content never leaves the device | Only `ImageProvider` (drawing) and `ObjectTagger` (on-device classification) touch bytes; no image or label is stored or transmitted, and classification makes no network call |
| Objects is opt-outable | `CaregiverSettings.objectsThemeEnabled`; off means the app is strictly metadata-only |
| No clinical language | `ClaimLanguage` carries the safe line and standing disclaimer verbatim |
| Mono stays crisp, optional, never the only lever | `PhotoTile` uses `grayscale(1).contrast(1.14)`; `CaregiverSettings.MonochromeMode` can be switched off |
| Telemetry is aggregate, never per-person/per-place | `EngagementEvent` has no field that could carry a photo, place or person |

## Layout

```
Photo Chronology/
  Model/          GameModel (themes, photos, levels, difficulty knob, theme rotation),
                  GameEngine, CompanionPrompts (Together-mode hints and questions)
  Sourcing/       PhotoLibraryService (PhotoKit metadata), PlaceResolver (geocode + cache),
                  ObjectCatalog (Vision allow-list), ObjectTagger (on-device classification),
                  PublicPacks (pack manifests), PackArtRenderer, ImageProvider
  Curation/       Curators (Chronology, Places, Objects), LevelGenerator (pooling and blending)
  Settings/       CaregiverSettings
  Telemetry/      Engagement (events + sinks), TelemetryQueue, StatsStore
  Views/          RootView, PlayView, CaregiverViews, HowsItGoingView, AboutView, DesignSystem
Tools/CurationHarness/  run.sh — invariant checks over thousands of generated levels
```

`Tools/CurationHarness/run.sh` compiles the curation logic on its own — no simulator,
no Xcode project — and is the fastest way to re-tune the difficulty knob and see what
it does to the time windows.

## iPad

The app runs on both device families. On a regular-width screen it keeps its content in
a centred column rather than stretching edge to edge, brings every size of type up a
notch (an iPad is held further away and has the room), lays a set of three photos out in
one row and a set of five as three-then-two, and gives caregiver setup a page-sized sheet
instead of the small form sheet iPadOS defaults to — which matters once the text size is
turned up. Copy is device-neutral: nothing says "your iPhone".

## Deliberately not built

- **Album-scoped themes** (Birthdays / Weddings) — v1.1 in the spec.
- **Tier 2 caregiver pairing** (§7.2) — deferred, per the spec's own note that it is a
  bigger lift and isn't needed for a playable v1. Tier 1, the on-device "How's it going"
  screen, is built, and Together mode covers the same-room case without any pairing at
  all. The setup screen says so in-app.
- **Live remote guiding** — a companion watching right/wrong in real time from elsewhere.
  Worth naming as a deliberate omission rather than an oversight: to guide usefully the
  companion needs to see the photos, which is exactly what §9 promises never leaves the
  device, and a stored per-item right/wrong history is the decline-detection dataset §7.2
  rules out. Ephemeral live signal could be defensible; persisted history is not.
- **OneBucket client** (§8) — `EngagementSink` is the seam. `LocalFileSink` ships and
  writes newline-delimited JSON to Application Support; `OneBucketSink` is a stub that
  reports itself unconfigured, because the bucket namespace and event schema are still
  open (§12). Swap it in `TelemetryQueue.init` when they're settled. Pack *delivery* over
  OneBucket is likewise unbuilt — the `1970s Americana` pack shows the slot, disabled.
- **Licensed pack imagery** (§6.2, §12) — no third-party photos are bundled. The three
  bundled packs carry real dates and real coordinates and render placeholder era artwork
  procedurally, which exercises every code path a licensed pack will use. Replacing
  `PackArtRenderer` with real image files is the only change needed.

## Running the Objects theme

The image classifier **cannot load in the iOS Simulator** — every request there fails with
`Failed to create espresso context`, including a synthetic control image, so it is the
simulator's Core ML runtime rather than anything in the app. On a simulator the Things
theme quietly falls back to the photo packs, whose subjects are hand-written, and
Diagnostics → Things coverage says so in as many words. Run on a device to see personal
photos classified.

A classifier failure is never cached, so a run that fails leaves every photo pending for
the next launch; only a genuine "nothing recognised in this photo" is remembered.

## Notes for the open decisions (§12)

- **Which Vision categories to ship** — the allow-list in `ObjectCatalog` is a first pass:
  24 broad categories across five families, each with the taxonomy identifiers that feed
  it and its own confidence floor. Every identifier is a real entry in Vision's 1,303-label
  taxonomy, and because that taxonomy is hierarchical, matching the broad parent also
  catches the breeds and varieties beneath it. Caregiver setup → Diagnostics → **Things
  coverage** reports how many photos each category matched on a real library — that report
  is the evidence for pruning the list and tuning the floors.
- **Geocoding provider** — the prototype uses MapKit's `MKReverseGeocodingRequest`, which
  is free, needs no API key, and sends only coordinates. Its `cityWithContext` is already
  the phrasing a question wants ("Rome, Italy", "San Francisco, CA"). It is rate-limited,
  so `PlaceResolver` throttles to one request every 1.2s, caps lookups per launch, resolves
  the largest clusters first, and caches results permanently. That class is the single seam
  to swap for a paid provider.
- **Screenshots** are excluded by default rather than needing a caregiver to notice them.
- Simulator libraries are tiny and mostly same-dated, so packs blend in constantly there;
  on a real library they mostly stay out of the way (35% chance per level, plus gap-filling).
- The claim line for Objects (`ClaimLanguage.objectsPrivacy`) is a draft written to match
  the pattern of the Places line. The Evidence Foundation doc's "Unified claim language"
  section is authoritative and should carry the final wording.
