//
//  ObjectCatalog.swift
//  Photo Chronology
//
//  The curated category allow-list for the Objects theme (spec §6.3): broad categories
//  the built-in Vision classifier handles well — dog, cake, tree, beach, book — never
//  open-ended object detection, and never the narrow labels it gets wrong.
//
//  Every identifier below is a real entry in Vision's 1,303-label taxonomy. That
//  taxonomy is hierarchical and classification returns ancestors too, so matching a
//  broad parent ("dog", "cake") also catches every breed and variety underneath it.
//
//  Which categories are reliable enough to ship, and how many make a good level pool,
//  is an open decision (spec §12). Caregiver setup → Diagnostics → Things coverage
//  reports how each category actually performs on a real library; prune from there.
//

import Foundation

nonisolated struct ObjectCategory: Identifiable, Hashable {

    /// Levels get harder when the distractors come from the same family as the answer.
    enum Family: String, Hashable {
        case animal, food, nature, vehicle, madeThing
    }

    /// Stable key. Stored in the tag cache, so don't rename without bumping the version.
    var id: String
    var displayName: String
    /// nil for mass nouns — "snow in it?" rather than "a snow in it?"
    var article: String?
    var family: Family
    /// Vision taxonomy identifiers that count as this category.
    var identifiers: Set<String>
    /// Confidence floor for a confident match. First-pass values — tune from coverage.
    var confidence: Float

    var subject: String {
        guard let article else { return displayName }
        return "\(article) \(displayName)"
    }

    var question: String { "Which photo has \(subject) in it?" }
}

nonisolated enum ObjectCatalog {

    /// Bump when the list or its thresholds change — cached tags re-derive themselves.
    static let version = 1

    /// A photo is excluded from being a distractor if the classifier saw even a hint of
    /// the target category. Errorless design: better to drop a candidate than to show
    /// two photos that both arguably have a dog in them.
    static let possibleConfidence: Float = 0.12

    static let categories: [ObjectCategory] = [
        // Animals — reliable, and the most fun to be asked about.
        ObjectCategory(id: "dog", displayName: "dog", article: "a", family: .animal,
                       identifiers: ["dog"], confidence: 0.45),
        ObjectCategory(id: "cat", displayName: "cat", article: "a", family: .animal,
                       identifiers: ["cat", "adult_cat"], confidence: 0.45),
        ObjectCategory(id: "bird", displayName: "bird", article: "a", family: .animal,
                       identifiers: ["bird"], confidence: 0.45),
        ObjectCategory(id: "horse", displayName: "horse", article: "a", family: .animal,
                       identifiers: ["horse"], confidence: 0.45),

        // Food — "cake" is the birthday-photo workhorse.
        ObjectCategory(id: "cake", displayName: "cake", article: "a", family: .food,
                       identifiers: ["cake", "cake_regular", "birthday_cake", "wedding_cake"],
                       confidence: 0.45),
        ObjectCategory(id: "food", displayName: "food", article: nil, family: .food,
                       identifiers: ["food"], confidence: 0.6),
        ObjectCategory(id: "fruit", displayName: "fruit", article: nil, family: .food,
                       identifiers: ["fruit", "citrus_fruit"], confidence: 0.5),

        // Nature and scenes.
        ObjectCategory(id: "flower", displayName: "flower", article: "a", family: .nature,
                       identifiers: ["flower", "flower_arrangement"], confidence: 0.5),
        ObjectCategory(id: "tree", displayName: "tree", article: "a", family: .nature,
                       identifiers: ["tree", "palm_tree", "oak_tree", "maple_tree",
                                     "eucalyptus_tree", "christmas_tree"], confidence: 0.5),
        ObjectCategory(id: "beach", displayName: "beach", article: "a", family: .nature,
                       identifiers: ["beach"], confidence: 0.5),
        ObjectCategory(id: "mountain", displayName: "mountain", article: "a", family: .nature,
                       identifiers: ["mountain"], confidence: 0.5),
        ObjectCategory(id: "snow", displayName: "snow", article: nil, family: .nature,
                       identifiers: ["snow"], confidence: 0.5),
        ObjectCategory(id: "water", displayName: "water", article: nil, family: .nature,
                       identifiers: ["water_body", "lake", "river", "ocean", "waterfall"],
                       confidence: 0.55),
        ObjectCategory(id: "garden", displayName: "garden", article: "a", family: .nature,
                       identifiers: ["garden"], confidence: 0.5),
        ObjectCategory(id: "forest", displayName: "forest", article: "a", family: .nature,
                       identifiers: ["forest"], confidence: 0.5),
        ObjectCategory(id: "sunset", displayName: "sunset", article: "a", family: .nature,
                       identifiers: ["sunset_sunrise"], confidence: 0.5),

        // Vehicles.
        ObjectCategory(id: "car", displayName: "car", article: "a", family: .vehicle,
                       identifiers: ["car", "police_car", "formula_one_car"], confidence: 0.5),
        ObjectCategory(id: "bicycle", displayName: "bicycle", article: "a", family: .vehicle,
                       identifiers: ["bicycle"], confidence: 0.5),
        ObjectCategory(id: "boat", displayName: "boat", article: "a", family: .vehicle,
                       identifiers: ["boat"], confidence: 0.5),
        ObjectCategory(id: "train", displayName: "train", article: "a", family: .vehicle,
                       identifiers: ["train", "train_real"], confidence: 0.5),

        // Made things.
        ObjectCategory(id: "book", displayName: "book", article: "a", family: .madeThing,
                       identifiers: ["book", "bookshelf"], confidence: 0.5),
        ObjectCategory(id: "instrument", displayName: "musical instrument", article: "a",
                       family: .madeThing,
                       identifiers: ["musical_instrument", "guitar", "brass_music"],
                       confidence: 0.5),
        ObjectCategory(id: "building", displayName: "building", article: "a", family: .madeThing,
                       identifiers: ["building", "skyscraper"], confidence: 0.6),
        ObjectCategory(id: "bridge", displayName: "bridge", article: "a", family: .madeThing,
                       identifiers: ["bridge"], confidence: 0.5),
    ]

    static func category(id: String) -> ObjectCategory? {
        lookup[id]
    }

    private static let lookup: [String: ObjectCategory] =
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

    /// Vision identifier → the categories it feeds, so one pass over the observations
    /// resolves the whole allow-list.
    static let byIdentifier: [String: [ObjectCategory]] = {
        var table: [String: [ObjectCategory]] = [:]
        for category in categories {
            for identifier in category.identifiers {
                table[identifier, default: []].append(category)
            }
        }
        return table
    }()

    static func displayName(forFirstOf tags: Set<String>) -> String? {
        categories.first { tags.contains($0.id) }?.displayName
    }
}

nonisolated extension PackMotif {
    /// What the bundled pack artwork actually draws. Hand-written rather than classified:
    /// we know exactly what is in these pictures, and motifs with no allow-listed subject
    /// (a portrait, a kitchen) simply stay untagged and serve as clean distractors.
    var objectTags: Set<String> {
        switch self {
        case .mountains: ["mountain"]
        case .seaside: ["beach", "water"]
        case .cityscape: ["building"]
        case .celebration: ["cake", "food"]
        case .garden: ["flower", "garden"]
        case .portrait, .kitchen, .roadTrip: []
        }
    }
}
