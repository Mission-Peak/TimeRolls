//
//  GameModel.swift
//  Photo Chronology
//
//  Core value types for the game loop. See PhotoChronology_Prototype_Spec_v1 §3–§5.
//

import Foundation
import CoreLocation

// MARK: - Themes

/// Chronology and Places need PhotoKit metadata only; Objects adds on-device Vision
/// classification (spec §4, §6.3).
enum GameTheme: String, CaseIterable, Identifiable, Codable {
    case chronology
    case places
    case objects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chronology: "Time"
        case .places: "Places"
        case .objects: "Things"
        }
    }

    var symbolName: String {
        switch self {
        case .chronology: "clock"
        case .places: "map"
        case .objects: "tag"
        }
    }

    /// True for themes that need to look at the photo itself rather than its metadata.
    var readsPhotoContent: Bool { self == .objects }
}

// MARK: - Photos

/// A coordinate we can hash, compare and cache without dragging CLLocation around.
struct Coordinate: Hashable, Codable {
    var latitude: Double
    var longitude: Double

    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// Grid cell used as the cache key for reverse geocoding, ~11km on a side.
    var clusterKey: String {
        String(format: "%.1f,%.1f", latitude, longitude)
    }

    func distance(to other: Coordinate) -> CLLocationDistance {
        clLocation.distance(from: other.clLocation)
    }
}

/// One playable photo, from either the player's library or a public pack.
/// Personal photos are referenced by identifier only — no pixels are held here.
struct GamePhoto: Identifiable, Hashable {
    enum Origin: Hashable {
        case personal(localIdentifier: String)
        case pack(packID: String, itemID: String)

        var isPersonal: Bool {
            if case .personal = self { return true }
            return false
        }
    }

    var id: String
    var origin: Origin
    var creationDate: Date?
    var coordinate: Coordinate?
    /// Plain caregiver-supplied context ("Mom's 80th"). Local only, never a person-ID.
    var caregiverLabel: String?
    /// Filled in by `PlaceResolver` for Places levels.
    var placeName: String?
    /// Allow-listed categories the on-device classifier is confident about (spec §6.3).
    var objectTags: Set<String> = []
    /// Categories it saw any hint of — used only to rule this photo out as a distractor.
    var possibleObjectTags: Set<String> = []

    var isPersonal: Bool { origin.isPersonal }
}

// MARK: - Levels

/// One level: a theme, a curated photo set, one question, one right answer (spec §3.1).
struct Level: Identifiable {
    let id = UUID()
    var theme: GameTheme
    var prompt: String
    var photos: [GamePhoto]
    var correctPhotoID: String
    /// The difficulty this level was generated at, 0 (gentlest) … 1 (hardest).
    var difficulty: Double
    /// Human-readable note on why this set is this hard. Surfaced only in caregiver diagnostics.
    var curationNote: String
    /// Objects only: the category the question asked about, so the answer's reveal
    /// caption names *that* rather than whatever else is in the photo.
    var focusTag: String?

    var usesPackPhotos: Bool { photos.contains { !$0.isPersonal } }

    func caption(for photo: GamePhoto) -> String {
        switch theme {
        case .chronology:
            guard let date = photo.creationDate else { return photo.caregiverLabel ?? "" }
            return Level.captionFormatter.string(from: date)
        case .places:
            return photo.placeName ?? photo.caregiverLabel ?? ""
        case .objects:
            // On reveal, name what was found in each photo — including the near misses.
            if photo.id == correctPhotoID,
               let focusTag,
               let asked = ObjectCatalog.category(id: focusTag) {
                return asked.displayName.capitalized
            }
            return ObjectCatalog.displayName(forFirstOf: photo.objectTags)?.capitalized ?? ""
        }
    }

    private static let captionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}

// MARK: - Theme rotation

/// Which theme to play next. Pure and injectable so its distribution can be checked
/// rather than eyeballed: mostly alternate, occasionally repeat, never starve a theme.
enum ThemeRotation {

    static let alternateChance = 0.7

    static func next(from available: [GameTheme],
                     last: GameTheme?,
                     roll: () -> Double = { Double.random(in: 0...1) },
                     pick: ([GameTheme]) -> GameTheme? = { $0.randomElement() }) -> GameTheme? {
        guard !available.isEmpty else { return nil }
        guard available.count > 1 else { return available[0] }
        if let last, roll() < alternateChance {
            let others = available.filter { $0 != last }
            return pick(others) ?? pick(available)
        }
        return pick(available)
    }
}

// MARK: - Difficulty

/// The tunable curation knob (spec §5.1: "a difficulty knob, not a fixed constant").
struct DifficultyKnob {
    /// 0 = gentlest, 1 = hardest.
    var level: Double = 0.25
    var photoCount: Int = 4

    static let gentle = DifficultyKnob(level: 0.0, photoCount: 3)
    static let standard = DifficultyKnob(level: 0.25, photoCount: 4)
    static let challenging = DifficultyKnob(level: 0.55, photoCount: 5)

    /// How close together the curated photos should sit in time.
    /// Gentlest is a ~20 year spread (trivial); hardest closes to ~9 months (a real task).
    var chronologyTargetGap: TimeInterval {
        let easiest: TimeInterval = 20 * .year
        let hardest: TimeInterval = 0.75 * .year
        return easiest * pow(hardest / easiest, level.clamped(to: 0...1))
    }

    /// The oldest photo has to be *clearly* the oldest — errorless design means
    /// the right answer is never a coin flip (spec §2).
    var chronologyDecisiveGap: TimeInterval {
        max(45 * .day, chronologyTargetGap * 0.3)
    }

    /// How often an Objects level draws its distractors from the same family as the
    /// answer — a cat and a horse against a dog, rather than a bridge. Ramps smoothly
    /// rather than flipping at a threshold.
    var objectsSameFamilyChance: Double { level }

    /// Above this, Places distractors are drawn from nearby towns rather than far-flung ones.
    var placesNeighbourRadius: CLLocationDistance {
        let easiest: CLLocationDistance = 3_000_000
        let hardest: CLLocationDistance = 60_000
        return easiest * pow(hardest / easiest, level.clamped(to: 0...1))
    }

    /// Silent adaptation (spec §2: timing may be captured, never shown).
    mutating func adapt(wasCorrect: Bool, attempts: Int) {
        if wasCorrect && attempts == 1 {
            level = (level + 0.08).clamped(to: 0...1)
        } else if !wasCorrect || attempts > 2 {
            level = (level - 0.12).clamped(to: 0...1)
        }
    }

    /// Only consulted when the caregiver has left adaptive timing on.
    mutating func adaptToPace(seconds: TimeInterval) {
        if seconds < 4 {
            level = (level + 0.04).clamped(to: 0...1)
        } else if seconds > 25 {
            level = (level - 0.06).clamped(to: 0...1)
        }
    }
}

// MARK: - Small helpers

extension TimeInterval {
    static let day: TimeInterval = 86_400
    static let year: TimeInterval = 365.25 * 86_400
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
