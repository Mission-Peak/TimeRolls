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
        return GamePhoto(
            id: "p\(index)",
            origin: .personal(localIdentifier: "p\(index)"),
            creationDate: Date(timeIntervalSinceNow: -secondsAgo),
            coordinate: place.map { Coordinate(latitude: $0.1, longitude: $0.2) },
            placeName: place?.0)
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
        }
    }
}

// --- The time-delta lever should actually tighten as difficulty rises.
let easy = gapsByDifficulty[0.0]!.reduce(0, +) / Double(gapsByDifficulty[0.0]!.count)
let mid = gapsByDifficulty[0.5]!.reduce(0, +) / Double(gapsByDifficulty[0.5]!.count)
let hard = gapsByDifficulty[1.0]!.reduce(0, +) / Double(gapsByDifficulty[1.0]!.count)
check(easy > mid && mid > hard,
      "difficulty knob is not monotonic: easy \(Int(easy / .year))y, mid \(Int(mid / .year))y, hard \(Int(hard / .year))y")

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
check(gpsPoor.availableThemes(knob: .standard).count == 2,
      "both themes should be playable once packs are on")

// --- No packs, no photos at all.
let empty = LevelGenerator()
check(empty.availableThemes(knob: .standard).isEmpty, "an empty library should offer no themes")

print("mean gap to runner-up — gentlest: \(Int(easy / .year))y, middle: \(Int(mid / .year))y, hardest: \(ChronologyCurator.describe(hard))")
if failures.isEmpty {
    print("✅ all curation invariants held over \(11 * 3 * 40 * 2) generated levels")
} else {
    print("❌ \(failures.count) failures:")
    for failure in Set(failures).sorted() { print("  - \(failure)") }
    exit(1)
}
