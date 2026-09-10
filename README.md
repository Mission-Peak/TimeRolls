# Photo Chronology — v1 prototype

An iOS prototype of the Photo-Chronology concept, built to
`PhotoChronology_Prototype_Spec_v1` (Attimis, 10 Sep 2026). SwiftUI, iOS 26.5,
no third-party dependencies.

Open `Photo Chronology.xcodeproj` and run on a simulator or device.

## What plays today

Both v1 themes are live, driven by PhotoKit metadata only:

- **Time** — "Which photo is older?" over 3–5 photos. Difficulty is the time-delta
  lever from spec §5.1: the library is bucketed into time windows and levels are
  sampled inside one of them. Gentle levels put ~11 years between the answer and
  the runner-up; the hardest close to ~10 months.
- **Places** — "Which photo was taken in [place]?" Coordinates are reverse-geocoded
  through `CLGeocoder`, cached per ~11 km cluster on disk, and looked up once.
  Harder levels draw distractors from nearby towns, gentle ones from other continents.

Around that: errorless feedback (a wrong tap dims and you try again — no score, no
fail state, no visible clock), silent adaptive difficulty, a soft-gated caregiver
setup, on-device aggregate progress, and an anonymous engagement queue.

## Design rules held in code

| Spec rule | Where it lives |
| --- | --- |
| Recognition only, never free recall | Every level is tap-to-select over a curated set |
| The answer is never a coin flip | `DifficultyKnob.chronologyDecisiveGap`, enforced in `ChronologyCurator`; Places allows exactly one photo from the target place |
| No visible time pressure | Duration is captured in `GameEngine.select` and used only by `DifficultyKnob.adaptToPace` |
| Photo content never leaves the device | `ImageProvider` is the only place bytes are touched, and only to draw them |
| No clinical language | `ClaimLanguage` carries the safe line and standing disclaimer verbatim |
| Mono stays crisp, optional, never the only lever | `PhotoTile` uses `grayscale(1).contrast(1.14)`; `CaregiverSettings.MonochromeMode` can be switched off |
| Telemetry is aggregate, never per-person/per-place | `EngagementEvent` has no field that could carry a photo, place or person |

## Layout

```
Photo Chronology/
  Model/          GameModel (themes, photos, levels, difficulty knob), GameEngine
  Sourcing/       PhotoLibraryService (PhotoKit metadata), PlaceResolver (geocode + cache),
                  PublicPacks (pack manifests), PackArtRenderer, ImageProvider
  Curation/       Curators (Chronology + Places), LevelGenerator (pooling and blending)
  Settings/       CaregiverSettings
  Telemetry/      Engagement (events + sinks), TelemetryQueue, StatsStore
  Views/          RootView, PlayView, CaregiverViews, HowsItGoingView, AboutView, DesignSystem
Tools/CurationHarness/  run.sh — invariant checks over thousands of generated levels
```

`Tools/CurationHarness/run.sh` compiles the curation logic on its own — no simulator,
no Xcode project — and is the fastest way to re-tune the difficulty knob and see what
it does to the time windows.

## Deliberately not built

- **Objects theme and album-scoped themes** — v1.1 in the spec.
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

## Notes for the open decisions (§12)

- **Geocoding provider** — the prototype uses `CLGeocoder`, which is free, needs no API
  key, and sends only coordinates. It is rate-limited, so `PlaceResolver` throttles to one
  request every 1.2s, caps lookups per launch, resolves the largest clusters first, and
  caches results permanently. If that ceiling becomes a problem, the class is the single
  seam to swap for a paid provider.
- **Screenshots** are excluded by default rather than needing a caregiver to notice them.
- Simulator libraries are tiny and mostly same-dated, so packs blend in constantly there;
  on a real library they mostly stay out of the way (35% chance per level, plus gap-filling).
