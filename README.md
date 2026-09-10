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
  Model/          GameModel (themes, photos, levels, difficulty knob, theme rotation), GameEngine
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

## Deliberately not built

- **Album-scoped themes** (Birthdays / Weddings) — v1.1 in the spec.
- **Tier 2 caregiver pairing** (§7.2) — deferred, per the spec's own note that it is a
  bigger lift and isn't needed for a playable v1. Tier 1, the on-device "How's it going"
  screen, is built. The setup screen says so in-app.
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
