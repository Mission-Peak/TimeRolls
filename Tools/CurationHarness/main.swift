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
        return GamePhoto(
            id: "p\(index)",
            origin: .personal(localIdentifier: "p\(index)"),
            creationDate: Date(timeIntervalSinceNow: -secondsAgo),
            coordinate: place.map { Coordinate(latitude: $0.1, longitude: $0.2) },
            placeName: place?.0,
            objectTags: confident,
            possibleObjectTags: possible)
    }
}

var failures: [String] = []
func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

let library = makeLibrary()
var generator = LevelGenerator()
generator.personal = library
generator.pack = PublicPackLibrary.photos(enabledPackIDs: PublicPackLibrary.defaultEnabledPackIDs)

// --- Invariants across the whole difficulty range, both themes.
var gapsByDifficulty: [Double: [TimeInterval]] = [:]
var sameFamilyShare: [Double: (same: Int, total: Int)] = [:]

for step in 0...10 {
    let level = Double(step) / 10
    for count in 3...5 {
        let knob = DifficultyKnob(level: level, photoCount: count)
        for _ in 0..<40 {
            guard let chrono = generator.makeLevel(theme: .chronology, knob: knob) else {
                failures.append("chronology returned nil at level \(level) count \(count)")
                continue
            }
            check((3...5).contains(chrono.photos.count), "photo count \(chrono.photos.count)")
            check(Set(chrono.photos.map(\.id)).count == chrono.photos.count, "duplicate photo in level")
            let sorted = chrono.photos.sorted { $0.creationDate! < $1.creationDate! }
            check(sorted.first!.id == chrono.correctPhotoID,
                  "correct answer is not the oldest photo")
            let gap = sorted[1].creationDate!.timeIntervalSince(sorted[0].creationDate!)
            check(gap >= 30 * .day,
                  "answer is only \(Int(gap / .day))d older than the runner-up at difficulty \(level)")
            gapsByDifficulty[level, default: []].append(gap)

            guard let places = generator.makeLevel(theme: .places, knob: knob) else {
                failures.append("places returned nil at level \(level) count \(count)")
                continue
            }
            check((3...5).contains(places.photos.count), "places photo count")
            let target = places.photos.first { $0.id == places.correctPhotoID }
            check(target != nil, "places level has no correct photo in its set")
            if let targetName = target?.placeName {
                let matching = places.photos.filter { $0.placeName == targetName }
                check(matching.count == 1,
                      "places level has \(matching.count) photos from the target place — ambiguous")
                check(places.prompt.contains(PlacesCurator.shortName(targetName)),
                      "prompt does not name the target place")
            }
            check(places.photos.allSatisfy { $0.placeName != nil }, "places level has an unnamed photo")

            guard let objects = generator.makeLevel(theme: .objects, knob: knob) else {
                failures.append("objects returned nil at level \(level) count \(count)")
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
            }
            let distractors = objects.photos.filter { $0.id != objects.correctPhotoID }
            let same = distractors.filter { photo in
                photo.objectTags.contains { ObjectCatalog.category(id: $0)?.family == category.family }
            }.count
            sameFamilyShare[level, default: (0, 0)].same += same
            sameFamilyShare[level, default: (0, 0)].total += distractors.count
        }
    }
}

// --- The time-delta lever should actually tighten as difficulty rises.
let easy = gapsByDifficulty[0.0]!.reduce(0, +) / Double(gapsByDifficulty[0.0]!.count)
let mid = gapsByDifficulty[0.5]!.reduce(0, +) / Double(gapsByDifficulty[0.5]!.count)
let hard = gapsByDifficulty[1.0]!.reduce(0, +) / Double(gapsByDifficulty[1.0]!.count)
check(easy > mid && mid > hard,
      "difficulty knob is not monotonic: easy \(Int(easy / .year))y, mid \(Int(mid / .year))y, hard \(Int(hard / .year))y")

// --- Harder levels should reach for same-family distractors (a cat against a dog).
func share(_ level: Double) -> Double {
    let entry = sameFamilyShare[level]!
    return Double(entry.same) / Double(entry.total)
}
check(share(1.0) > share(0.0) * 2,
      "objects difficulty does not bite: same-family distractors are "
        + "\(Int(share(0.0) * 100))% at the gentlest and \(Int(share(1.0) * 100))% at the hardest")

// --- Objects must decline when the classifier has found nothing.
var untagged = LevelGenerator()
untagged.personal = makeLibrary().map {
    var copy = $0
    copy.objectTags = []
    copy.possibleObjectTags = []
    return copy
}
check(untagged.makeLevel(theme: .objects, knob: .standard) == nil,
      "Objects should decline when no photo has a recognised subject")

// --- And it must stay off entirely when the caregiver switches it off.
var objectsOff = LevelGenerator()
objectsOff.personal = library
objectsOff.pack = PublicPackLibrary.photos(enabledPackIDs: PublicPackLibrary.defaultEnabledPackIDs)
objectsOff.allowObjects = false
check(objectsOff.makeLevel(theme: .objects, knob: .standard) == nil,
      "Objects should build nothing when switched off")
check(!objectsOff.availableThemes(knob: .standard).contains(.objects),
      "Objects should not be offered when switched off")

// --- Pack art alone can carry the theme (its subjects are hand-written, not classified).
var packOnly = LevelGenerator()
packOnly.pack = PublicPackLibrary.photos(enabledPackIDs: PublicPackLibrary.defaultEnabledPackIDs)
check(packOnly.makeLevel(theme: .objects, knob: .standard) != nil,
      "the bundled packs should be able to carry an Objects level on their own")

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
check(sparse.makeLevel(theme: .chronology, knob: .standard) != nil,
      "a three-photo library should still make a Chronology level")
check(sparse.makeLevel(theme: .places, knob: .standard) == nil,
      "Places should decline rather than fake a level with no geotags")

// --- GPS-poor library must degrade into the packs, not error.
var gpsPoor = LevelGenerator()
gpsPoor.personal = sparse.personal
gpsPoor.pack = PublicPackLibrary.photos(enabledPackIDs: PublicPackLibrary.defaultEnabledPackIDs)
check(gpsPoor.makeLevel(theme: .places, knob: .standard) != nil,
      "Places should fall back to pack photos when the library has no geotags")
check(gpsPoor.availableThemes(knob: .standard).count == 3,
      "all three themes should be playable once packs are on")

// --- No packs, no photos at all.
let empty = LevelGenerator()
check(empty.availableThemes(knob: .standard).isEmpty, "an empty library should offer no themes")

print("theme rotation over 30k picks — " + allThemes.map { "\($0.title) \(Int(Double(picked[$0] ?? 0) / 300))%" }.joined(separator: ", ") + ", repeats \(Int(repeatShare * 100))%")
print("chronology mean gap to runner-up — gentlest: \(Int(easy / .year))y, middle: \(Int(mid / .year))y, hardest: \(ChronologyCurator.describe(hard))")
print("objects same-family distractors — gentlest: \(Int(share(0.0) * 100))%, middle: \(Int(share(0.5) * 100))%, hardest: \(Int(share(1.0) * 100))%")
if failures.isEmpty {
    print("✅ all curation invariants held over \(11 * 3 * 40 * 3) generated levels")
} else {
    print("❌ \(failures.count) failures:")
    for failure in Set(failures).sorted() { print("  - \(failure)") }
    exit(1)
}
