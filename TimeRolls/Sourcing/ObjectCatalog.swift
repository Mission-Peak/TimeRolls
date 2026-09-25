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
    static let version = 25

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

        // --- Everyday things and the world around them.
        //
        // A hundred and twenty concepts from the expanded theme list, aimed at what is
        // actually in an older adult's photographs: the instruments, the cars, the
        // kitchen, the fairground. They carry no Vision identifiers — the taxonomy
        // knows about a fifth of them — and do not need to. The themes model compares a
        // photograph against written English, so a concept is added by writing it down
        // in Tools/Themes/concepts.json and running the text encoder once on a Mac.
        //
        // The confidence floor is the same 0.45 the first thirty use. It is a starting
        // value for every one of these and wants measuring against real photographs,
        // not trusting.
        // Animals
        ObjectCategory(id: "seahorse", displayName: "seahorse", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "jaguar", displayName: "jaguar", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "elephant", displayName: "elephant", article: "an",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "giraffe", displayName: "giraffe", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "penguin", displayName: "penguin", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "owl", displayName: "owl", article: "an",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "dolphin", displayName: "dolphin", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "kangaroo", displayName: "kangaroo", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "flamingo", displayName: "flamingo", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "polar_bear", displayName: "polar bear", article: "a",
                       family: .animal, identifiers: [], confidence: 0.45),
        // Carousel Horses & Vintage Fairgrounds
        ObjectCategory(id: "carousel_horse", displayName: "carousel horse", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "ferris_wheel", displayName: "Ferris wheel", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "fairground_carousel", displayName: "fairground carousel", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "carnival_strongman_game", displayName: "carnival strongman game", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "cotton_candy_machine", displayName: "cotton candy machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "fortune_teller_machine", displayName: "fortune-teller machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "tilt_a_whirl_ride", displayName: "Tilt-A-Whirl ride", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "vintage_roller_coaster", displayName: "vintage roller coaster", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "carnival_game_booth", displayName: "carnival game booth", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "hand_painted_carousel", displayName: "hand-painted carousel", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Diners & Soda Fountains
        ObjectCategory(id: "diner_counter_with_stools", displayName: "diner counter with stools", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "soda_fountain", displayName: "soda fountain", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "milkshake_in_a_metal_cup", displayName: "milkshake in a metal cup", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "diner_jukebox", displayName: "diner jukebox", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "neon_diner_sign", displayName: "neon diner sign", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "malt_shop_booth", displayName: "malt shop booth", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "root_beer_float", displayName: "root beer float", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "classic_diner_storefront", displayName: "classic diner storefront", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "checkerboard_diner_floor", displayName: "checkerboard diner floor", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "carhop_on_roller_skates", displayName: "carhop on roller skates", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Drive-Ins & Classic Entertainment
        ObjectCategory(id: "drive_in_movie_screen", displayName: "drive-in movie screen", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "drive_in_speaker_post", displayName: "drive-in speaker post", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "theater_marquee", displayName: "theater marquee", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "popcorn_machine", displayName: "popcorn machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "ticket_booth", displayName: "ticket booth", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "film_projector", displayName: "film projector", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "nickelodeon", displayName: "nickelodeon", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "family_gathered_around_a_radio", displayName: "family gathered around a radio", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "black_and_white_television_set", displayName: "black-and-white television set", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "console_television", displayName: "console television", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Musical Instruments
        ObjectCategory(id: "violin", displayName: "violin", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "saxophone", displayName: "saxophone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "trumpet", displayName: "trumpet", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "drum_set", displayName: "drum set", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "flute", displayName: "flute", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "harp", displayName: "harp", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "cello", displayName: "cello", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "accordion", displayName: "accordion", article: "an",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "banjo", displayName: "banjo", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "trombone", displayName: "trombone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Record Players & Home Audio
        ObjectCategory(id: "record_player", displayName: "record player", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "stack_of_vinyl_records", displayName: "stack of vinyl records", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "jukebox", displayName: "jukebox", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "vintage_console_radio", displayName: "vintage console radio", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "gramophone", displayName: "gramophone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "cassette_tape", displayName: "cassette tape", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "8_track_player", displayName: "8-track player", article: "an",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "boombox", displayName: "boombox", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "reel_to_reel_tape_recorder", displayName: "reel-to-reel tape recorder", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "transistor_radio", displayName: "transistor radio", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Rotary & Vintage Telephones
        ObjectCategory(id: "rotary_dial_telephone", displayName: "rotary dial telephone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "wall_mounted_telephone", displayName: "wall-mounted telephone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "telephone_booth", displayName: "telephone booth", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "switchboard", displayName: "switchboard", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "princess_phone", displayName: "princess phone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "payphone", displayName: "payphone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "party_line_telephone", displayName: "party-line telephone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "candlestick_telephone", displayName: "candlestick telephone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "corded_telephone", displayName: "corded telephone", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "operator_s_headset", displayName: "operator's headset", article: "an",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Sewing & Handcrafts
        ObjectCategory(id: "sewing_machine", displayName: "sewing machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "knitting_basket", displayName: "knitting basket", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "quilt_being_pieced", displayName: "quilt being pieced", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "spinning_wheel", displayName: "spinning wheel", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "loom", displayName: "loom", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "embroidery_hoop", displayName: "embroidery hoop", article: "an",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "button_jar", displayName: "button jar", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "darning_egg", displayName: "darning egg", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "thread_spool_rack", displayName: "thread spool rack", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "hand_crank_sewing_machine", displayName: "hand-crank sewing machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Steam Locomotives & Vintage Trains
        ObjectCategory(id: "steam_locomotive", displayName: "steam locomotive", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "train_caboose", displayName: "train caboose", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "vintage_train_platform", displayName: "vintage train platform", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "conductor_s_pocket_watch", displayName: "conductor's pocket watch", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "train_dining_car", displayName: "train dining car", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "railroad_water_tower", displayName: "railroad water tower", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "handcar", displayName: "handcar", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "vintage_subway_car", displayName: "vintage subway car", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "trolley_on_tracks", displayName: "trolley on tracks", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "ticket_punch", displayName: "ticket punch", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        // Typewriters & Letter Writing
        ObjectCategory(id: "typewriter", displayName: "typewriter", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "fountain_pen", displayName: "fountain pen", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "quill_and_inkwell", displayName: "quill and inkwell", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "mimeograph_machine", displayName: "mimeograph machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "rolodex", displayName: "rolodex", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "filing_cabinet", displayName: "filing cabinet", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "stack_of_handwritten_letters", displayName: "stack of handwritten letters", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "stamp_collection", displayName: "stamp collection", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "telegram", displayName: "telegram", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "manual_adding_machine", displayName: "manual adding machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        // Vintage & Classic Cars
        ObjectCategory(id: "1950s_convertible", displayName: "1950s convertible", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "ford_model_t", displayName: "Ford Model T", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "vw_beetle", displayName: "VW Beetle", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "muscle_car", displayName: "muscle car", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "wood_paneled_station_wagon", displayName: "wood-paneled station wagon", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "tail_finned_sedan", displayName: "tail-finned sedan", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "vintage_pickup_truck", displayName: "vintage pickup truck", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "motorcycle_with_a_sidecar", displayName: "motorcycle with a sidecar", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "horse_drawn_carriage", displayName: "horse-drawn carriage", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "streetcar", displayName: "streetcar", article: "a",
                       family: .vehicle, identifiers: [], confidence: 0.45),
        // Vintage Home & Kitchen
        ObjectCategory(id: "wood_burning_stove", displayName: "wood-burning stove", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "potbelly_stove", displayName: "potbelly stove", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "icebox", displayName: "icebox", article: "an",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "washboard_and_tub", displayName: "washboard and tub", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "hand_crank_washing_machine", displayName: "hand-crank washing machine", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "rotary_egg_beater", displayName: "rotary egg beater", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "percolator_coffee_pot", displayName: "percolator coffee pot", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "cast_iron_skillet", displayName: "cast-iron skillet", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "oil_lamp", displayName: "oil lamp", article: "an",
                       family: .madeThing, identifiers: [], confidence: 0.45),
        ObjectCategory(id: "wood_fired_oven", displayName: "wood-fired oven", article: "a",
                       family: .madeThing, identifiers: [], confidence: 0.45),
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
