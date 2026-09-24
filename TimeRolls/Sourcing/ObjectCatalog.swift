//
//  ObjectCatalog.swift
//  Time Rolls
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
    /// A question of its own, for categories where "which photo has a mammal in it?"
    /// is the wrong shape and "which one is a mammal?" is the right one.
    var questionOverride: String?

    var subject: String {
        guard let article else { return displayName }
        return "\(article) \(displayName)"
    }

    var question: String { questionOverride ?? "Which photo has \(subject) in it?" }
}

nonisolated enum ObjectCatalog {

    /// Things that turn up in photographs without anybody meaning them to, and so cannot
    /// carry the question "which photo has a … in it?"
    ///
    /// A tree is in the background of half of all outdoor photographs. So the round asks
    /// which photo has a tree, two of them plainly do, and the player is right and the
    /// game says no. The model is not wrong about either picture — the *question* is
    /// unanswerable, and no amount of better looking fixes it.
    ///
    /// This is the same failure as absence of evidence elsewhere in the pipeline, wearing
    /// different clothes: the distractor rules can only rule a photograph out when
    /// something noticed the tree in it, and nothing notices the tree behind a group of
    /// people at a party. The fix is not to ask.
    ///
    /// These remain perfectly good as *themes* — "a walk in the woods" is a fine round.
    /// They are only unfit as the thing a Things question hunts for.
    static let tooIncidentalToAskAbout: Set<String> = [
        "tree", "water", "building", "bridge", "car",
    ]

    /// Things that are photographed *close up*, so a photograph of one is a photograph of
    /// it rather than of wherever it happened to be.
    ///
    /// The Places game asks where a photograph was taken, and the player answers from what
    /// they can see. A dinner, a cake, a dog filling the frame — these tell you nothing
    /// about the county, even when the scene model is quite right that the sky is visible
    /// behind them. Landscape-ish concepts are deliberately absent from this list: a beach,
    /// a mountain or a bridge *is* somewhere.
    static let subjectsRatherThanPlaces: Set<String> = [
        "food", "fruit", "cake", "flower", "book", "instrument",
        "dog", "cat", "bird", "horse",
        "class-mammal", "class-bird", "class-reptile", "class-amphibian",
        "class-fish", "class-insect",
    ]

    static func isASubjectRatherThanAPlace(_ concept: String) -> Bool {
        subjectsRatherThanPlaces.contains(concept)
    }

    /// Creatures that could be argued over in a photograph, and so may never appear in
    /// the same round.
    ///
    /// Asking "which photo has a lion in it?" is safe beside a tiger, because nobody has
    /// ever mistaken one for the other. It is not safe beside a lioness, and it is not
    /// safe to ask for an alligator beside a crocodile or a hare beside a rabbit — those
    /// are distinctions a zoologist makes from a photograph and a person cannot. The
    /// answer would still be *true*; it would not be *findable*, which is the same
    /// failure as four anonymous streets and one of them being Shibuya.
    static let confusable: [Set<String>] = [
        ["alligator", "crocodile", "caiman"],
        ["rabbit", "hare"],
        ["frog", "toad"],
        ["butterfly", "moth"],
        ["dolphin", "porpoise", "whale"],
        ["crow", "raven", "rook", "jackdaw"],
        ["leopard", "jaguar", "cheetah", "panther"],
        ["donkey", "mule", "horse", "pony"],
        ["turtle", "tortoise", "terrapin"],
        ["seal", "sea lion", "walrus"],
        ["moose", "elk", "deer", "reindeer", "caribou"],
        ["wolf", "coyote", "jackal", "dog"],
        ["monkey", "ape", "chimpanzee", "gorilla", "orangutan", "baboon"],
        ["eagle", "hawk", "falcon", "buzzard", "kite"],
        ["goat", "sheep", "lamb", "ram"],
        ["bee", "wasp", "hornet"],
        ["squid", "octopus", "cuttlefish"],
        ["rat", "mouse", "vole"],
        ["alpaca", "llama"],
        ["ferret", "weasel", "stoat", "mink", "otter"],
    ]

    /// Whether two named creatures can stand in the same round.
    static func canStandTogether(_ one: String, _ other: String) -> Bool {
        let first = one.lowercased(), second = other.lowercased()
        if first == second { return false }
        // Whole words. This used to ask whether the name *contained* a confusable word
        // anywhere in it, which is true of far more names than anybody would guess:
        // "transfiguration" contains "rat", and so does "horatii", so a round holding
        // Raphael's Transfiguration and The Oath of the Horatii was refused on the
        // grounds that nobody could tell the two rodents apart.
        let firstWords = words(in: first), secondWords = words(in: second)
        for group in confusable {
            let hasFirst = group.contains { firstWords.contains($0) }
            let hasSecond = group.contains { secondWords.contains($0) }
            if hasFirst && hasSecond { return false }
        }
        return true
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init))
    }

    /// Bump when the list or its thresholds change — cached tags re-derive themselves.
    static let version = 24

    /// A photo is excluded from being a distractor if the classifier saw even a hint of
    /// the target category. Errorless design: better to drop a candidate than to show
    /// two photos that both arguably have a dog in them.
    ///
    /// Lowered from 0.12. A "hint" should be almost any flicker of recognition, because
    /// the cost of the two mistakes is not symmetric: excluding a usable distractor costs
    /// a level nobody misses, while admitting one costs somebody a correct answer marked
    /// wrong. The failing case was a bare winter wood that the classifier saw only as sky,
    /// offered as a distractor for "which photo has a tree in it?".
    static let possibleConfidence: Float = 0.05

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

        // Animal classes. Like the seasonal subjects before them these carry no Vision
        // identifiers, so the classifier can never put one on somebody's own photograph —
        // they are declared by hand on the Animals pack, where the answer is a fact about
        // the creature rather than a guess about the picture.
        ObjectCategory(id: "class-mammal", displayName: "mammal", article: "a", family: .animal,
                       identifiers: [], confidence: 1, questionOverride: "Which one is a mammal?"),
        ObjectCategory(id: "class-bird", displayName: "bird", article: "a", family: .animal,
                       identifiers: [], confidence: 1, questionOverride: "Which one is a bird?"),
        ObjectCategory(id: "class-reptile", displayName: "reptile", article: "a", family: .animal,
                       identifiers: [], confidence: 1, questionOverride: "Which one is a reptile?"),
        ObjectCategory(id: "class-amphibian", displayName: "amphibian", article: "an", family: .animal,
                       identifiers: [], confidence: 1, questionOverride: "Which one is an amphibian?"),
        ObjectCategory(id: "class-fish", displayName: "fish", article: "a", family: .animal,
                       identifiers: [], confidence: 1, questionOverride: "Which one is a fish?"),
        ObjectCategory(id: "class-insect", displayName: "insect", article: "an", family: .animal,
                       identifiers: [], confidence: 1, questionOverride: "Which one is an insect?"),
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
