//
//  main.swift — curation harness
//
//  Generates thousands of levels against a synthetic library and checks the
//  invariants the game depends on: the answer is always unambiguous, distractors
//  are always plausible, the difficulty knob actually tightens the time window,
//  and thin or GPS-poor libraries degrade instead of erroring.
//
//  Run with Tools/CurationHarness/run.sh — it needs no simulator and no Xcode project.
//
import Foundation
import CoreLocation

// A synthetic library: 400 photos over 60 years, half of them geotagged across 14 places.
func makeLibrary() -> [GamePhoto] {
    var rng = SystemRandomNumberGenerator()
    let places: [(String, Double, Double)] = [
        ("Rome, Italy", 41.90, 12.49), ("Milan, Italy", 45.46, 9.19),
        ("Naples, Italy", 40.85, 14.27), ("Lyon, France", 45.76, 4.83),
        ("Nice, France", 43.71, 7.26), ("Boston, USA", 42.36, -71.06),
        ("Denver, USA", 39.74, -104.99), ("Austin, USA", 30.27, -97.74),
        ("Dublin, Ireland", 53.35, -6.26), ("Cork, Ireland", 51.90, -8.48),
        ("Oslo, Norway", 59.91, 10.75), ("Kyoto, Japan", 35.01, 135.77),
        ("Perth, Australia", -31.95, 115.86), ("Lisbon, Portugal", 38.72, -9.14),
    ]
    return (0..<400).map { index in
        let secondsAgo = Double.random(in: 0...(60 * .year), using: &rng)
        let place = Bool.random(using: &rng) ? places.randomElement(using: &rng)! : nil
        // Roughly six photos in ten get a subject, as a real classifier would give.
        var confident: Set<String> = []
        var possible: Set<String> = []
        if Double.random(in: 0...1, using: &rng) < 0.6 {
            let category = ObjectCatalog.categories.randomElement(using: &rng)!
            confident.insert(category.id)
            possible.insert(category.id)
            // Plus the odd hint the classifier wasn't sure about.
            if Double.random(in: 0...1, using: &rng) < 0.3 {
                possible.insert(ObjectCatalog.categories.randomElement(using: &rng)!.id)
            }
        }
        var photo = GamePhoto(
            id: "p\(index)",
            origin: .personal(localIdentifier: "p\(index)"),
            creationDate: Date(timeIntervalSinceNow: -secondsAgo),
            coordinate: place.map { Coordinate(latitude: $0.1, longitude: $0.2) },
            placeName: place?.0,
            objectTags: confident,
            possibleObjectTags: possible)
        // The app looks at every photograph before it uses one, so a library that has
        // never been looked at is not a library the app would ever see.
        //
        // Leaving this false quietly excluded the whole library from Places, which refuses
        // an unexamined photograph on purpose: a face prominence of zero means nobody has
        // looked, not that there is no face. So Places measured zero of the player's
        // photographs in three hundred rounds — and that was the fixture, not the game.
        photo.wasExamined = true
        photo.aesthetics = Double.random(in: 0.2...0.9, using: &rng)
        return photo
    }
}

var failures: [String] = []
func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

let library = makeLibrary()
// Stand-in pack photos. The harness builds its own rather than reading the shipped
// packs: those are app resources, and a check of the curation rules should not depend
// on which packs happen to be bundled this week.
func makePackPhotos(count: Int = 40) -> [GamePhoto] {
    var rng = SystemRandomNumberGenerator()
    let places = ["Rome, Italy", "Paris, France", "Kyoto, Japan", "Boston, USA",
                  "Cairo, Egypt", "Sydney, Australia", "Oslo, Norway", "Lima, Peru"]
    return (0..<count).map { index in
        let category = ObjectCatalog.categories.randomElement(using: &rng)!
        let place = places[index % places.count]
        return GamePhoto(
            id: "pack:test:\(index)",
            origin: .pack(packID: "test", itemID: "\(index)"),
            // Two centuries, because that is what a pack claiming chronology actually looks
            // like — Famous Faces spans 546 years. At eighty this fixture could not hold
            // four public photographs twenty-five years apart plus one of the player's,
            // so five-card rounds failed on arithmetic rather than on any rule.
            creationDate: Date(timeIntervalSinceNow: -Double.random(in: 0...(200 * .year), using: &rng)),
            coordinate: Coordinate(latitude: Double(index % 80) - 40, longitude: Double(index % 170) - 85),
            placeName: place,
            objectTags: [category.id],
            possibleObjectTags: [category.id])
    }
}

var generator = LevelGenerator()
generator.personal = library
generator.pack = makePackPhotos()

// --- Three to one: one of the player's own photographs per round, the rest from packs.
//
// Measured rather than asserted per round, because the ratio is a target the generator
// reaches by asking a curator again, not a rule it can enforce. What matters is that a
// full library lands on it nearly always, and that a library with nothing to offer a
// theme still gets a round instead of an empty screen.
var mixCounts: [Int: Int] = [:]
var mixRounds = 0
var mixByTheme: [GameTheme: (none: Int, one: Int, asked: Int)] = [:]
for theme in GameTheme.allCases {
    for _ in 0..<300 {
        mixByTheme[theme, default: (0, 0, 0)].asked += 1
        guard let level = generator.makeLevel(theme: theme) else { continue }
        mixRounds += 1
        let mine = level.photos.count(where: \.isPersonal)
        mixCounts[mine, default: 0] += 1
        if mine == 0 { mixByTheme[theme, default: (0, 0, 0)].none += 1 }
        if mine == 1 { mixByTheme[theme, default: (0, 0, 0)].one += 1 }
    }
}
for theme in GameTheme.allCases {
    let entry = mixByTheme[theme] ?? (0, 0, 0)
    print("   \(theme.title): \(entry.one) with one, \(entry.none) with none, "
        + "of \(entry.asked) asked")
}
let onTarget = mixCounts[LevelGenerator.personalPhotosWanted] ?? 0
check(mixRounds > 0, "the balance check built no rounds at all")
// Never more than one. This is the part that has to be exact, and it is exact because the
// pool only ever holds one, not because the generator got lucky.
let tooMany = mixCounts.filter { $0.key > LevelGenerator.personalPhotosWanted }
    .values.reduce(0, +)
check(tooMany == 0,
      "\(tooMany) rounds held more than \(LevelGenerator.personalPhotosWanted) "
    + "of the player's own photographs")
check(Double(onTarget) / Double(max(mixRounds, 1)) >= 0.70,
      "only \(onTarget) of \(mixRounds) rounds had "
    + "\(LevelGenerator.personalPhotosWanted) personal photograph")
print("three to one — \(onTarget) of \(mixRounds) rounds had exactly one personal photo"
    + " · spread \(mixCounts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " "))")

// --- Invariants across every round size, both themes.
//
// This used to sweep a difficulty lever from 0 to 1 and check the game got harder, and
// then a round size from 3 to 5. Both are gone: every round is four photographs. What is
// left is the part that was never about difficulty — that rounds come out answerable —
// run enough times to be a measurement rather than a coin toss.
var gaps: [TimeInterval] = []
var sameFamily = (same: 0, total: 0)

do {
    do {
        for _ in 0..<3960 {
            guard let chrono = generator.makeLevel(theme: .chronology) else {
                failures.append("chronology returned nil")
                continue
            }
            check((3...5).contains(chrono.photos.count), "photo count \(chrono.photos.count)")
            // A dated round comes from one pack, so the question it asks fits every
            // photograph in it. Mixed, it asked "which occurred first" of a painting
            // and three people.
            let datedPacks = Set(chrono.photos.filter(\.dateIsAboutTheSubject)
                                              .compactMap(\.packID))
            check(datedPacks.count <= 1,
                  "a Time round mixed \(datedPacks.sorted().joined(separator: " and "))")
            // Never two photographs of the same thing in one round — with several
            // photographs per subject in a pack, that would mark a right answer wrong.
            let subjects = chrono.photos.compactMap(\.subjectID)
            check(Set(subjects).count == subjects.count,
                  "a round held two photographs of the same subject")
            // A generation between every pair of public photographs, and the player's
            // own picture at the recent end of the round.
            let publicWhen = chrono.photos
                .filter { !$0.isPersonal && $0.dateIsAboutTheSubject }
                .compactMap(\.creationDate).sorted()
            for (index, earlier) in publicWhen.enumerated() {
                for later in publicWhen.dropFirst(index + 1) {
                    check(later.timeIntervalSince(earlier)
                            >= DifficultyKnob.everyPublicPairMinimumGap,
                          "a Time round held two public photographs "
                        + String(format: "%.1f", later.timeIntervalSince(earlier) / .year)
                        + " years apart")
                }
            }
            // A subject-dated round is all pack photographs: nobody's dinner has a
            // birth year, and a fourth option that can never be the answer is not an
            // option.
            if chrono.photos.contains(where: \.dateIsAboutTheSubject) {
                check(!chrono.photos.contains(where: \.isPersonal),
                      "a \"who was born first\" round held one of the player's photographs")
            }
            check(Set(chrono.photos.map(\.id)).count == chrono.photos.count, "duplicate photo in level")
            let sorted = chrono.photos.sorted { $0.creationDate! < $1.creationDate! }
            check(sorted.first!.id == chrono.correctPhotoID,
                  "correct answer is not the oldest photo")
            let gap = sorted[1].creationDate!.timeIntervalSince(sorted[0].creationDate!)
            check(gap >= 30 * .day,
                  "answer is only \(Int(gap / .day))d older than the runner-up")
            gaps.append(gap)

            // A set with a public photograph in it has to span eras, not years: nobody
            // can place two strangers' photographs a decade apart.
            if chrono.photos.contains(where: { !$0.isPersonal && $0.dateIsAboutTheSubject }),
               sorted.allSatisfy({ $0.isPersonal || $0.dateIsAboutTheSubject }) {
                check(gap >= DifficultyKnob.publicPhotographMinimumGap,
                      "a public photograph appeared only \(Int(gap / .year))y from the answer")
            }

            guard let places = generator.makeLevel(theme: .places) else {
                failures.append("places returned nil")
                continue
            }
            check((3...5).contains(places.photos.count), "places photo count")
            let target = places.photos.first { $0.id == places.correctPhotoID }
            check(target != nil, "places level has no correct photo in its set")
            if let targetName = target?.placeName {
                let matching = places.photos.filter { $0.placeName == targetName }
                check(matching.count == 1,
                      "places level has \(matching.count) photos from the target place — ambiguous")
                // Either the town or the wider place it is in: a round asks by the
                // region when no other photograph in it comes from that region.
                let wider = targetName.split(separator: ",").last
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? targetName
                check(places.prompt.contains(PlacesCurator.shortName(targetName))
                        || places.prompt.contains(wider)
                        || PlacesCurator.regionHint(for: targetName)?
                            .contains(places.prompt
                                .replacingOccurrences(of: "Which photo is from ", with: "")
                                .replacingOccurrences(of: "?", with: "")) == true,
                      "prompt \(places.prompt.debugDescription) names neither "
                        + "\(targetName.debugDescription) nor the region it is in")
            }
            check(places.photos.allSatisfy { $0.placeName != nil }, "places level has an unnamed photo")

            guard let objects = generator.makeLevel(theme: .objects) else {
                failures.append("objects returned nil")
                continue
            }
            check((3...5).contains(objects.photos.count), "objects photo count")
            check(Set(objects.photos.map(\.id)).count == objects.photos.count,
                  "duplicate photo in an objects level")
            guard let subject = objects.photos.first(where: { $0.id == objects.correctPhotoID }),
                  let categoryID = subject.objectTags.first(where: { tag in
                      objects.prompt.contains(ObjectCatalog.category(id: tag)?.subject ?? "\u{0}")
                  }),
                  let category = ObjectCatalog.category(id: categoryID) else {
                failures.append("objects level prompt does not match the answer's tags")
                continue
            }
            for distractor in objects.photos where distractor.id != objects.correctPhotoID {
                check(!distractor.possibleObjectTags.contains(categoryID),
                      "an objects distractor might also contain \(categoryID) — ambiguous")
                // An untagged photo is not a known-clean photo. It is a photo nothing is
                // known about, and it may be full of the subject.
                check(!distractor.objectTags.isEmpty,
                      "an objects distractor was never classified, so nothing rules "
                        + "\(categoryID) out of it")
            }
            let distractors = objects.photos.filter { $0.id != objects.correctPhotoID }
            let same = distractors.filter { photo in
                photo.objectTags.contains { ObjectCatalog.category(id: $0)?.family == category.family }
            }.count
            sameFamily.same += same
            sameFamily.total += distractors.count
        }
    }
}

// --- Time rounds stay readable. There is no lever to check any more, so what matters is
// that the spread never collapses: a round whose photographs sit a few months apart is a
// coin toss whoever is playing.
let meanGap = gaps.reduce(0, +) / Double(max(gaps.count, 1))
check(!gaps.isEmpty, "no chronology gaps were measured at all")
check(meanGap >= DifficultyKnob.everyPublicPairMinimumGap,
      "time rounds average only \(Int(meanGap / .year))y apart")
print("time rounds — \(gaps.count) measured, mean gap \(Int(meanGap / .year))y, "
    + "closest \(Int((gaps.min() ?? 0) / .year))y")

// --- Objects reaches for same-family distractors some of the time, and not most of it.
let familyShare = Double(sameFamily.same) / Double(max(sameFamily.total, 1))
check(familyShare > 0.05 && familyShare < 0.60,
      "same-family distractors came out at \(Int(familyShare * 100))%, "
    + "which is either never or nearly always")

// --- Objects must decline when the classifier has found nothing.
var untagged = LevelGenerator()
untagged.personal = makeLibrary().map {
    var copy = $0
    copy.objectTags = []
    copy.possibleObjectTags = []
    return copy
}
check(untagged.makeLevel(theme: .objects) == nil,
      "Objects should decline when no photo has a recognised subject")

// --- Pack art alone can carry the theme (its subjects are hand-written, not classified).
var packOnly = LevelGenerator()
packOnly.pack = makePackPhotos()
check(packOnly.makeLevel(theme: .objects) != nil,
      "packs should be able to carry an Objects level on their own")

// --- A pack-only chronology level must still clear fifty years.
var packOnly2 = LevelGenerator()
packOnly2.pack = makePackPhotos(count: 60)
var packGaps: [TimeInterval] = []
for _ in 0..<200 {
    guard let level = packOnly2.makeLevel(theme: .chronology) else { continue }
    let sorted = level.photos.sorted { $0.creationDate! < $1.creationDate! }
    packGaps.append(sorted[1].creationDate!.timeIntervalSince(sorted[0].creationDate!))
}
check(!packGaps.isEmpty, "no pack-only chronology levels could be built at all")
check(packGaps.allSatisfy { $0 >= DifficultyKnob.publicPhotographMinimumGap },
      "a pack-only level came out \(Int((packGaps.min() ?? 0) / .year))y apart, under the fifty-year floor")

// --- A level made entirely of one kind of thing asks about that kind, not about
// photographs: "which of these was the earliest president".
var subjectOnly = LevelGenerator()
let subjects = ["president", "boxer", "film star"]
subjectOnly.pack = (0..<90).map { index in
    GamePhoto(id: "pack:subjects:\(index)",
              origin: .pack(packID: "subjects", itemID: "\(index)"),
              creationDate: Date(timeIntervalSinceNow: -Double.random(in: 0...(120 * .year))),
              subject: subjects[index % subjects.count])
}
subjectOnly.packChronologyPrompts = ["subjects": "Who came first?"]
var namedTheSubject = 0
var subjectLevels = 0
for _ in 0..<300 {
    guard let level = subjectOnly.makeLevel(theme: .chronology) else { continue }
    subjectLevels += 1
    let kinds = Set(level.photos.compactMap(\.subject))
    if kinds.count == 1 {
        namedTheSubject += 1
        check(level.prompt == "Which of these was the earliest \(kinds.first!)?",
              "a level of \(kinds.first!)s asked \(level.prompt.debugDescription)")
    } else {
        check(level.prompt == "Who came first?",
              "a mixed-subject level asked \(level.prompt.debugDescription)")
    }
}
check(subjectLevels > 0, "no chronology levels could be built from subject-tagged pack photos")
check(Double(namedTheSubject) / Double(max(subjectLevels, 1)) > 0.8,
      "only \(namedTheSubject) of \(subjectLevels) pack-only levels came out as one kind of thing")

// --- A personal photograph in the set means the player is placing their own photograph,
// so the question goes back to being about the photograph.
var mixedSubjects = LevelGenerator()
mixedSubjects.personal = library
mixedSubjects.pack = subjectOnly.pack
for _ in 0..<300 {
    guard let level = mixedSubjects.makeLevel(theme: .chronology) else { continue }
    if level.photos.contains(where: \.isPersonal) {
        check(level.prompt == "Which photo is older?",
              "a level with the player's own photo in it asked \(level.prompt.debugDescription)")
    }
}

// --- Rounds should not keep asking about the same photographs.
var fresh = LevelGenerator()
fresh.pack = makePackPhotos(count: 120)
// Three hundred rounds rather than forty. The share being measured is a property of the
// library and the window, not of how many rounds are drawn — but forty rounds is only
// about a hundred and seventy comparisons, where one extra repeat moves the figure by
// half a percent and the estimate wanders across the threshold. It failed twice in a day
// at 7% and 18% and passed cleanly either side, which is a test teaching people to ignore
// it. More draws, same bar, steady answer.
var repeatsWithinTen = 0
var comparisons = 0
var window: [String] = []
for _ in 0..<300 {
    fresh.recentlyUsed = Set(window)
    guard let level = fresh.makeLevel(theme: .chronology) else { continue }
    for photo in level.photos {
        comparisons += 1
        if window.contains(photo.id) { repeatsWithinTen += 1 }
        window.append(photo.id)
    }
    if window.count > 40 { window.removeFirst(window.count - 40) }
}
check(comparisons > 0, "no levels generated for the repetition check")
let photoRepeatShare = Double(repeatsWithinTen) / Double(max(comparisons, 1))
check(photoRepeatShare < 0.05,
      "\(Int(photoRepeatShare * 100))% of photos came round again inside the last forty")

// --- The daily rotation: steady all day, different tomorrow, and nothing left
// permanently on the shelf.
let catalogue = Array(0..<120)
let today = PhotoRotation.dayIndex()
let slice = PhotoRotation.selection(from: catalogue, packID: "faces", day: today)
check(slice == PhotoRotation.selection(from: catalogue, packID: "faces", day: today),
      "the same day gave two different selections")
check(slice.count == PhotoRotation.inPlay(from: catalogue.count),
      "daily slice is \(slice.count) of \(catalogue.count), not the expected share")
// Never more than half, whatever the pack holds — that is what leaves a second day's
// worth to deal and keeps consecutive days from overlapping. A flat slice did not: a
// pack of 192 showing 150 left 42 unseen and repeated four photographs in five.
check(slice.count * 2 <= catalogue.count,
      "a day's slice is more than half the pack, so days must overlap")
let nextDay = PhotoRotation.selection(from: catalogue, packID: "faces", day: today + 1)
let sharedWithNextDay = Set(slice).intersection(Set(nextDay)).count
check(sharedWithNextDay == 0,
      "\(sharedWithNextDay) photographs appear both today and tomorrow")
check(Set(slice).count == slice.count, "the daily slice repeats a photograph")

let tomorrow = PhotoRotation.selection(from: catalogue, packID: "faces", day: today + 1)
check(slice != tomorrow, "tomorrow's selection is identical to today's")
let otherPack = PhotoRotation.selection(from: catalogue, packID: "sports", day: today)
check(slice != otherPack, "two packs rotate in lockstep")

// Over a month, every photograph should get its turn.
var everSeen: Set<Int> = []
for offset in 0..<30 {
    everSeen.formUnion(PhotoRotation.selection(from: catalogue, packID: "faces",
                                                day: today + offset))
}
check(everSeen.count == catalogue.count,
      "\(catalogue.count - everSeen.count) photographs never appear in a month")

// A pack at or under the floor keeps all of its photographs.
let small = Array(0..<PhotoRotation.floor)
check(PhotoRotation.selection(from: small, packID: "a-pack", day: today).count
      == small.count, "a small pack was thinned below the floor")

// --- The Things game should not ask the same question twice in a row.
var thingsRun = LevelGenerator()
thingsRun.personal = library
thingsRun.pack = makePackPhotos(count: 80)
var askedAbout: [String] = []
var immediateRepeats = 0
var thingsLevels = 0
for _ in 0..<60 {
    thingsRun.recentCategories = askedAbout
    guard let level = thingsRun.makeLevel(theme: .objects),
          let tag = level.focusTag else { continue }
    thingsLevels += 1
    if askedAbout.last == tag { immediateRepeats += 1 }
    askedAbout.append(tag)
    if askedAbout.count > 6 { askedAbout.removeFirst(askedAbout.count - 6) }
}
check(thingsLevels > 20, "too few Things levels to judge repetition")
check(immediateRepeats == 0,
      "the Things game asked the same subject twice running \(immediateRepeats) times")

// --- Theme rotation: no theme may be starved, and repeats stay occasional.
var picked: [GameTheme: Int] = [:]
var repeats = 0
var previous: GameTheme?
let allThemes = GameTheme.allCases
for _ in 0..<30_000 {
    guard let next = ThemeRotation.next(from: allThemes, last: previous) else {
        failures.append("rotation returned nothing")
        break
    }
    picked[next, default: 0] += 1
    if next == previous { repeats += 1 }
    previous = next
}
for theme in allThemes {
    let observedShare = Double(picked[theme] ?? 0) / 30_000
    check(abs(observedShare - 1.0 / Double(allThemes.count)) < 0.03,
          "theme \(theme.title) is picked \(Int(observedShare * 100))% of the time, not an even share")
}
let repeatShare = Double(repeats) / 30_000
check(abs(repeatShare - (1 - ThemeRotation.alternateChance) / Double(allThemes.count)) < 0.02,
      "repeat rate is \(Int(repeatShare * 100))%, not the expected 10%")

// --- Sparse library: three dated photos and nothing else must still produce a level.
var sparse = LevelGenerator()
sparse.personal = (0..<3).map {
    GamePhoto(id: "s\($0)", origin: .personal(localIdentifier: "s\($0)"),
              creationDate: Date(timeIntervalSinceNow: -Double($0 + 1) * 3 * .year),
              coordinate: nil)
}
check(sparse.makeLevel(theme: .chronology) != nil,
      "a three-photo library should still make a Chronology level")
check(sparse.makeLevel(theme: .places) == nil,
      "Places should decline rather than fake a level with no geotags")

// --- GPS-poor library must degrade into the packs, not error.
var gpsPoor = LevelGenerator()
gpsPoor.personal = sparse.personal
gpsPoor.pack = makePackPhotos()
check(gpsPoor.makeLevel(theme: .places) != nil,
      "Places should fall back to pack photos when the library has no geotags")
check(gpsPoor.availableThemes().count == 3,
      "all three themes should be playable once packs are on")

// --- No packs, no photos at all.
let empty = LevelGenerator()
check(empty.availableThemes().isEmpty, "an empty library should offer no themes")

// --- Birth-dated packs ask about the person, not the photograph, and say so in the hint.
var births = LevelGenerator()
births.pack = (0..<60).map { index in
    GamePhoto(id: "pack:famous-faces:\(index)",
              origin: .pack(packID: "famous-faces", itemID: "\(index)"),
              creationDate: Date(timeIntervalSinceNow: -Double.random(in: 0...(180 * .year))),
              subject: ["singer", "president"][index % 2])
}
births.packChronologyPrompts = ["famous-faces": "Who was born first?"]
births.birthDatedPacks = ["famous-faces"]
var birthLevels = 0
for _ in 0..<200 {
    guard let level = births.makeLevel(theme: .chronology) else { continue }
    birthLevels += 1
    check(level.prompt.contains("born first"),
          "a birth-dated level asked \(level.prompt.debugDescription)")
    if let hint = level.hint {
        check(hint.contains("was born in"),
              "a birth-dated level hinted \(hint.debugDescription)")
    }
}
check(birthLevels > 0, "no levels could be built from a birth-dated pack")

// --- The player's own photographs come as one kind of picture: faces, or not faces.
func makeFacedLibrary(span: TimeInterval, count: Int = 300) -> [GamePhoto] {
    (0..<count).map { index in
        GamePhoto(id: "f\(index)",
                  origin: .personal(localIdentifier: "f\(index)"),
                  creationDate: Date(timeIntervalSinceNow: -Double.random(in: 0...span)),
                  showsPeople: index % 2 == 0)
    }
}
var faces = LevelGenerator()
faces.personal = makeFacedLibrary(span: 20 * .year)
var facedLevels = 0
var coherent = 0
for _ in 0..<300 {
    guard let level = faces.makeLevel(theme: .chronology) else { continue }
    let own = level.photos.filter(\.isPersonal)
    guard own.count >= 2 else { continue }
    facedLevels += 1
    if Set(own.map(\.showsPeople)).count == 1 { coherent += 1 }
}
check(facedLevels > 0, "no chronology levels came out of the face-tagged library")
let coherentShare = Double(coherent) / Double(max(facedLevels, 1))
check(coherentShare > 0.9,
      "only \(Int(coherentShare * 100))% of personal rounds were all faces or all not")

// --- How far apart the player's own photographs sit follows how many years they have.
func meanPersonalGap(span: TimeInterval) -> TimeInterval {
    var generator = LevelGenerator()
    generator.personal = makeFacedLibrary(span: span)
    var gaps: [TimeInterval] = []
    for _ in 0..<200 {
        guard let level = generator.makeLevel(theme: .chronology) else { continue }
        let dates = level.photos.compactMap(\.creationDate).sorted()
        guard dates.count >= 2 else { continue }
        gaps.append(dates[1].timeIntervalSince(dates[0]))
    }
    return gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
}
let fiveYears = meanPersonalGap(span: 5 * .year)
let twentyYears = meanPersonalGap(span: 20 * .year)
check(twentyYears > fiveYears * 1.2,
      "a twenty-year library spread its photographs no wider than a five-year one")
check(twentyYears >= 2 * .year,
      "a twenty-year library put its photographs only \(ChronologyCurator.describe(twentyYears)) apart")
check(fiveYears >= 240 * .day,
      "a five-year library put its photographs only \(ChronologyCurator.describe(fiveYears)) apart")

// --- Near-identical photographs never end up in the same round.
//
// The harness has no Vision, so it stands in a distance function of its own: photos
// are given a "moment" and two from the same moment are declared identical, which is
// what a burst or a re-shot photograph looks like to a feature print.
var moments: [String: Int] = [:]
var duplicates = LevelGenerator()
duplicates.personal = (0..<300).map { index in
    let moment = index / 3          // three photographs of every moment
    moments["d\(index)"] = moment
    return GamePhoto(id: "d\(index)",
                     origin: .personal(localIdentifier: "d\(index)"),
                     // The three share a minute, as a burst would.
                     creationDate: Date(timeIntervalSinceNow: -Double(moment) * 20 * .day
                                        - Double(index % 3) * 20),
                     showsPeople: moment % 2 == 0)
}
duplicates.visualDistance = { first, second in
    moments[first.id] == moments[second.id] ? 0.01 : 1.4
}
var duplicateRounds = 0
var roundsWithARepeat = 0
for _ in 0..<300 {
    guard let level = duplicates.makeLevel(theme: .chronology) else { continue }
    duplicateRounds += 1
    let used = level.photos.compactMap { moments[$0.id] }
    if Set(used).count != used.count { roundsWithARepeat += 1 }
}
check(duplicateRounds > 0, "no rounds could be built from the duplicate-heavy library")
check(roundsWithARepeat == 0,
      "\(roundsWithARepeat) rounds offered the same moment twice")

// --- Receipts and screenshots never reach a round.
var documents = LevelGenerator()
documents.personal = (0..<300).map { index in
    var photo = GamePhoto(id: "x\(index)",
                          origin: .personal(localIdentifier: "x\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 30 * .day))
    photo.looksLikeDocument = index % 3 == 0
    return photo
}
var documentRounds = 0
for _ in 0..<300 {
    guard let level = documents.makeLevel(theme: .chronology) else { continue }
    documentRounds += 1
    check(level.photos.allSatisfy { !$0.looksLikeDocument },
          "a round showed a photograph the tagger had marked as a document")
}
check(documentRounds > 0, "no rounds could be built once documents were excluded")

// --- A pack that names its photographs is asked about by name, and never puts two
// creatures in a round that a person could argue over.
//
// The Animals pack knows every photograph is a lion, a tiger, a moose. The game used to
// ask "which one is a mammal?" anyway. Asking by name is a better round — but only while
// nothing in it can be mistaken for the answer, so the confusable list is what makes the
// specific question safe, and it is checked on every pair rather than only against the
// answer.
var zoo = LevelGenerator()
let creatures = ["lion", "tiger", "moose", "elk", "rabbit", "hare", "crow", "raven",
                 "alligator", "crocodile", "frog", "toad", "eagle", "hawk", "panda",
                 "penguin", "dolphin", "whale", "octopus", "squid", "hedgehog", "badger",
                 "zebra", "giraffe", "flamingo", "otter", "weasel", "camel", "koala"]
zoo.pack = creatures.enumerated().map { index, creature in
    var photo = GamePhoto(id: "pack:animals:\(creature)",
                          origin: .pack(packID: "animals", itemID: creature))
    photo.objectTags = ["class-mammal"]
    photo.possibleObjectTags = ["class-mammal"]
    photo.title = "A \(creature)"
    photo.conceptID = "class-mammal"
    return photo
}

var namedRounds = 0, askedByName = 0
for level in (0..<400).compactMap({ _ in zoo.makeLevel(theme: .objects) }) {
    namedRounds += 1
    if !level.prompt.contains("mammal") { askedByName += 1 }

    // No two photographs in the round may be arguable against each other.
    let names = level.photos.compactMap { $0.title?.lowercased()
        .replacingOccurrences(of: "a ", with: "") }
    for (index, one) in names.enumerated() {
        for other in names.dropFirst(index + 1) {
            check(ObjectCatalog.canStandTogether(one, other),
                  "a round held both a \(one) and a \(other), which nobody could tell apart")
        }
    }
    // And the answer has to be the thing the question asks for.
    if let answer = level.photos.first(where: { $0.id == level.correctPhotoID }),
       let focus = level.focusTag, !level.prompt.contains("mammal") {
        check(answer.title?.lowercased().contains(focus) == true,
              "the question asked for \(focus) but the answer was \(answer.title ?? "—")")
    }
}
check(namedRounds > 0, "no rounds could be built from a pack of named creatures")
check(askedByName == namedRounds,
      "\(namedRounds - askedByName) rounds still asked \"which one is a mammal\" of a pack "
    + "that names every photograph")
check(ObjectCatalog.canStandTogether("lion", "tiger"),
      "a lion and a tiger were called confusable — the list is too broad to be useful")
check(!ObjectCatalog.canStandTogether("alligator", "crocodile"),
      "an alligator and a crocodile were allowed in the same round")

// The check above is weak on a mixed zoo: a rabbit and a hare rarely meet by chance, so
// it catches the rule being deleted only about once in four hundred rounds. This library
// is nothing but look-alikes — every creature has a twin — so a round can still be built
// (one from each pair) but any slip is near-certain to show.
var lookalikes = LevelGenerator()
lookalikes.pack = ["rabbit", "hare", "frog", "toad", "alligator", "crocodile",
                   "moose", "elk", "crow", "raven", "butterfly", "moth"]
    .map { creature in
        var photo = GamePhoto(id: "pack:animals:\(creature)",
                              origin: .pack(packID: "animals", itemID: creature))
        photo.objectTags = ["class-mammal"]
        photo.possibleObjectTags = ["class-mammal"]
        photo.title = "A \(creature)"
        photo.conceptID = "class-mammal"
        return photo
    }

var twinRounds = 0
for level in (0..<400).compactMap({ _ in lookalikes.makeLevel(theme: .objects) }) {
    twinRounds += 1
    let names = level.photos.compactMap { $0.title?.lowercased()
        .replacingOccurrences(of: "a ", with: "") }
    for (index, one) in names.enumerated() {
        for other in names.dropFirst(index + 1) {
            check(ObjectCatalog.canStandTogether(one, other),
                  "a round of look-alikes held both a \(one) and a \(other)")
        }
    }
}
check(twinRounds > 0,
      "no round could be built from a library of look-alikes — one of each pair should fit")

print("look-alikes — \(twinRounds) rounds from a zoo of twins, none held a pair")
print("named subjects — \(askedByName) of \(namedRounds) rounds asked by name, none arguable")

// --- Occasions: the answer is which album somebody filed it in, and nothing else.
//
// This is the only personal round whose answer nobody inferred — a person typed the name.
// So the checks are about the *name* rather than the picture: a round must never ask
// about a name the phone made up, and never put two photographs from the same holiday in
// front of somebody when only one of them counts as right.

var shoebox = LevelGenerator()
let albums = ["Hawaii 2019": 12, "Dad's 80th": 8, "The allotment": 6, "Christmas at Mum's": 9,
              "Recents": 30, "IMG_2021": 5, "Untitled Album": 7, "Favourites": 20,
              "Hawaii": 4]
var built: [GamePhoto] = []
var index = 0
for (album, count) in albums {
    for _ in 0..<count {
        var photo = GamePhoto(id: "p\(index)",
                              origin: .personal(localIdentifier: "p\(index)"),
                              creationDate: Date(timeIntervalSinceNow: -Double(index) * 20 * .day))
        photo.albumName = album
        built.append(photo)
        index += 1
    }
}
// Some photographs are in no album at all, which is most of a real camera roll.
for _ in 0..<60 {
    built.append(GamePhoto(id: "p\(index)", origin: .personal(localIdentifier: "p\(index)"),
                           creationDate: Date(timeIntervalSinceNow: -Double(index) * 20 * .day)))
    index += 1
}
shoebox.personal = built

// Album rounds are gone from Occasions, so the checks that tested them are gone too.
// They asked "which photo is from Dad's 80th?" using a name a person had chosen, which is
// better evidence than anything a model infers — but a round whose only personal
// photograph is the answer is solved by spotting which one is personal, without reading
// the question. What Occasions asks now is what a photograph shows, and that is checked
// where the identify rounds are.

// A library whose albums are all the phone's own has no Occasions to offer, and must say
// so rather than asking about "Recents".
var unsorted = LevelGenerator()
unsorted.personal = (0..<80).map { number in
    var photo = GamePhoto(id: "u\(number)", origin: .personal(localIdentifier: "u\(number)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(number) * 30 * .day))
    photo.albumName = ["Recents", "Favourites", "Screenshots"][number % 3]
    return photo
}
check(!AlbumNames.areDistinct("Italy", "Italy 2019"),
      "\"Italy\" and \"Italy 2019\" were treated as two different holidays")
check(AlbumNames.areDistinct("Hawaii 2019", "Dad's 80th"), "two plain names were confused")

print("album names — the rules still hold; the Occasions theme itself is gone")

// --- What somebody said, and which photograph they meant.
//
// Every photograph is numbered so it can be answered out loud. The recogniser hands back
// ordinary English, and ordinary English about numbers is full of traps: it writes "to"
// for two and "for" for four, people say "the third one" rather than "three", and they
// correct themselves out loud — which is why the *last* number wins rather than the first.

let spoken: [(String, Int, Int?)] = [
    ("two", 4, 2),
    ("2", 4, 2),
    ("number three", 4, 3),
    ("the third one", 4, 3),
    ("I think it's four", 4, 4),
    // Homophones the recogniser really does return.
    ("to", 4, 2),
    ("for", 4, 4),
    ("won", 4, 1),
    // Correcting yourself: the answer is what they settled on.
    ("no not one, three", 4, 3),
    ("two... sorry, four", 4, 4),
    // Nothing to act on.
    ("I don't know", 4, nil),
    ("they're all lovely", 4, nil),
    // Never a photograph that isn't there: a phone shows four, not five.
    ("five", 4, nil),
    ("nine", 4, nil),
    // But five is fine on an iPad.
    ("five", 5, 5),
]
for (said, count, expected) in spoken {
    let heard = SpokenNumbers.number(in: said, upTo: count)
    check(heard == expected,
          "heard \"\(said)\" among \(count) photographs as \(heard.map(String.init) ?? "nothing"), "
        + "expected \(expected.map(String.init) ?? "nothing")")
}
print("spoken answers — \(spoken.count) phrasings, including homophones and corrections")

// --- What the voice says after an answer.
//
// There is no score and no fail state, so these words are the only thing that happens
// after a wrong tap. Two rules: never a verdict, and never the same line twice running —
// somebody playing eight rounds hears this a dozen times in an afternoon, and a kind
// sentence becomes a nagging one on the third identical repeat.

let verdicts = ["wrong", "incorrect", "no,", "failed", "mistake", "bad", "sorry"]
for line in Encouragement.tryAgain + Encouragement.praise {
    for verdict in verdicts {
        check(!line.lowercased().contains(verdict),
              "the voice says \"\(line)\", which marks the player rather than encouraging them")
    }
    check(line.count <= 44, "\"\(line)\" is long to hear read aloud after every answer")
    check(line.hasSuffix("!") || line.hasSuffix(".") || line.hasSuffix("?"),
          "\"\(line)\" does not finish — the synthesiser needs the punctuation to land it")
}

for lines in [Encouragement.tryAgain, Encouragement.praise] {
    check(lines.count >= 5, "only \(lines.count) lines to choose from — that will wear out")
    var said = lines[0]
    for turn in 0..<200 {
        let next = Encouragement.next(from: lines, after: said)
        check(next != said, "the voice repeated \"\(next)\" twice running on turn \(turn)")
        check(lines.contains(next), "the voice said something that is not on the list")
        said = next
    }
}
// Every line has to be reachable, or a list of seven is really a list of two.
var everSaid: Set<String> = []
var cursor: String? = nil
for _ in 0..<2000 {
    let next = Encouragement.next(from: Encouragement.praise, after: cursor)
    everSaid.insert(next)
    cursor = next
}
check(everSaid.count == Encouragement.praise.count,
      "only \(everSaid.count) of \(Encouragement.praise.count) praise lines are ever said")

print("spoken feedback — \(Encouragement.tryAgain.count) encouragements and "
    + "\(Encouragement.praise.count) praises, none repeating, none a verdict")

// --- Some things cannot be asked about at all.
//
// "Which photo has a tree in it?" was asked of a round with two trees in it. Neither
// reading was wrong: a tree really is in the background of a group photograph at a party,
// and nothing had noticed it, so the distractor rules let it through. The question was
// the thing that was broken.

var woods = LevelGenerator()
woods.personal = (0..<200).map { number in
    var photo = GamePhoto(id: "w\(number)", origin: .personal(localIdentifier: "w\(number)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(number) * 9 * .day))
    // Half the library has a tree noticed in it, and — as in life — plenty of the rest
    // have one nobody wrote down.
    let concepts = ["tree", "cake", "dog", "water", "flower", "building", "cat"]
    photo.conceptID = concepts[number % concepts.count]
    photo.objectTags = [photo.conceptID!]
    photo.possibleObjectTags = photo.objectTags
    photo.wasExamined = true
    return photo
}
var thingsAsked: Set<String> = []
for _ in 0..<400 {
    guard let level = woods.makeLevel(theme: .objects),
          let focus = level.focusTag else { continue }
    thingsAsked.insert(focus)
}
for incidental in ObjectCatalog.tooIncidentalToAskAbout {
    check(!thingsAsked.contains(incidental),
          "a round asked which photo has a \(incidental) in it — that is in the background "
        + "of half of everybody's photographs")
}
check(!thingsAsked.isEmpty, "no Things round could be built once the incidental ones were out")

print("things worth asking — \(thingsAsked.count) subjects asked, none of them scenery")

// --- Reading a description of somebody's own photograph.
//
// The rules that catch notes-to-self work on text area, faces and classifier tags, and a
// photograph of a floor taken to show a scratch has none of those: no text, no face, an
// ordinary aesthetic score, nothing nameable. Every signal says "fine". It reached a round
// twice after being reported. A plain description — "a close-up of a wooden floor with a
// scratch" — gives it away immediately, so this reads descriptions.
//
// The danger is the opposite mistake. Taking away somebody's photograph of their husband
// holding a certificate, because the word "certificate" looked like paperwork, is far
// worse than showing one dull floor. So anything with a person in it is kept, whatever
// else the description says.

let setAsideCases: [(String, String)] = [
    ("A close-up of a wooden floor with a scratch on it.", "the floor, reported twice"),
    ("A screenshot of a weather app.", "a screenshot"),
    ("A receipt from a supermarket on a table.", "a receipt"),
    ("A handwritten note on a sticky note.", "a note"),
    ("A close-up of a price tag on a jumper.", "a label"),
    ("A photo of a computer screen showing an email.", "a screen"),
    ("A plain wall with a crack in it.", "damage"),
    ("A calendar on a kitchen wall.", "a reminder"),
]
for (description, why) in setAsideCases {
    check(!DescribedPhotos.keeps(DescribedPhotos.read(description)),
          "kept a photograph that is \(why): \u{201C}\(description)\u{201D}")
}

let keepCases = [
    "A man in a suit holding a certificate in a school hall.",
    "A woman smiling beside a whiteboard covered in writing.",
    "A child holding a menu in a restaurant.",
    "A nurse holding a chart beside a hospital bed.",
    "A group of people at a table with a birthday cake.",
    "A dog asleep on a carpet in front of a fire.",
    "A beach at sunset with boats on the water.",
    "An old stone church on a hill.",
]
for description in keepCases {
    check(DescribedPhotos.keeps(DescribedPhotos.read(description)),
          "set aside a real memory: \u{201C}\(description)\u{201D}")
}

// Silence keeps the photograph, like every other silence in this pipeline.
for quiet in [nil, "", "   ", "a"] as [String?] {
    check(DescribedPhotos.keeps(DescribedPhotos.read(quiet)),
          "a photograph was set aside because nothing had described it yet")
}

print("described photographs — \(setAsideCases.count) notes-to-self set aside, "
    + "\(keepCases.count) memories kept, silence keeps them all")

// --- A portrait is never the answer to a question about a thing.
//
// "Which photo has a boat in it?" was asked about a photograph of the player standing on
// one. The model was not wrong — a boat really is the most nameable thing in the frame —
// but the picture is of a person, and answering meant hunting behind a shoulder for a bit
// of rail. A photograph of somebody is about somebody.

var portraits = LevelGenerator()
portraits.personal = (0..<240).map { number in
    var photo = GamePhoto(id: "f\(number)", origin: .personal(localIdentifier: "f\(number)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(number) * 11 * .day))
    let concepts = ["boat", "cake", "dog", "flower", "bicycle", "book"]
    photo.conceptID = concepts[number % concepts.count]
    photo.objectTags = [photo.conceptID!]
    photo.possibleObjectTags = photo.objectTags
    photo.wasExamined = true
    // Every third photograph is a portrait: a face filling a third of the frame.
    photo.faceProminence = number % 3 == 0 ? 0.34 : 0.02
    return photo
}
var portraitRounds = 0
for _ in 0..<400 {
    guard let level = portraits.makeLevel(theme: .objects) else { continue }
    portraitRounds += 1
    let answer = level.photos.first { $0.id == level.correctPhotoID }
    check(answer?.isAPortrait != true,
          "a round about \(level.focusTag ?? "a thing") was answered by a portrait")
}
check(portraitRounds > 0, "no Things round survived once portraits could not be the answer")
check(GamePhoto(id: "x", origin: .personal(localIdentifier: "x")).isAPortrait == false,
      "a photograph with no face measured was called a portrait")

print("portraits — \(portraitRounds) Things rounds, none answered by a picture of somebody")

// --- Somebody's own photographs carry no caption, in any theme.
//
// Mixed rounds were the giveaway: a pack photograph named itself, a personal one showed a
// date or a place or nothing at all depending on what happened to be recorded about it.
// Beyond looking untidy, it quietly told the player which photographs were theirs.

var mixed = LevelGenerator()
mixed.personal = (0..<120).map { number in
    var photo = GamePhoto(id: "m\(number)", origin: .personal(localIdentifier: "m\(number)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(number) * 40 * .day))
    photo.coordinate = Coordinate(latitude: 30 + Double(number % 9) * 2,
                                  longitude: -100 + Double(number % 7) * 2)
    // Deliberately patchy: only some have a place name or an album, which is exactly the
    // state that produced captions on some tiles and not others.
    if number % 2 == 0 { photo.placeName = "Town \(number % 9)" }
    if number % 3 == 0 { photo.albumName = "Hawaii 2019" }
    photo.objectTags = ["cake"]
    photo.conceptID = "cake"
    photo.wasExamined = true
    return photo
}
var captioned = 0, personalSeen = 0
for theme in GameTheme.allCases where theme != .places {
    for _ in 0..<150 {
        guard let level = mixed.makeLevel(theme: theme) else { continue }
        for photo in level.photos where photo.isPersonal {
            personalSeen += 1
            if !level.caption(for: photo).isEmpty { captioned += 1 }
            if !level.name(for: photo).isEmpty { captioned += 1 }
        }
    }
}
check(personalSeen > 0, "no personal photographs appeared, so this checked nothing")
check(captioned == 0,
      "\(captioned) of \(personalSeen) personal photographs were captioned outside Places")

// Places is the exception, and there everything is captioned the same way: the place,
// for the player's photographs and the packs alike. A round where some tiles name a
// landmark and others name a state is not a row of four comparable things.
var placeRoundsChecked = 0
for _ in 0..<300 {
    guard let level = mixed.makeLevel(theme: .places) else { continue }
    placeRoundsChecked += 1
    for photo in level.photos {
        check(level.caption(for: photo) == (photo.placeName ?? ""),
              "a Places caption said something other than the place")
        check(!level.caption(for: photo).isEmpty,
              "a photograph in a Places round had no caption while others did")
    }
}
check(placeRoundsChecked > 0, "no Places round was built, so captions went unchecked")

print("personal photographs — \(personalSeen) shown, none captioned outside Places; "
    + "\(placeRoundsChecked) Places rounds evenly captioned")

// --- The note about supporting the app is asked once, late, and never mid-game.
//
// The person holding the iPad may not remember having been asked, may not remember
// whether they already gave, and cannot meaningfully consent to a purchase in the middle
// of a game. So the bar is deliberately high and the count is exactly one.

let weekAgo = Date(timeIntervalSinceNow: -8 * 86_400)
let yesterday = Date(timeIntervalSinceNow: -86_400)

check(Supporting.shouldAsk(firstPlayed: weekAgo, sessions: 9, alreadyAsked: false),
      "somebody who has played for over a week was never asked")
check(!Supporting.shouldAsk(firstPlayed: weekAgo, sessions: 9, alreadyAsked: true),
      "the app asked for money a second time")
check(!Supporting.shouldAsk(firstPlayed: yesterday, sessions: 9, alreadyAsked: false),
      "asked on the second day of using it")
check(!Supporting.shouldAsk(firstPlayed: weekAgo, sessions: 2, alreadyAsked: false),
      "asked somebody who opened it twice and put it down")
check(!Supporting.shouldAsk(firstPlayed: nil, sessions: 40, alreadyAsked: false),
      "asked somebody who has never actually played")

// However long it runs, it is asked once. Nothing accumulates towards a second ask.
var timesAsked = 0
for day in 0..<400 {
    let started = Date(timeIntervalSinceNow: -Double(day) * 86_400)
    if Supporting.shouldAsk(firstPlayed: started, sessions: day * 2,
                            alreadyAsked: timesAsked > 0) {
        timesAsked += 1
    }
}
check(timesAsked <= 1, "over a year of playing the app asked \(timesAsked) times")

print("supporting — asked once, after \(Supporting.afterDays) days and "
    + "\(Supporting.afterSessions) sessions, never twice")

// --- A distractor may not plainly contain the thing, however far ahead the answer is.
//
// A real round: one photograph of a meal, another of a cat sitting beside a plate of
// dinner. The first scored a little higher on "food", which was all the old rule asked,
// so the player was shown two photographs of food and asked which had food in it. Beating
// the others at being food is not the same as the others not being food.

var kitchen = LevelGenerator()
// A library where a third of the photographs plainly contain food and say nothing about
// it in their tags — a cat on a table, a party, a picnic.
var foodScores: [String: Double] = [:]
kitchen.personal = (0..<240).map { number in
    var photo = GamePhoto(id: "k\(number)", origin: .personal(localIdentifier: "k\(number)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(number) * 13 * .day))
    let concepts = ["food", "cat", "dog", "flower", "cake", "bicycle"]
    photo.conceptID = concepts[number % concepts.count]
    photo.objectTags = [photo.conceptID!]
    photo.possibleObjectTags = photo.objectTags
    photo.wasExamined = true
    // Food is plainly in shot in every third photograph, whatever the tags say.
    foodScores["k\(number)"] = photo.conceptID == "food" ? 0.09
        : (number % 3 == 0 ? 0.055 : 0.010)
    return photo
}
kitchen.conceptScore = { photo, concept in
    concept == "food" ? foodScores[photo.id] : (photo.conceptID == concept ? 0.09 : 0.01)
}
kitchen.bestConcept = { $0.conceptID }

var foodRounds = 0
for _ in 0..<400 {
    guard let level = kitchen.makeLevel(theme: .objects),
          level.focusTag == "food" else { continue }
    foodRounds += 1
    for photo in level.photos where photo.id != level.correctPhotoID {
        let score = foodScores[photo.id] ?? 0
        // Against a fixed number, not against the constant being tested — checking a
        // rule against its own setting passes however the setting is changed, which is
        // the same as not checking it. 0.040 is where the themes model calls a concept
        // present.
        check(score < 0.040,
              "a round asked which photo has food in it beside one scoring \(score) on food")
    }
}
check(foodRounds > 0, "no food round could be built once hidden food was excluded")

print("hidden food — \(foodRounds) rounds, no distractor plainly containing the thing")

// --- How much of a photograph is words.
//
// A receipt photographed in a car footwell reached a round asking which photo was older.
// The old rule summed the boxes of the individual lines, and on a receipt almost all the
// paper is in the gaps *between* the lines — so a picture that is plainly a receipt
// measured as barely any text at all.
//
// The boxes below are in the frame's own units, as Vision reports them: x, y, width,
// height from 0 to 1.

func lines(count: Int, x: Double, width: Double, top: Double, height: Double,
           gap: Double) -> [CGRect] {
    (0..<count).map { CGRect(x: x, y: top + Double($0) * (height + gap),
                             width: width, height: height) }
}

// The receipt: a tall narrow column of thin lines down a third of the frame. Half its
// lines lost to fast recognition on crumpled paper, so only 24 of about 50 are found.
let receipt = lines(count: 24, x: 0.34, width: 0.30, top: 0.05, height: 0.012, gap: 0.022)
let receiptReading = TextDensity.reading(from: receipt)
check(receiptReading.covered < 0.18,
      "the fixture is wrong: this receipt would have been caught by the old rule anyway")
check(TextDensity.looksLikeADocument(receiptReading),
      "a receipt covering \(Int(receiptReading.enclosed * 100))% of the frame was not "
    + "read as a document (its lines sum to only \(Int(receiptReading.covered * 100))%)")

// A screenshot: text tiling the frame. The old rule caught these and must still.
let screenshot = lines(count: 18, x: 0.05, width: 0.90, top: 0.05, height: 0.030, gap: 0.020)
check(TextDensity.looksLikeADocument(TextDensity.reading(from: screenshot)),
      "a screenshot stopped being read as a document")

// And the photographs this must never take away.
let keepThese: [(String, [CGRect])] = [
    ("a shopfront with a big sign",
     lines(count: 3, x: 0.20, width: 0.55, top: 0.10, height: 0.040, gap: 0.010)),
    ("somebody holding a certificate",
     lines(count: 5, x: 0.35, width: 0.28, top: 0.40, height: 0.015, gap: 0.012)),
    ("a race number on a runner",
     lines(count: 1, x: 0.45, width: 0.12, top: 0.50, height: 0.060, gap: 0)),
    ("a birthday banner across a room",
     lines(count: 2, x: 0.10, width: 0.75, top: 0.08, height: 0.050, gap: 0.015)),
    ("a street sign in the corner of a holiday photo",
     lines(count: 2, x: 0.72, width: 0.20, top: 0.12, height: 0.030, gap: 0.008)),
]
for (what, boxes) in keepThese {
    check(!TextDensity.looksLikeADocument(TextDensity.reading(from: boxes)),
          "\(what) was thrown away as a document")
}
check(!TextDensity.looksLikeADocument(TextDensity.reading(from: [])),
      "a photograph with no text found in it was called a document")

// Somebody in front of a wall of writing is a photograph of them. A menu board, a
// noticeboard, a chalkboard in a classroom — all of them would fail the paper tests, and
// all of them are exactly the pictures this game is for.
let menuBoard = lines(count: 22, x: 0.08, width: 0.80, top: 0.06, height: 0.018, gap: 0.014)
check(TextDensity.looksLikeADocument(TextDensity.reading(from: menuBoard)),
      "a photographed menu board was not read as a document")
check(!TextDensity.looksLikeADocument(TextDensity.reading(from: menuBoard), hasFace: true),
      "somebody standing in front of a menu board was thrown away as a document")
// A screenshot is still a screenshot even if the classifier thinks it sees a face in it —
// a photograph of a phone showing a photograph of somebody, say.
check(TextDensity.looksLikeADocument(TextDensity.reading(from: screenshot), hasFace: true),
      "a screenshot survived because something face-shaped was in it")

print("words in a photograph — receipt caught at \(Int(receiptReading.enclosed * 100))% "
    + "enclosed, \(keepThese.count) photographs with writing in them kept")

// --- A photograph the model described as a note to self is never shown.
//
// The rules in DescribedPhotos existed for days with nothing feeding them, which is why a
// receipt reached a round: the model could name it and was never asked. Now it is asked,
// and this checks the two halves that matter — what it sets aside really goes, and what it
// has not looked at yet is unaffected.

var described = LevelGenerator()
described.personal = (0..<200).map { number in
    var photo = GamePhoto(id: "d\(number)", origin: .personal(localIdentifier: "d\(number)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(number) * 16 * .day))
    photo.coordinate = Coordinate(latitude: 40 + Double(number % 8) * 1.4,
                                  longitude: -80 + Double(number % 6) * 1.4)
    photo.placeName = "Town \(number % 8)"
    photo.objectTags = ["cake"]
    photo.conceptID = "cake"
    photo.wasExamined = true
    return photo
}
// A quarter of them turn out to be receipts, floors and screenshots — and, as in life,
// nothing in their tags says so.
let notMemories = Set(described.personal.filter { Int($0.id.dropFirst()) ?? 0 % 4 == 0 }
    .prefix(50).map(\.id))
described.setAsideByDescription = notMemories

var describedRounds = 0
for theme in GameTheme.allCases {
    for _ in 0..<150 {
        guard let level = described.makeLevel(theme: theme) else { continue }
        describedRounds += 1
        let shown = Set(level.photos.map(\.id)).intersection(notMemories)
        check(shown.isEmpty,
              "a round showed \(shown.count) photograph(s) the model called a note to self")
    }
}
check(describedRounds > 0, "no rounds survived once the described notes were set aside")

// And a library nothing has described yet plays exactly as before — silence keeps them.
var undescribed = LevelGenerator()
undescribed.personal = described.personal
check(undescribed.makeLevel(theme: .chronology) != nil,
      "a library the model has not looked at yet stopped producing rounds")

print("described notes — \(describedRounds) rounds, none showed one; "
    + "an undescribed library is untouched")

// --- A question somebody got wrong is not asked again.
//
// The pairing, not the theme and not the photograph. Somebody who could not pick the
// Eiffel Tower out of four monuments is never asked to pick it again — while the Eiffel
// Tower stays usable as a wrong answer in somebody else's round, which is what keeps one
// bad afternoon from thinning the library.

var practised = LevelGenerator()
practised.pack = ["lion", "tiger", "moose", "penguin", "otter", "camel", "koala", "zebra",
                  "giraffe", "flamingo", "badger", "hedgehog"].map { creature in
    var photo = GamePhoto(id: "pack:animals:\(creature)",
                          origin: .pack(packID: "animals", itemID: creature))
    photo.objectTags = ["class-mammal"]
    photo.possibleObjectTags = ["class-mammal"]
    photo.title = "A \(creature)"
    photo.conceptID = "class-mammal"
    return photo
}

// Play until a lion round comes up, then get it wrong.
var missedSubject: String?
var missedAnswer: String?
for _ in 0..<200 {
    guard let level = practised.makeLevel(theme: .objects),
          let subject = level.focusTag, subject == "lion" else { continue }
    missedSubject = subject
    missedAnswer = level.correctPhotoID
    break
}
check(missedSubject != nil, "no lion round came up, so nothing was tested")
if let subject = missedSubject, let answer = missedAnswer {
    practised.missedPairings = [AlreadyMissed.key(subject: subject, answer: answer)]

    var askedAgain = 0, stillPlayable = 0, appearedAsDistractor = 0
    for _ in 0..<400 {
        guard let level = practised.makeLevel(theme: .objects) else { continue }
        stillPlayable += 1
        if level.focusTag == subject, level.correctPhotoID == answer { askedAgain += 1 }
        if level.photos.contains(where: { $0.id == answer }) { appearedAsDistractor += 1 }
    }
    check(askedAgain == 0, "the lion was asked again \(askedAgain) times after being missed")
    check(stillPlayable > 0, "the library stopped producing rounds after one wrong answer")
    check(appearedAsDistractor > 0,
          "the missed photograph vanished from the game entirely — it should still stand "
        + "beside other questions as a wrong answer")
    print("already missed — asked \(askedAgain) times again, still appeared in "
        + "\(appearedAsDistractor) of \(stillPlayable) rounds as a distractor")
}

// Chronology has no subject, so nothing there is ever retired: the same four photographs
// in a different order is a different question.
check(!AlreadyMissed.wasMissed(subject: nil, answer: "p1", among: ["x"]),
      "a round with no subject was retired")
check(!AlreadyMissed.wasMissed(subject: "", answer: "p1", among: [""]),
      "a round with an empty subject was retired")
check(AlreadyMissed.wasMissed(subject: "lion", answer: "p1",
                              among: [AlreadyMissed.key(subject: "lion", answer: "p1")]),
      "a missed pairing was not recognised")
check(!AlreadyMissed.wasMissed(subject: "lion", answer: "p2",
                               among: [AlreadyMissed.key(subject: "lion", answer: "p1")]),
      "a different photograph of the same subject was retired too")

// --- A photograph a caregiver has struck off is never shown again.
//
// This is the one control in the app that has to be absolute. Every other rule here is
// a judgement about what makes a good round; this one is somebody saying "not that one,
// not ever", usually for a reason they should not have to explain and that no rule could
// have anticipated. A list that is obeyed most of the time is worse than no list, because
// it is a promise that breaks when someone has stopped watching for it.
//
// So it is checked on every theme, and on the availability checks too — a photograph that
// is struck off must not even count towards whether a theme can be played.
var struck = LevelGenerator()
struck.personal = (0..<240).map { index in
    var photo = GamePhoto(id: "p\(index)",
                          origin: .personal(localIdentifier: "p\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 20 * .day))
    photo.coordinate = Coordinate(latitude: 34 + Double(index % 12) * 1.5,
                                  longitude: -118 + Double(index % 9) * 1.5)
    photo.placeName = "Town \(index % 12)"
    photo.objectTags = index % 4 == 0 ? ["dog"] : ["cake"]
    photo.wasExamined = true
    return photo
}
// Strike off a third of them, including every photograph of a dog — the shape of a real
// request ("no more pictures of the dog") rather than a scattering of ids.
let struckOff = Set(struck.personal.filter { $0.objectTags.contains("dog") }.map(\.id))
    .union(struck.personal.prefix(20).map(\.id))
struck.excluded = struckOff

var struckRounds = 0
for theme in GameTheme.allCases {
    for _ in 0..<200 {
        guard let level = struck.makeLevel(theme: theme) else { continue }
        struckRounds += 1
        let shown = Set(level.photos.map(\.id)).intersection(struckOff)
        check(shown.isEmpty,
              "a round showed \(shown.count) photograph(s) a caregiver had struck off")
    }
}
check(struckRounds > 0, "no rounds could be built once photographs were struck off")

// Striking one off must also take it out of the reckoning for whether a theme is playable,
// or a theme can be offered on the strength of photographs that can never be shown.
var onlyDogs = LevelGenerator()
onlyDogs.personal = struck.personal.filter { $0.objectTags.contains("dog") }
let couldPlayBefore = onlyDogs.availableThemes()
onlyDogs.excluded = Set(onlyDogs.personal.map(\.id))
check(!couldPlayBefore.isEmpty, "the fixture proved nothing — nothing was playable to begin with")
check(onlyDogs.availableThemes().isEmpty,
      "a theme was still offered when every photograph in it had been struck off")

print("struck off — \(struckRounds) rounds across every theme, none showed a struck photograph")

// --- Distractors that look like the answer are a hard round; ones that look nothing
// like it are a gentle one. The harness gives every photograph a "look" on a line and
// calls the gap between two looks their visual distance.
var looks: [String: Double] = [:]
func makeLookLibrary() -> [GamePhoto] {
    (0..<300).map { index in
        looks["k\(index)"] = Double(index % 30) / 30
        return GamePhoto(id: "k\(index)",
                         origin: .personal(localIdentifier: "k\(index)"),
                         creationDate: Date(timeIntervalSinceNow: -Double(index) * 40 * .day))
    }
}
func alikeShare() -> Double {
    var generator = LevelGenerator()
    generator.personal = makeLookLibrary()
    generator.visualDistance = { first, second in
        guard let a = looks[first.id], let b = looks[second.id] else { return nil }
        // Floored well above the duplicate threshold: these are different photographs
        // that merely resemble each other to different degrees. Without the floor,
        // curation reads the whole fixture as one moment shot three hundred times.
        return 0.3 + 0.6 * abs(a - b)
    }
    var alike = 0
    var rounds = 0
    for _ in 0..<200 {
        guard let level = generator.makeLevel(theme: .chronology),
              let answer = level.photos.first(where: { $0.id == level.correctPhotoID }),
              let target = looks[answer.id] else { continue }
        let gaps = level.photos
            .filter { $0.id != answer.id }
            .compactMap { looks[$0.id].map { abs($0 - target) } }
        guard !gaps.isEmpty else { continue }
        rounds += 1
        // "Alike" means the average distractor is in the nearer half of the range.
        if gaps.reduce(0, +) / Double(gaps.count) < 0.3 { alike += 1 }
    }
    return rounds == 0 ? 0 : Double(alike) / Double(rounds)
}
// Distractors are drawn from the alike end a quarter of the time now, by one fixed
// number rather than a lever. What has to hold is that it happens sometimes and is not
// the rule — a round of four near-identical photographs is a coin toss dressed up.
let alike = alikeShare()
check(alike > 0.02 && alike < 0.70,
      "look-alike distractors came out at \(Int(alike * 100))% of rounds")
print("look-alike distractors — \(Int(alike * 100))% of rounds")

// --- "Which photo is from Rome?" never shows a photograph of somebody's face.
var selfies = LevelGenerator()
let selfiePlaces: [(String, Double, Double)] = [
    ("Rome, Italy", 41.90, 12.49), ("Cork, Ireland", 51.90, -8.48),
    ("Oslo, Norway", 59.91, 10.75), ("Kyoto, Japan", 35.01, 135.77),
    ("Lisbon, Portugal", 38.72, -9.14), ("Denver, USA", 39.74, -104.99),
]
selfies.personal = (0..<300).map { index in
    let place = selfiePlaces[index % selfiePlaces.count]
    var photo = GamePhoto(id: "s\(index)",
                          origin: .personal(localIdentifier: "s\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 20 * .day),
                          coordinate: Coordinate(latitude: place.1, longitude: place.2),
                          placeName: place.0)
    // A third are selfies, a third are close-up portraits by another route, a third
    // are photographs of somewhere.
    // Stepped separately from the place, or every clean photograph lands in the same
    // two cities and the round has too few places to build from — a fixture bug that
    // reads exactly like a curation bug.
    photo.wasExamined = true
    switch (index / selfiePlaces.count) % 3 {
    case 0: photo.isSelfie = true
    case 1: photo.faceProminence = 0.4
    default: break
    }
    return photo
}
var placeRounds = 0
for _ in 0..<300 {
    guard let level = selfies.makeLevel(theme: .places) else { continue }
    placeRounds += 1
    check(level.photos.allSatisfy { !$0.hidesSurroundings },
          "a Places round showed a photograph with nothing around the face in it")
}
check(placeRounds > 0, "no Places rounds survived once close-ups were excluded")

// --- A round asks by the region when only one photograph comes from it, and falls back
// to the town when two do. "Which photo is from McLean?" asks about a town almost
// nobody can place.
var regions = LevelGenerator()
regions.examinesPhotos = false
let towns: [(String, Double, Double)] = [
    ("McLean, VA", 38.93, -77.17), ("Cork, Ireland", 51.90, -8.48),
    ("Kyoto, Japan", 35.01, 135.77), ("Lisbon, Portugal", 38.72, -9.14),
    ("Oslo, Norway", 59.91, 10.75), ("Perth, Australia", -31.95, 115.86),
]
regions.personal = (0..<240).map { index in
    let town = towns[index % towns.count]
    return GamePhoto(id: "r\(index)",
                     origin: .personal(localIdentifier: "r\(index)"),
                     creationDate: Date(timeIntervalSinceNow: -Double(index) * 20 * .day),
                     coordinate: Coordinate(latitude: town.1, longitude: town.2),
                     placeName: town.0)
}
var askedByRegion = 0
var regionRounds = 0
for _ in 0..<300 {
    guard let level = regions.makeLevel(theme: .places) else { continue }
    regionRounds += 1
    check(!level.prompt.contains(", "),
          "a Places question asked \(level.prompt.debugDescription)")
    // Every town here is in a different region, so every round should ask by region.
    if level.prompt.contains("Virginia") || level.prompt.contains("Ireland")
        || level.prompt.contains("Japan") || level.prompt.contains("Portugal")
        || level.prompt.contains("Norway") || level.prompt.contains("Australia") {
        askedByRegion += 1
    }
}
check(regionRounds > 0, "no Places rounds were built for the region check")
check(askedByRegion == regionRounds,
      "only \(askedByRegion) of \(regionRounds) rounds asked by the wider place")

// --- No round asks the player to tell one suburb from the next.
var neighbours = LevelGenerator()
neighbours.examinesPhotos = false
// Four towns in northern Virginia, then somewhere else entirely. The four are all
// within twenty miles of each other.
let northernVirginia: [(String, Double, Double)] = [
    ("McLean, VA", 38.934, -77.177), ("Fairfax, VA", 38.846, -77.306),
    ("Springfield, VA", 38.789, -77.187), ("Arlington, VA", 38.880, -77.107),
]
let elsewhere: [(String, Double, Double)] = [
    ("Chicago, IL", 41.88, -87.63), ("Denver, CO", 39.74, -104.99),
    ("Portland, OR", 45.52, -122.68), ("Austin, TX", 30.27, -97.74),
    ("Boston, MA", 42.36, -71.06),
]
let everywhere = northernVirginia + elsewhere
neighbours.personal = (0..<360).map { index in
    let place = everywhere[index % everywhere.count]
    return GamePhoto(id: "n\(index)",
                     origin: .personal(localIdentifier: "n\(index)"),
                     creationDate: Date(timeIntervalSinceNow: -Double(index) * 15 * .day),
                     coordinate: Coordinate(latitude: place.1, longitude: place.2),
                     placeName: place.0)
}
var separationRounds = 0
for _ in 0..<300 {
    guard let level = neighbours.makeLevel(theme: .places) else { continue }
    separationRounds += 1
    let spots = level.photos.compactMap(\.coordinate)
    for (index, spot) in spots.enumerated() {
        for other in spots.dropFirst(index + 1) {
            check(spot.distance(to: other) >= PlacesCurator.minimumSeparation,
                  "a round put two places \(Int(spot.distance(to: other) / 1000))km apart")
        }
    }
}
check(separationRounds > 0, "no Places rounds survived the separation floor")

// --- A round of one occasion asks about the occasion.
var occasions = LevelGenerator()
occasions.examinesPhotos = false
let occasionKinds = [("birthday", "Birthdays", "Which birthday came first?"),
                     ("beach", "By the sea", "Which day by the sea came first?"),
                     ("snow", "Snow", "Which snowy day came first?")]
occasions.personal = (0..<300).map { index in
    let kind = occasionKinds[index % occasionKinds.count]
    var photo = GamePhoto(id: "o\(index)",
                          origin: .personal(localIdentifier: "o\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 30 * .day))
    photo.themeID = kind.0
    photo.themeTitle = kind.1
    photo.themeQuestion = kind.2
    return photo
}
var occasionRounds = 0
var namedTheOccasion = 0
for _ in 0..<300 {
    guard let level = occasions.makeLevel(theme: .chronology) else { continue }
    occasionRounds += 1
    let kinds = Set(level.photos.compactMap(\.themeID))
    if kinds.count == 1 {
        namedTheOccasion += 1
        check(level.prompt == level.photos.first?.themeQuestion,
              "a round of one occasion asked \(level.prompt.debugDescription)")
    } else {
        check(level.prompt == "Which photo is older?",
              "a mixed round asked \(level.prompt.debugDescription)")
    }
}
check(occasionRounds > 0, "no rounds were built from the occasion library")
check(Double(namedTheOccasion) / Double(max(occasionRounds, 1)) > 0.8,
      "only \(namedTheOccasion) of \(occasionRounds) rounds came out as one occasion")

// --- The second opinion throws out rounds the classifier got wrong.
//
// The library here is deliberately mislabelled, the way a real classifier mislabels:
// some photographs carry a tag for something they do not show, and some show a thing
// they carry no tag for. A round may only go out when the photograph being asked about
// looks more like the thing than every other photograph in it.
var truth: [String: Set<String>] = [:]      // what is really in each photograph
var opinions = LevelGenerator()
opinions.examinesPhotos = false
let asked = ["dog", "cake", "food", "flower"]
opinions.personal = (0..<400).map { index in
    let real = asked[index % asked.count]
    let tagged = index % 11 == 0 ? asked[(index + 1) % asked.count] : real  // a false yes
    truth["c\(index)"] = [real]
    var photo = GamePhoto(id: "c\(index)",
                          origin: .personal(localIdentifier: "c\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 9 * .day),
                          objectTags: [tagged],
                          // A tenth of them hide what they contain, the way a classifier
                          // that missed the food beside the cat did.
                          possibleObjectTags: index % 10 == 0 ? [tagged] : [tagged, real])
    photo.wasExamined = true
    return photo
}
opinions.bestConcept = { photo in truth[photo.id]?.first }
opinions.conceptScore = { photo, concept in
    // The stand-in for CLIP: it knows the truth, as a second model roughly does.
    // On the real scale: the themes model calls a concept present at 0.040.
    (truth[photo.id]?.contains(concept) ?? false) ? 0.090 : 0.012
}
var checkedRounds = 0
for _ in 0..<400 {
    guard let level = opinions.makeLevel(theme: .objects),
          let focus = level.focusTag else { continue }
    checkedRounds += 1
    let holders = level.photos.filter { truth[$0.id]?.contains(focus) ?? false }
    check(holders.count == 1,
          "a Things round asked about \(focus) with \(holders.count) photographs of it")
    check(holders.first?.id == level.correctPhotoID,
          "a Things round marked the wrong photograph as the one with the \(focus)")
}
check(checkedRounds > 0, "no Things rounds survived the second opinion")

// --- A photograph taken abroad is asked about by its country, not its town.
var abroad = LevelGenerator()
abroad.examinesPhotos = false
let foreign: [(String, String, String, Double, Double)] = [
    ("Vík, Iceland", "Iceland", "IS", 63.42, -19.01),
    ("Kyoto, Japan", "Japan", "JP", 35.01, 135.77),
    ("Cork, Ireland", "Ireland", "IE", 51.90, -8.48),
    ("Perth, Australia", "Australia", "AU", -31.95, 115.86),
    ("Lisbon, Portugal", "Portugal", "PT", 38.72, -9.14),
    ("Oslo, Norway", "Norway", "NO", 59.91, 10.75),
]
abroad.personal = (0..<240).map { index in
    let place = foreign[index % foreign.count]
    var photo = GamePhoto(id: "a\(index)",
                          origin: .personal(localIdentifier: "a\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 25 * .day),
                          coordinate: Coordinate(latitude: place.3, longitude: place.4),
                          placeName: place.0)
    photo.countryName = place.1
    photo.countryCode = place.2
    return photo
}
var abroadRounds = 0
var askedByCountry = 0
for _ in 0..<300 {
    guard let level = abroad.makeLevel(theme: .places) else { continue }
    abroadRounds += 1
    let countries = level.photos.compactMap(\.countryCode)
    check(Set(countries).count == countries.count,
          "a round abroad used two photographs from one country")
    if foreign.contains(where: { level.prompt == "Which photo is from \($0.1)?" }) {
        askedByCountry += 1
    }
}
check(abroadRounds > 0, "no rounds were built from the library taken abroad")
check(askedByCountry == abroadRounds,
      "only \(askedByCountry) of \(abroadRounds) rounds abroad asked by country")

// --- No two photographs in a round come from the same afternoon.
//
// A graduation is fifty photographs of one day. All fifty are years away from a
// photograph taken in another decade, and no distance at all from each other, so a
// gap measured only from the answer lets three of them into one round.
var oneDay = LevelGenerator()
oneDay.examinesPhotos = false
oneDay.personal = (0..<400).map { index in
    // Twenty occasions, twenty photographs each, an hour apart within the day.
    let occasion = index / 20
    let withinDay = Double(index % 20) * 3600
    var photo = GamePhoto(id: "g\(index)",
                          origin: .personal(localIdentifier: "g\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(occasion) * 200 * .day
                                             - withinDay))
    photo.themeID = "graduation"
    photo.themeTitle = "Graduations"
    photo.themeQuestion = "Which graduation came first?"
    photo.wasExamined = true
    return photo
}
var oneDayRounds = 0
for _ in 0..<300 {
    guard let level = oneDay.makeLevel(theme: .chronology) else { continue }
    oneDayRounds += 1
    let days = level.photos.compactMap(\.creationDate).map {
        Int($0.timeIntervalSince1970 / (24 * 3600))
    }
    check(Set(days).count == days.count,
          "a round showed \(days.count - Set(days).count + 1) photographs from one day")
}
check(oneDayRounds > 0, "no rounds survived the one-photograph-per-occasion rule")

// --- A cat tagged as a dog never becomes the answer to "which one has a dog".
var confusion = LevelGenerator()
confusion.examinesPhotos = false
var reality: [String: String] = [:]
confusion.personal = (0..<320).map { index in
    let real = ["cat", "dog", "horse", "bird"][index % 4]
    // Every fifth photograph is tagged as the animal next door.
    let tagged = index % 5 == 0 ? ["dog", "cat", "bird", "horse"][index % 4] : real
    reality["m\(index)"] = real
    var photo = GamePhoto(id: "m\(index)",
                          origin: .personal(localIdentifier: "m\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 11 * .day),
                          objectTags: [tagged],
                          possibleObjectTags: [tagged])
    photo.wasExamined = true
    return photo
}
confusion.bestConcept = { reality[$0.id] }
// Graded, the way CLIP actually scores: a cat looks a fair bit like "a photo of a dog"
// — more like it than a bird does — so the margin rule alone lets a cat through when
// the other photographs in the round are a bird and a horse. Only the agreement rule
// catches that, and this fixture is built so it has to.
let nearness: [String: [String: Double]] = [
    // A cat looks a little like a dog and nothing like a bird — but "a little like" still
    // has to sit below the level at which the thing counts as present (0.040), because a
    // cat is not a dog however much it rhymes with one.
    "cat":   ["cat": 0.090, "dog": 0.030, "horse": 0.014, "bird": 0.012],
    "dog":   ["dog": 0.090, "cat": 0.030, "horse": 0.015, "bird": 0.012],
    "horse": ["horse": 0.090, "dog": 0.015, "cat": 0.014, "bird": 0.012],
    "bird":  ["bird": 0.090, "cat": 0.012, "dog": 0.012, "horse": 0.012],
]
confusion.conceptScore = { photo, concept in
    guard let real = reality[photo.id] else { return nil }
    return nearness[real]?[concept] ?? 0.15
}
var confusionRounds = 0
for _ in 0..<300 {
    guard let level = confusion.makeLevel(theme: .objects),
          let focus = level.focusTag else { continue }
    confusionRounds += 1
    check(reality[level.correctPhotoID] == focus,
          "a round asked for a \(focus) and marked a \(reality[level.correctPhotoID] ?? "?")")
}
check(confusionRounds > 0, "no Things rounds survived the agreement rule")

// --- The question comes from the themes model, not from the classifier's tags.
//
// Every photograph here is tagged as the wrong thing. If questions were still built
// from tags, every round would ask about something that is not in the photograph.
var reading = LevelGenerator()
reading.examinesPhotos = false
var whatItIs: [String: String] = [:]
reading.personal = (0..<320).map { index in
    let real = ["dog", "cake", "flower", "boat"][index % 4]
    let mistaken = ["cat", "food", "tree", "car"][index % 4]
    whatItIs["t\(index)"] = real
    var photo = GamePhoto(id: "t\(index)",
                          origin: .personal(localIdentifier: "t\(index)"),
                          creationDate: Date(timeIntervalSinceNow: -Double(index) * 13 * .day),
                          objectTags: [mistaken],
                          possibleObjectTags: [mistaken])
    photo.conceptID = real
    photo.conceptScore = 0.30
    photo.wasExamined = true
    return photo
}
reading.bestConcept = { whatItIs[$0.id] }
reading.conceptScore = { photo, concept in whatItIs[photo.id] == concept ? 0.090 : 0.011 }
var readingRounds = 0
for _ in 0..<300 {
    guard let level = reading.makeLevel(theme: .objects),
          let focus = level.focusTag else { continue }
    readingRounds += 1
    check(whatItIs[level.correctPhotoID] == focus,
          "the answer to a \(focus) round was a \(whatItIs[level.correctPhotoID] ?? "?")")
    let alsoHolding = level.photos.filter { $0.id != level.correctPhotoID }
        .filter { whatItIs[$0.id] == focus }
    check(alsoHolding.isEmpty,
          "a \(focus) round had \(alsoHolding.count) other photographs of one")
}
check(readingRounds > 0, "no rounds were built from the themes model's reading")

print("theme rotation over 30k picks — " + allThemes.map { "\($0.title) \(Int(Double(picked[$0] ?? 0) / 300))%" }.joined(separator: ", ") + ", repeats \(Int(repeatShare * 100))%")
print("subject-aware prompts — \(namedTheSubject) of \(subjectLevels) pack-only levels named their subject")
print("things subjects — \(thingsLevels) rounds, no subject asked twice running")
print("daily rotation — \(slice.count) of \(catalogue.count) in play each day, all seen within 30 days")
print("repeats inside the last forty photographs — \(repeatsWithinTen) of \(comparisons)")
print("pack-only chronology gap — smallest \(Int((packGaps.min() ?? 0) / .year))y over \(packGaps.count) levels (floor is 50y)")
print("questions from the reading — \(readingRounds) rounds, tags all wrong, answers all right")
print("two models agreeing — \(confusionRounds) rounds, none asked for the wrong animal")
print("second opinion — \(checkedRounds) Things rounds, each with exactly one true answer")
print("one day, one photograph — \(oneDayRounds) rounds, none repeated a day")
print("occasions — \(namedTheOccasion) of \(occasionRounds) personal rounds were one occasion, named")
print("abroad — \(askedByCountry) of \(abroadRounds) rounds asked by country")
print("places kept apart — \(separationRounds) rounds, none closer than \(Int(PlacesCurator.minimumSeparation / 1000))km")
print("places asked by region — \(askedByRegion) of \(regionRounds) rounds")
print("places without close-ups — \(placeRounds) rounds, none showed a selfie")
print("duplicate moments — \(roundsWithARepeat) of \(duplicateRounds) rounds offered one twice")
print("documents — \(documentRounds) rounds built, none showed one")
print("personal rounds of one kind — \(Int(coherentShare * 100))% all faces or all scenery")
print("personal spacing — five-year library \(ChronologyCurator.describe(fiveYears)), twenty-year \(ChronologyCurator.describe(twentyYears))")
print("objects same-family distractors — \(Int(familyShare * 100))% of distractors")
// MARK: - A reworded question may not invent anything, or point at one photograph
//
// Every line here is a rewording that reached a real round. The model is allowed to say
// the same question differently; it is not allowed to add a fact, and it is not allowed
// to turn a comparison of four photographs into a reference to one of them.

let walk = Level(theme: .chronology, prompt: "Which walk came first?",
                 photos: [], correctPhotoID: "", curationNote: "")
let dog = Level(theme: .objects, prompt: "Which photo has a dog in it?",
                photos: [], correctPhotoID: "", curationNote: "")

let older = Level(theme: .chronology, prompt: "Which photo is older?",
                  photos: [], correctPhotoID: "", curationNote: "")

let mustBeRejected: [(String, Level, String)] = [
    ("Which image shows earlier time?", older,
     "not a sentence anybody says — seen in a real round"),
    ("Which shows earlier?", older, "stopped saying which photo"),
    ("Which came before the quiet walk?", walk,
     "invented “quiet” and made the player find one photograph first — seen in a real round"),
    ("Which came before the walk?", walk,
     "points at one photograph, even without inventing a word"),
    ("Which of these lovely walks came first?", walk,
     "“lovely” is a fact about the photographs that nobody checked"),
    ("Which walk came first, the muddy one?", walk,
     "same again, wearing a comma"),
    ("Which photo has a friendly dog in it?", dog,
     "“friendly” is not something curation established"),
]
for (candidate, level, why) in mustBeRejected {
    check(QuestionGuardrail.reject(candidate, rewordingOf: level.prompt, in: level) != nil,
          "a rewording was allowed through — \(why): “\(candidate)”")
}

let mustBeKept: [(String, Level)] = [
    ("Which one is older?", older),
    ("Which photo was taken first?", older),
    ("Which of these photos is the oldest?", older),
    ("Which of these walks happened first?", walk),
    ("Which walk do you think came first?", walk),
    ("Which walk was taken first?", walk),
    ("Which photo shows a dog?", dog),
    ("Which of these photos has a dog in it?", dog),
]
for (candidate, level) in mustBeKept {
    let verdict = QuestionGuardrail.reject(candidate, rewordingOf: level.prompt, in: level)
    check(verdict == nil,
          "a fair rewording was thrown away (\(verdict ?? "")): “\(candidate)”")
}
print("question rewording — \(mustBeRejected.count) inventions refused, "
    + "\(mustBeKept.count) fair rewordings kept")

// MARK: - The round audit can only ever take a round away
//
// The audit hands a finished round to Apple's on-device model and drops it if the model
// can't answer it. That is a good trade exactly as long as it stays one-directional: it
// must never be able to keep a round curation rejected, and — more easily got wrong — a
// device where the model is missing, busy, or slow must play the same game as one where
// it answered. Every no-verdict outcome therefore has to keep the round.

for personal in [true, false] {
    check(!RoundAuditRules.judges(theme: .chronology, usesPersonalPhotos: personal),
          "the audit ruled on Chronology, where the date in the file is the answer")
    check(RoundAuditRules.judges(theme: .objects, usesPersonalPhotos: personal),
          "the audit skipped Things, where what is in the photograph is visible to anyone")
}
check(!RoundAuditRules.judges(theme: .places, usesPersonalPhotos: true),
      "the audit ruled on someone's own Places round — nothing in a back garden says Virginia, "
    + "so it would delete the theme for anyone playing with their own photographs")
check(RoundAuditRules.judges(theme: .places, usesPersonalPhotos: false),
      "the audit skipped a pack Places round, where the landmark is right there in the frame")
let auditedThemes: [GameTheme] = GameTheme.allCases.filter {
    RoundAuditRules.judges(theme: $0, usesPersonalPhotos: false)
}

let silences: [RoundAuditRules.Outcome] = [
    .unjudged("no answer in time"),
    .unjudged("Apple Intelligence is switched off"),
    .unjudged("a photograph couldn't be fetched"),
    .unjudged("the model refused"),
]
for silence in silences {
    check(silence.keepsRound,
          "a round was dropped for a non-answer (\(silence)) — a quiet model must not mean a worse game")
}
check(RoundAuditRules.Outcome.agreed.keepsRound, "an agreed round was dropped")
check(!RoundAuditRules.Outcome.chose("photo 3").keepsRound,
      "a round survived the model naming a different photograph")
check(!RoundAuditRules.Outcome.arguable.keepsRound,
      "a round survived the model calling it arguable")

let offered = ["photo 1", "photo 2", "photo 3", "photo 4"]
check(RoundAuditRules.labelSaid("photo 2", amongst: offered) == "photo 2",
      "a plain label wasn't recognised")
check(RoundAuditRules.labelSaid("[photo 2]", amongst: offered) == "photo 2",
      "a label in brackets wasn't recognised — the model writes them that way")
check(RoundAuditRules.labelSaid("\"Photo 2\".", amongst: offered) == "photo 2",
      "a quoted, capitalised, full-stopped label wasn't recognised")
check(RoundAuditRules.labelSaid("#/$defs/ImageReference", amongst: offered) == nil,
      "the model quoting its own schema was read as naming a photograph")
check(RoundAuditRules.labelSaid("photo 9", amongst: offered) == nil,
      "a photograph that wasn't in the round was read as an answer")
check(RoundAuditRules.Outcome.unjudged("answered with “#/$defs/ImageReference”").keepsRound,
      "a round was thrown away over punctuation")

print("round audit — judges \(auditedThemes.map(\.rawValue).sorted().joined(separator: " and ")); "
    + "\(silences.count) kinds of silence all keep the round")

// MARK: - The packs that actually ship (spec §3)
//
// Everything above plays against libraries invented to be awkward. This plays against the
// photographs that will be on somebody's iPad, read off the same files the app bundles.
// A pack is content rather than code, and content is exactly what nobody re-checks after
// the first time it is built.

let repoRoot = FileManager.default.currentDirectoryPath + "/../.."
let shippedPacks = loadPacks(from: repoRoot)
check(!shippedPacks.isEmpty, "no packs could be read from TimeRolls/Packs")

var packSummary: [String] = []
for pack in shippedPacks {
    let items = pack.items
    check(!items.isEmpty, "\(pack.id) ships with no photographs in it")

    // Every photograph has to be attributable. Licensing is still an open decision, and
    // an unattributed photograph is the one that makes it a problem rather than a choice.
    for field in ["license", "credit", "sourceURL"] {
        let missing = items.filter { ($0[field] as? String)?.isEmpty ?? true }
        check(missing.isEmpty,
              "\(pack.id): \(missing.count) photographs have no \(field)")
    }

    // The same photograph twice is a round that can offer the answer as its own distractor.
    let ids = items.compactMap { $0["id"] as? String }
    check(Set(ids).count == ids.count, "\(pack.id) has repeated ids")
    let urls = items.compactMap { $0["remoteURL"] as? String }
    check(Set(urls).count == urls.count,
          "\(pack.id) points at the same picture more than once")

    // What the pack says it can carry, it has to be able to carry.
    var generator = LevelGenerator()
    generator.pack = photos(from: pack)
    generator.packThemeSupport = [pack.id: Set(pack.themes.compactMap(GameTheme.init))]

    // A named round stays inside its own pack where it can, and asks in the pack's own
    // words. "Which one shows the Mona Lisa?" beside a lion is a fair question and a
    // strange one; four paintings is a round about paintings.
    for name in pack.themes {
        guard let theme = GameTheme(rawValue: name) else {
            check(false, "\(pack.id) claims a theme called \(name), which does not exist")
            continue
        }
        var built = 0
        for _ in 0..<120 {
            guard let level = generator.makeLevel(theme: theme) else { continue }
            built += 1
            // The invariants that matter whatever the library: one answer, no repeats.
            let ids = level.photos.map(\.id)
            check(Set(ids).count == ids.count,
                  "\(pack.id) \(name): a round showed the same photograph twice")
            check(level.photos.contains { $0.id == level.correctPhotoID },
                  "\(pack.id) \(name): the answer was not among the photographs")
            check(!level.prompt.isEmpty, "\(pack.id) \(name): a round had no question")
            // A round built from a pack that names its photographs shows that pack.
            if theme == .objects, level.photos.allSatisfy({ $0.title != nil }),
               generator.pack.count(where: { $0.packID == pack.id }) >= 4 {
                let packs = Set(level.photos.compactMap(\.packID))
                check(packs.count == 1,
                      "\(pack.id): a named round mixed \(packs.sorted().joined(separator: " and "))")
            }
            // Named rounds may not put two creatures nobody could tell apart together.
            let names = level.photos.compactMap { $0.title?.lowercased() }
            for (index, one) in names.enumerated() {
                for other in names.dropFirst(index + 1) {
                    check(ObjectCatalog.canStandTogether(one, other),
                          "\(pack.id): a round held both \u{201C}\(one)\u{201D} and "
                        + "\u{201C}\(other)\u{201D}")
                }
            }
        }
        check(built > 0,
              "\(pack.id) says it carries \(name) but no \(name) round could be built from it")
        packSummary.append("\(pack.id)/\(name): \(built)")
    }
}
print("shipped packs — \(shippedPacks.count) read from disk · "
    + packSummary.joined(separator: " · "))

if failures.isEmpty {
    print("✅ all curation invariants held over \(11 * 3 * 120 * 3) generated levels")
} else {
    print("❌ \(failures.count) failures:")
    for failure in Set(failures).sorted() { print("  - \(failure)") }
    exit(1)
}
