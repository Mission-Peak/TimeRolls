# iRecollect — v1 prototype

An iOS prototype of the Photo-Chronology concept, built to
`PhotoChronology_Prototype_Spec_v1` (Attimis, 10 Sep 2026). SwiftUI, iOS 26.5,
no third-party dependencies.

The app is called **iRecollect** on the home screen and everywhere a person sees it.
The Xcode project, the scheme and the bundle identifier (`hanna.Photo-Chronology`) keep
their original names on purpose: changing a bundle identifier makes every installed copy
a different app, which would wipe the settings and progress on any device already
testing it. Renaming those is a deliberate, separate step whenever it's wanted.

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

**The player picks what they play.** Anyone who declines their own photos at first run
chooses a set of photos instead — one tap on a card, with a real photograph on it, no
confirm step. During play the chip at the top left says what is being played and is how
it changes: it opens a picker for the kind of question (a mix, or one theme pinned) and
which sets of photos are in play. Both lists are live — turning on a set of photos with
coordinates makes Places appear as a choice.

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

**How much CC0 is out there.** Commons alone holds about **8 million CC0 JPEGs** — 3.3
million across a dozen everyday subjects. Supply is not the constraint; app size is, which
is why packs download rather than ship (see below).

Other sources checked: Openverse aggregates far more but its API returned 504s throughout
testing; the Cleveland Museum (1,023 CC0 works), Art Institute of Chicago (132k) and Met
(577 with images) are all keyless but art-heavy rather than photographic.

**Sources.** `commons-geo` geosearches Wikimedia Commons around a landmark coordinate, so
those items carry real coordinates and can drive the Places theme. `commons-subject`
searches the whole CC0 pool by subject, which is where volume comes from. `smithsonian` pulls
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
| Travel Landmarks | 48 | 2002–2025 | Wikimedia Commons | Places (27 cities), Time |
| Decades | 56 | 1884–1980 | Smithsonian Open Access | Time |

Decades runs one query per decade and caps each decade's contribution, so it spreads
evenly — six photos per decade from the 1880s through the 1960s. The 1970s and 1980s thin
out to one apiece: CC0 material from those decades is overwhelmingly the Smithsonian
photographing its own buildings, which the subject filter removes.

Travel Landmarks queries 40 landmarks across six continents and yields 27 cities; the
other 13 have no strict-CC0 photography within range. More cities is not only more
content — Places picks its distractors by distance from the answer, so the spread is what
gives that difficulty lever something to work with.

**Subject filtering is a safety feature, not tidiness.** An archive search returns a
lynching victim's funeral, machine-gun companies and train wrecks alongside the picnics —
the first build of this pack contained Emmett Till's funeral. For an audience of older
adults, some living with dementia, in a game designed around avoiding distress, none of
that can ship. The builder filters by subject before anyone sees it: 119 items were
rejected as distressing on the last run and 303 as institutional records rather than
scenes. The landmarks run caught a photograph captioned "Hitler at the Charles Bridge,
Prague" — a picture of an occupation to anyone old enough to remember it.

The word lists in `build_pack.py` are deliberately conservative and are the right place to
adjust that judgement. Two lessons are baked into them: military abbreviations matter,
because a title like "366 Inf. 92nd Div." never trips a filter looking for "infantry"; and
proper nouns need their own list, because no amount of topic vocabulary catches a caption
whose only distressing word is a name.
| Classic Holidays | 12 | 1951–2019 | Procedural placeholder art | all three |

**What the licence filter costs.** Strict CC0 buys legal clarity and loses the middle of
the twentieth century. CC0 material is bimodal: pre-1900 museum holdings and post-2010
photography, with 1940–1990 — precisely the era this audience remembers — thinly covered.
If mid-century nostalgia turns out to matter for the experience, that is an argument for
licensing a collection rather than for loosening the filter.

**A filter for photographs, not just images.** Geosearch returns whatever is pinned at a
coordinate (maps, diagrams, a webcam still, a video poster) and the Smithsonian returns
paintings, sketchbook folios and herbarium sheets. Both are filtered out — by MIME type
and title for Commons, by `object_type` for the Smithsonian.

**Packs stay in the background when they should.** Once the player's own library can
carry a theme, a level is allowed at most one pack photo: §6.2b asks for pack photos
blended *alongside* personal ones, and without a cap a dense pack wins a time window
outright and the level comes out entirely stock. Curation is random, so the generator
simply tries a few times and keeps the least-stock result. Geocoding also keeps running in
waves until the player's own places are named — while fewer than three are known, Places
counts as sparse and the landmark pack carries it, which is the wrong outcome for a
library full of real holidays.

Pack photographs are classified on device by the same Vision pass as personal photos, so
they work in the Things theme too. A pack that appears in a later build arrives switched
on rather than hidden.

## Where the photographs come from

A pack is a manifest: a date, a place, a credit and a source URL per photograph. Most
packs carry no images at all — the photographs stay where they already live, on Wikimedia
Commons and Smithsonian Open Access, and are fetched the first time a round needs one and
kept on the device from then on.

That is what makes the catalogue affordable. **350 photographs cost 171 KB as metadata**;
the same photographs bundled would be roughly 80 MB. The app is 14 MB with 452
photographs available to it.

| Pack | Photos | Years | Carries | Source |
| --- | --- | --- | --- | --- |
| Famous Faces | 18 | 1863–1993 | Time, Things | Commons (curated) |
| Milestones | 11 | 1883–1997 | Time, Things | Commons (curated) |
| Space | 23 | 1962–2024 | Time, Things | NASA (curated) |
| Sports | 36 | 1860–1949 | Time, Things | Smithsonian |
| Stage and Screen | 43 | 1858–1962 | Time, Things | Smithsonian |
| Travel Landmarks | 46 | 2002–2025 | Places, Things | Commons |
| Natural Wonders | 35 | 2012–2026 | Places, Things | Commons |

**Packs are photographs people recognise; everyday life comes from the player's own
library.** That division is the point of the whole content strategy. An earlier pack of
anonymous everyday scenes was unplayable — a stranger's 2019 kitchen means nothing to
anyone, and there is no way to date it either.

**Significance has to be curated, not searched.** An archive has no idea which of its
holdings everyone has already seen, so Famous Faces, Milestones and Space are written
lists — Lincoln, Einstein, Migrant Mother, the Wright brothers, Earthrise, the bootprint —
looked up one at a time.

**And the year has to be checked against the photograph.** The year belongs to the event,
not to whenever a scan was uploaded, so it is written down with the list; but a keyword
search for "Neil Armstrong 1969" cheerfully returns a 2020 photograph of a museum display.
Every curated item is verified against the photograph's own date and dropped if it
disagrees by more than three years — a dating game that teaches the wrong date is worse
than one with fewer photographs. That check removed seven of the first thirty-six matches.

**Licences are declared per pack, not assumed.** CC0 is the default and the safest: a
worldwide waiver. A pack of famous photographs cannot live on it, though — almost nothing
iconic was ever CC0-released — so the curated packs also accept two other footings, named
in the manifest: copyright that has expired, and US federal government work, which carries
none by statute. That second one is why anything between 1930 and 1990 is reachable at
all.

**A pack says which games it can carry, and that is not a formality.** The first attempt
at an everyday-life pack was unplayable for "which photo is older" because 331 of its 350
photographs came from 2000 onward — nothing about a 2019 kitchen tells you it isn't a 2022
one. Travel Landmarks has the same shape and is declared places-and-things for the same
reason. Anything asked to carry Time has to come from an era-spread historical source,
which in practice means the Smithsonian: its CC0 photographs run from the 1850s to the
1960s, while Commons CC0 is overwhelmingly post-2010.

Where a pack is built by searching for a subject, the subject is recorded in the manifest
rather than left to the classifier — a photograph found under "kitten" contains a cat. That
also closes a gap: photographs fetched on demand never reach the on-device classifier, so
without declared subjects they could never be the *answer* to a Things round, only a
distractor.

**Wi-Fi only, and fetched once.** `RemoteImageCache` refuses cellular and expensive
networks outright, so nobody's mobile data goes on a photo game, and a photograph is
fetched exactly once ever. Commons permits this kind of linking and asks that reusers
cache rather than re-fetch, and that tools identify themselves — both of which this does.

**Nothing half-ready is ever shown.** The next round is built and its photographs fetched
while the current one is being played, so moving on is instant. If a photograph can't be
had — Commons warns that files get renamed or deleted, and it does happen — that
photograph drops out of the pool and the round is rebuilt without it. A dead link
degrades the catalogue rather than breaking a game.

**Offline** falls back to the starter pack and the player's own photos, which is the
trade this design accepts: iPads are almost always on wi-fi, and personal photos never
need the network at all.

## Publishing a pack

```bash
python3 Tools/PackBuilder/build_pack.py --pack everyday --metadata-only \
    --out "Photo Chronology/Packs"
```

A metadata-only pack needs no hosting: it points at the original sources. The OneBucket
delivery path (`PackDownloader`, `make_catalog.py`, `upload_packs.sh`) is still built and
tested, for packs whose photographs need to be hosted rather than linked — but it is no
longer on the critical path, and OneBucket's gateway does not currently serve anonymous
reads (see `diagnose_public.sh`).

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
