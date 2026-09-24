# How a round gets built

Every question in Time Rolls is assembled on the device, from photographs the app has
already looked at. The photographs, the answer, the difficulty and the facts are all
settled by the rules below before any model is asked anything.

Apple's on-device model is allowed two jobs, both of them downstream of every rule here.
It may **reword** the finished question, and anything it writes that breaks a guardrail is
thrown away in favour of the written one. And it may **take a finished round away** (§4) —
never keep one the rules rejected, never choose a photograph, never decide an answer. If
it is missing, switched off, or slow, the game plays exactly as it would have without it.

Two ideas run through all of it. **The answer is never arguable** — if a round could have
two defensible answers, it is thrown away and another is built. And **absence of evidence
is not evidence of absence** — a photograph nothing has looked at yet is never treated as
a photograph with nothing in it.

---

## 1. What the device knows about each photograph

Each photograph goes through one pass, in the background, a chunk at a time. Everything
here runs on the device; no image and no label leaves it.

| Pass | Framework | What it produces |
|---|---|---|
| Metadata | PhotoKit | date, coordinates, album, burst identifier, screenshot/panorama/selfie flags |
| Place name | MapKit reverse geocoding | "McLean, VA", the country and its code, one lookup per ~11 km cluster |
| Classification | Vision `ClassifyImageRequest` | tags from a fixed taxonomy, split into *confident* and *possible* |
| Faces | Vision `DetectFaceRectanglesRequest` | whether there is a face, and how much of the frame the largest one fills |
| Face quality | Vision `DetectFaceCaptureQualityRequest` | how good a shot of a person it is |
| Text | Vision `RecognizeTextRequest` (fast) | how much of the frame is text, by area |
| Aesthetics | Vision `CalculateImageAestheticsScoresRequest` | Apple's quality score, and `isUtility` |
| Saliency | Vision `GenerateAttentionBasedSaliencyImageRequest` | where the subject sits in the frame |
| Similarity | Vision `GenerateImageFeaturePrintRequest` | a fingerprint for comparing two photographs |
| Reading | **SigLIP 2 base patch16-224**, bundled, 8-bit, 88 MB | 512 numbers, and from them: the occasion, the thing, and whether it is a photograph of anywhere |

The embedding is kept (about a kilobyte per photograph, half precision). Everything
else is stored as a handful of numbers and flags. The cache is versioned; bumping the
version re-reads the library.

### What the embedding model is asked

Three tables of vectors, written as English sentences and embedded once on a Mac with the
matching text encoder — which is why the text half of the model is not in the app.

- **themes** (`Tools/Themes/themes.json`) — 98 occasions: birthdays, weddings, snow, by
  the sea, a walk, a harbour. Each carries the question a round asks when every photograph
  shares it, and each is written with several phrasings so a photograph matches on meaning
  rather than on one lucky word. They are checked against each other as well as against
  photographs: four of the 102 written were merged because no two questions could tell
  them apart.
- **concepts** (`Tools/Themes/concepts.json`) — one per thing the Things game can ask
  about, four phrasings each, averaged.
- **scenes** (`Tools/Themes/scenes.json`) — whether a photograph is outdoors, a room, a
  portrait, a group, or one of five kinds of note-to-self.

To change what the app understands, edit a sentence and re-run `Tools/Themes/embed_themes.py`.

---

## 2. What never reaches a round

- **Screenshots, panoramas, and every burst frame but one** — PhotoKit says so, for free.
- **Utility images** — Apple's `isUtility`, then a text-area check (more than 18% of the
  frame across at least four regions) as a second opinion.
- **Notes to self** — a photograph that matches "a floor, a wall, a plain surface", "a
  label, a parking space, a price tag", "a scratch, a dent, a stain", "an identity card,
  a licence, a ticket" or "a product listing" better than it matches any occasion, *and*
  has no face in it, *and* has nothing the classifier could name.
- **Near-duplicates** — feature prints closer than 0.22, compared against the last 40
  neighbours. Of each run the app keeps the best: the best face shot, or failing that the
  better-rated photograph.
- **Photographs that could not be fetched** — an iCloud photograph that will not come
  down is a blank card, and is dropped from later rounds.
- **Anything a caregiver has struck off** — a plain list of identifiers, kept on the
  device, obeyed exactly and without inference (spec §4). It is applied in `pool(for:)`,
  the one door every round *and* every "can this theme be played" check comes through, so
  a struck photograph cannot even argue a theme into being offered. Leaving one out offers
  to leave out the rest of its day, its place or its month, because nobody takes a single
  photograph at a funeral.
- **The duller half** — when at least 60 photographs have been rated and at least 40 would
  remain, rounds draw from the better half by Apple's score.

---

## 3. Building a round

### Time — "which came first"

1. Sort by date; slide a window whose width comes from the difficulty knob.
2. Prefer windows containing the player's own photographs.
3. Narrow the window in passes, giving up one thing at a time: one occasion → one kind
   (faces or scenery) → one subject → one pack → whatever is left.
4. The oldest photograph in the window is the answer. Every other photograph must be
   clearly later:
   - a share of the library's own span for personal photographs — about a year for five
     years of photographs, two to three for twenty — scaled by difficulty;
   - **fifty years** whenever a public photograph is involved, never relaxed, because
     nobody can place two strangers' photographs a decade apart.
5. Personal photographs must also be apart from **each other**, not just from the answer,
   or three photographs of one graduation fill the round.
6. Distractors are ranked by how much they *look* like the answer — most alike on a hard
   round, least on a gentle one — then spread across the window.
7. If every photograph shares an occasion, the question names it: "Which birthday came
   first?" Otherwise a pack's own phrasing, or "Which photo is older?".

Famous Faces is dated by **birth**, not by when the photograph was taken, so the question
is "Who was born first?" and the reveal says "born 1901".

### Places — "which photo is from…"

- A photograph qualifies only if it has a place name, has been looked at, is not a
  close-up (no selfie; the largest face under 8% of the frame), and **reads as outdoors**
  — a street, a building, a landscape. A photograph taken indoors says nothing about where
  it was taken.
- Every photograph in the round must be **120 km** from every other, and from a different
  region; two photographs from one foreign country never appear together.
- A place is only used as the question when there are three or more photographs there —
  one photograph is a car park, several is a visit. Landmarks from the packs are exempt.
- The question asks at the coarsest name that still points at one photograph: the country
  when abroad, the state or county at home, the town only when two share a region.
- **Places asked about lately go to the back of the queue.** Without this, a library whose
  personal photographs cluster in one state asks about that state nearly every round: the
  ordering is stable and the same place keeps winning it. Occasions has the same memory.
- Distractors are the ones that look most like the answer, whatever the difficulty —
  Places has its own lever in how near the other places are — but never one that looks
  *nearly identical* to it. Alike is the point; identical is a coin toss dressed as a
  decision, which is how a round ends up as three anonymous streets and one of them being
  Shibuya.

### Occasions — "which photo is from Dad's 80th?"

The only question about somebody's own photographs whose answer nobody inferred. An album
is a person, at some point, deciding that these pictures belong together and typing what
they are — the same certainty the packs have, sitting unused in every camera roll.

- The name has to be one a **person** chose. `AlbumNames` rejects by rule, never by guess:
  *Recents*, *Favourites*, *Screenshots*, *Untitled Album*, anything containing `IMG_` or
  `DSC_`, anything under three characters or over forty, anything with no letters in it.
- An album needs **three photographs** before its name means anything — one is an accident,
  three is an occasion. The same rule Places uses for a place.
- No distractor may come from that album, **or from one whose name reads as the same
  album**: "Italy" and "Italy 2019" are one holiday to whoever named them.
- One photograph per album among the distractors, so the reveal never shows two from the
  same holiday with only one of them counting as right.
- Photographs in no album at all are perfectly good distractors — the question only ever
  asks which one *is* from the album.
- Packs have no albums, so this theme is never propped up by them. Either the player's own
  library carries it or it is not offered.

The round audit never rules on this one. Which album somebody filed a photograph in is not
in the photograph; the model would be guessing at "Dad's 80th" from a cake, and disagreeing
with a fact.

### Things — "which one has…"

**When the pack names the photograph, the question uses the name.** The Animals pack
carries a hand-written name and a Wikipedia sentence for every photograph, and the game
asks "which photo has a lion in it?" rather than "which one is a mammal?". The coarse
question was never caution about the photographs — it was caution about the *classifier*,
which you need when reading a stranger's camera roll and do not need for a pack somebody
curated by hand. Distractors are then chosen by name rather than by class, so a lion can
stand beside a tiger and a leopard: four animals and a real decision, instead of one
mammal beside a bird, a fish and a lizard where the biology gives it away.

The exception is creatures a person could argue over from a photograph — alligator and
crocodile, hare and rabbit, moth and butterfly, moose and elk. `ObjectCatalog.confusable`
lists them and no round may hold two members of a group, checked on **every pair** rather
than only against the answer.

For everything else — the player's own photographs — the older machinery still applies:

- The question comes from **the embedding model's reading**, not from the classifier's
  tags: a photograph must be read as the thing, above a floor and clear of whatever came
  second. A library it has not reached yet falls back to tags rather than going quiet.
- A distractor must carry no hint of the thing from either model — not in the classifier's
  *possible* tags, not as the embedding model's own reading.
- The answer must beat every distractor on the thing by a margin, **and** the thing must be
  what the embedding model says the answer most is. The margin alone let a cat answer "which one has a
  dog", because a cat beats a plate of food at looking like a dog.
- Harder rounds draw distractors from the same family — a cat and a horse against a dog.
- Subjects asked about recently go to the back of the queue.
- **Some things can never be asked about.** A tree is in the background of half of all
  outdoor photographs, and the rule that keeps a distractor out only works when something
  *noticed* the tree in it — nothing notices the tree behind a group at a party. So
  `tree`, `water`, `building`, `bridge` and `car` are barred as questions. They remain
  perfectly good themes; they are only unfit as the thing a question hunts for.
- **A portrait is never the answer.** A picture of somebody standing on a boat is a
  picture of *them*, even when the boat is the most nameable thing in it. A face filling
  more than 22% of the frame means the photograph is about the face.
- **Only the answer is captioned.** Naming every photograph the classifier could name left
  some tiles with a word under them and some blank — not because those held nothing, but
  because nothing had been written down about them.

---

## 4. The last check, before anyone sees it

A finished round is handed to Apple's on-device model, which sees the same photographs and
the same question and picks one. If it picks a different photograph, or says more than one
would do, the round is discarded and another is built — which costs nothing, because the
next round is prepared while the player is still looking at this one.

It may only ever **take a round away**. Three boundaries, all deliberate:

- **Things, always.** What is in a photograph is visible to anyone.
- **Places, only for pack rounds.** Nothing in a picture of a back garden says Virginia;
  that is answered by GPS, and the player is remembering their own garden rather than
  reading the pixels. Letting the model rule on those would delete the theme for anyone
  playing with their own library.
- **Time, never.** The date in the file is the answer. A model would be reading the grain
  and the haircuts.

**Silence keeps the round.** No model, no Apple Intelligence, no answer inside eight
seconds, an unreadable reply — none of it is evidence against a round, so none of it takes
one away. A device with a busy model must not quietly play a worse game than one without.

Measured on pack landmark rounds whose answers are known to be right: it agreed with 40 of
40 rounds built from landmarks it can name, and 38 of 40 built from landmarks it cannot.
Naming a photograph and choosing among four are different tasks — it cannot produce "Ben
Nevis" from a blank page, but shown four photographs it only has to notice that one is a
Scottish mountain. Recognition beats recall, which is what the whole game is built on.

---

## 5. Reading a description of a personal photograph

`DescribedPhotos` reads a plain description and decides whether a photograph is a memory
or a note to self. It exists because the rule-based filters keep half-missing the same
thing: a photograph of a floor taken to show a scratch has no text, no face, an ordinary
aesthetic score and nothing nameable, so every signal says "fine". A description gives it
away in a sentence.

The guard that matters is the opposite mistake. Taking away somebody's photograph of their
husband holding a certificate, because "certificate" looked like paperwork, is far worse
than showing one dull floor — so anything with a person or an animal in it is kept
whatever else is said, surfaces only count when the picture is *of* the surface, and no
description at all keeps the photograph.

**Not yet wired:** nothing generates the descriptions. The rules are tested and idle.

---

## 6. Before any of it ships — vetting the packs

`Tools/PackVet` is a separate routine, run on a Mac rather than a device, over the public
photographs before they ship. It asks the model to **describe** each photograph and reads
the answer, rather than asking whether the photograph shows X. That is measured, not
preferred: asking directly scores 17%, describing and reading scores 67%, and the direct
question answered "no" for a photograph of Big Ben whose own description named Big Ben.

It flags; it never deletes. At 67% a third of what it catches is the model's mistake, so it
writes a list for a person. And it never relabels anything: the pack says "robin" where the
model offers "a small bird with an orange chest", and the pack is the better authority in
every pack we ship.

---

## 7. Difficulty

One knob, 0 to 1, moved silently by how the last rounds went and — if the caregiver leaves
it on — by how long they took. It moves four things: how close together in time the
photographs are, how near the other places are, how often distractors come from the same
family, and how much they resemble the answer. It never changes the number of photographs
beyond the device's own cap (four on a phone, five on an iPad).

---

## 8. What checks all this

`Tools/CurationHarness/run.sh` builds about twelve thousand rounds against synthetic
libraries and asserts the invariants: the answer is always the oldest, public photographs
are always fifty years apart, no round repeats a day or a moment, Places rounds never show
a close-up and never two places within 120 km, Things rounds have exactly one true answer
even when a fifth of the library is deliberately mislabelled, and the difficulty lever
actually moves.

It also reads the **shipped pack manifests off disk** — the same bytes the app bundles —
and checks that every photograph has a licence, a credit and a source, that no picture or
id is used twice, and that each pack can build 120 rounds for every theme it claims. That
check found the same photograph of Sally Ride entered twice under two names on its first
run. A pack is content, and content is what nobody re-checks after the day it was built.

It also checks the newer rules: a photograph a caregiver struck off appears in none of six
hundred rounds across every theme, a round built from a zoo of look-alikes never holds both
the hare and the rabbit, a reworded question may not invent a word or point at one
photograph, and every way the round audit can fail to answer keeps the round.

Several of those fixtures exist because a real round went wrong first, and several were
written to fail before they were written to pass — the exclusion check fails 554 times
when the filter is removed, which is how we know it is checking something.
