//
//  QuizCurator.swift
//  Time Rolls
//
//  Rounds for the four quiz categories — Geography, Cars, Film Stars, Sports Stars.
//
//  Each category is one pack, and a round is built from that pack alone: never a map beside
//  a car, never a photograph of the player's. The pool handed in here has already been cut
//  to the one theme by `LevelGenerator`, and every photograph in it is checked again below,
//  so a category cannot leak into another even if a pack declared two themes.
//
//  Three kinds of question:
//
//  * **Named** — "Which one is a map of Florida?", "Which car is a Ford Mustang?". Three
//    others from the same cluster where there are three: four US states, four pony cars,
//    four actresses of the same era. A round of one state and three countries gives itself
//    away.
//  * **Fact** — "Who starred in Casablanca (1942)?", "Which country borders Germany?". The
//    pack lists, per subject, what is known; the answer holds the value, and every
//    distractor is *known not to*. A subject whose facts say nothing either way about the
//    thing asked is not a distractor — absence of evidence is not evidence of absence, the
//    same rule the Things game was built on.
//  * **Generation** — "Which car is a 2020 Ford Mustang?". Four generations of one car,
//    every pair at least twenty years apart and none overlapping, so the question is about
//    reading an era off a car rather than telling two facelifts apart.
//

import Foundation

nonisolated enum QuizCurator {

    /// How far apart, in model years, any two cars in a generation round must be.
    static let generationGap = 20

    enum Ask: String, CaseIterable, Sendable {
        case named
        case fact
        case generation

        static func order(leastRecent recent: [String]) -> [Ask] {
            Recency.leastRecentFirst(allCases.shuffled(), key: \.rawValue, recent: recent)
        }
    }

    static func makeLevel(theme: GameTheme,
                          pool: [GamePhoto],
                          questions: [String: [QuizQuestion]],
                          recentFocus: [String] = [],
                          recentAsks: [String] = [],
                          recentWordings: [String] = []) -> Level? {
        // The engine keeps this list oldest-first; `Recency` reads newest-first.
        let recentFocus = Array(recentFocus.reversed())
        // The pool is the category's pack and nothing else.
        let pool = pool.filter { !$0.isPersonal && $0.askableName != nil }
        guard pool.count >= DifficultyKnob.photoCount else { return nil }

        for kind in Ask.order(leastRecent: recentAsks) {
            let level: Level?
            switch kind {
            case .named:
                level = namedLevel(theme: theme, pool: pool, recentFocus: recentFocus,
                                   recentWordings: recentWordings)
            case .fact:
                level = factLevel(theme: theme, pool: pool, questions: questions,
                                  recentFocus: recentFocus, recentWordings: recentWordings)
            case .generation:
                level = generationLevel(theme: theme, pool: pool, recentFocus: recentFocus)
            }
            if var level {
                level.ask = "quiz-\(kind.rawValue)"
                return level
            }
        }
        return nil
    }

    // MARK: - Fairness

    /// What a round asks a photograph by. A car is asked by its model line, so two
    /// generations of the Mustang are the same name and cannot both be in a named round.
    static func name(of photo: GamePhoto) -> String? {
        (photo.family ?? photo.askableName)?.lowercased()
    }

    /// Whether these photographs can share a round: no name twice (Georgia the state and
    /// Georgia the country), no subject twice, and nothing the pack says to keep apart.
    static func canStandTogether(_ photos: [GamePhoto]) -> Bool {
        var names: Set<String> = []
        var subjects: Set<String> = []
        for photo in photos {
            guard let name = name(of: photo), names.insert(name).inserted else { return false }
            if let subject = photo.subjectID, !subjects.insert(subject).inserted { return false }
        }
        let titles = Set(photos.compactMap { $0.title?.lowercased() })
        for photo in photos {
            let apart = Set(photo.keepApartFrom.map { $0.lowercased() })
            if !apart.isDisjoint(with: titles) { return false }
        }
        return true
    }

    /// Up to `count` distractors from `candidates`, the same cluster first, that can all
    /// stand beside `target` and each other.
    private static func distractors(for target: GamePhoto, from candidates: [GamePhoto],
                                    count: Int, sameClusterOnly: Bool,
                                    order: (([GamePhoto]) -> [GamePhoto])? = nil)
        -> [GamePhoto]? {
        let others = candidates.filter { $0.id != target.id }
        let same = others.filter { $0.cluster != nil && $0.cluster == target.cluster }
        let rest = others.filter { $0.cluster == nil || $0.cluster != target.cluster }
        let ordered = (order ?? { $0.shuffled() })
        let tiers = sameClusterOnly ? [ordered(same)] : [ordered(same), ordered(rest)]
        var chosen: [GamePhoto] = []
        for tier in tiers {
            for photo in tier where chosen.count < count {
                if canStandTogether([target] + chosen + [photo]) {
                    chosen.append(photo)
                }
            }
        }
        return chosen.count == count ? chosen : nil
    }

    // MARK: - Named

    /// "Which one is a map of Florida?" — "Which one is Audrey Hepburn?"
    private static func namedLevel(theme: GameTheme, pool: [GamePhoto],
                                   recentFocus: [String],
                                   recentWordings: [String]) -> Level? {
        let wanted = DifficultyKnob.photoCount
        let byName = Dictionary(grouping: pool) { name(of: $0) ?? "" }
            .filter { !$0.key.isEmpty }
        let names = Recency.leastRecentFirst(Array(byName.keys).shuffled(),
                                             key: { "named:\($0)" }, recent: recentFocus)
        for key in names.prefix(24) {
            guard let target = byName[key]?.randomElement() else { continue }
            // Cars: alike in era as well as in kind — a 1965 Mustang beside three 1960s
            // pony cars, not beside a 2020 hatchback.
            let order: (([GamePhoto]) -> [GamePhoto])? = target.askYear.map { year in
                { photos in
                    photos.shuffled().sorted {
                        abs(($0.askYear ?? 0) - year) < abs(($1.askYear ?? 0) - year)
                    }
                }
            }
            guard let others = distractors(for: target, from: pool, count: wanted - 1,
                                           sameClusterOnly: false, order: order) else { continue }
            let spoken = target.family ?? target.askableName ?? key
            // A pack may give several ways of asking, separated by "|" — Geography says
            // both "Which one is a map of France?" and "Which map shows France?" — and they
            // are taken in turn, the one used longest ago first, as every other kind of
            // question is.
            let photos = ([target] + others).shuffled()
            // People are asked about as people — see `PeopleWording` — and every other
            // pack by its own wordings.
            let people = PeopleWording.isAboutPeople(theme)
            let templates = people
                ? PeopleWording.named(among: photos, theme: theme)
                : (target.namedSubjectPrompt ?? "Which one is {name}?")
                    .split(separator: "|").map {
                        $0.trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "{name}", with: "{x}")
                    }
            let chosen = Recency.choose(templates.map { vehicleWording($0, for: photos) },
                                        kind: people ? "people-named" : "quiz-named",
                                        x: spoken, recent: recentWordings)
            var level = Level(theme: theme,
                         prompt: chosen.text,
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "quiz named · \(spoken) · \(byName.count) names",
                         focusTag: "named:\(key)",
                         // No hint on a person. "They're an American actress" beside four
                         // actresses says nothing, and beside one it says everything.
                         hint: people ? nil : hint(for: target, among: photos, theme: theme))
            // Recorded only where there was a choice, as everywhere else: a question with
            // one wording cannot be asked two ways, and remembering it would only teach the
            // rotation that the one wording is always "the same as last time".
            if templates.count > 1 { level.wording = chosen.wording }
            return level
        }
        return nil
    }

    /// "It's a country in Western Europe." Only when it points at one photograph.
    private static func hint(for answer: GamePhoto, among photos: [GamePhoto],
                             theme: GameTheme) -> String? {
        guard let kind = answer.subjectKind?.nilIfBlank else { return nil }
        let shared = photos.contains {
            $0.id != answer.id && $0.subjectKind?.caseInsensitiveCompare(kind) == .orderedSame
        }
        guard !shared else { return nil }
        return "It's \(kind)."
    }

    // MARK: - Facts

    /// "Who starred in Casablanca (1942)?" — "Which country borders Germany?"
    private static func factLevel(theme: GameTheme, pool: [GamePhoto],
                                  questions: [String: [QuizQuestion]],
                                  recentFocus: [String],
                                  recentWordings: [String]) -> Level? {
        let wanted = DifficultyKnob.photoCount
        let packs = Set(pool.compactMap(\.packID))
        let templates = packs.flatMap { questions[$0] ?? [] }.shuffled()

        for question in Recency.leastRecentFirst(templates, key: { "fact:\($0.id)" },
                                                 recent: recentFocus) {
            // Every value somebody in the pool holds, the least recently asked first.
            var holders: [String: [GamePhoto]] = [:]
            for photo in pool {
                for value in photo.facts[question.ask] ?? [] where !value.isBlank {
                    holders[value, default: []].append(photo)
                }
            }
            let values = Recency.leastRecentFirst(
                Array(holders.keys).shuffled(),
                key: { "fact:\(question.id):\($0)" }, recent: recentFocus)

            for value in values.prefix(30) {
                guard let target = holders[value]?.randomElement() else { continue }
                let lowered = value.lowercased()
                // Known not to hold the value, and not the thing the question names —
                // "which country borders France?" with France itself in the row.
                let cleared = pool.filter { photo in
                    guard let known = photo.facts[question.exclude] else { return false }
                    guard !known.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
                    else { return false }
                    return photo.title?.lowercased() != lowered
                }
                guard let others = distractors(for: target, from: cleared, count: wanted - 1,
                                               sameClusterOnly: question.sameCluster)
                else { continue }
                // The answer has to hold the value by the exclusion rule too, or the
                // question has a different meaning for the answer than for the others.
                if let known = target.facts[question.exclude],
                   !known.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                    continue
                }
                let photos = ([target] + others).shuffled()
                // Several wordings, separated by "|", taken in turn — "Who played for the
                // Packers?" and "Which player played for the Packers?".
                let wordings = question.prompt.split(separator: "|").map {
                    vehicleWording($0.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "{value}", with: "{x}"), for: photos)
                }
                let chosen = Recency.choose(wordings, kind: "fact-\(question.id)", x: value,
                                            recent: recentWordings)
                var level = Level(theme: theme,
                             prompt: chosen.text,
                             photos: photos,
                             correctPhotoID: target.id,
                             curationNote: "quiz fact · \(question.id) · \(value) · "
                                + "\(holders.count) values",
                             focusTag: "fact:\(question.id):\(value)",
                             hint: nil)
                if wordings.count > 1 { level.wording = chosen.wording }
                return level
            }
        }
        return nil
    }

    // MARK: - Generations

    /// "Which car is a 2020 Ford Mustang?" — four generations of one car, decades apart.
    ///
    /// "Which car", not "which one": only cars have generations, and naming what the four
    /// pictures are of is the plainer question.
    private static func generationLevel(theme: GameTheme, pool: [GamePhoto],
                                        recentFocus: [String]) -> Level? {
        let wanted = DifficultyKnob.photoCount
        let families = Dictionary(grouping: pool.filter { $0.family != nil && $0.askYear != nil }) {
            $0.family!
        }.filter { $0.value.count >= wanted }
        guard !families.isEmpty else { return nil }

        for family in Recency.leastRecentFirst(Array(families.keys).shuffled(),
                                               key: { "generation:\($0)" },
                                               recent: recentFocus) {
            let cars = families[family]!
            // A handful of shuffled greedy passes finds a spread whenever one exists in a
            // family this size, without trying every combination.
            for _ in 0..<12 {
                var chosen: [GamePhoto] = []
                for car in cars.shuffled() where chosen.count < wanted {
                    if chosen.allSatisfy({ farEnoughApart($0, car) }),
                       chosen.allSatisfy({ $0.subjectID == nil || $0.subjectID != car.subjectID }) {
                        chosen.append(car)
                    }
                }
                guard chosen.count == wanted, let target = chosen.randomElement(),
                      let year = target.askYear else { continue }
                return Level(theme: theme,
                             prompt: "Which \(vehicleNoun(for: chosen)) is a \(year) \(family)?",
                             photos: chosen.shuffled(),
                             correctPhotoID: target.id,
                             curationNote: "quiz generation · \(family) · "
                                + chosen.compactMap(\.askYear).sorted()
                                    .map(String.init).joined(separator: ", "),
                             focusTag: "generation:\(family)",
                             hint: nil)
            }
        }
        return nil
    }

    /// "Which truck is a Ford F-Series?", "Which car is a Ford Mustang?" — what the four
    /// are, in a word true of all of them: car, truck, van, and vehicle when they differ.
    static func vehicleNoun(for photos: [GamePhoto]) -> String {
        let nouns = Set(photos.map { photo -> String in
            switch photo.cluster {
            case "pickup truck": "truck"
            case "van": "van"
            case "SUV", "off-roader": "vehicle"
            default: "car"
            }
        })
        return nouns.count == 1 ? nouns.first! : "vehicle"
    }

    /// Fills `{noun}` in a car pack's wording. Every other pack passes straight through.
    static func vehicleWording(_ template: String, for photos: [GamePhoto]) -> String {
        template.replacingOccurrences(of: "{noun}", with: vehicleNoun(for: photos))
    }

    /// Twenty model years between the two named years, and the two generations never
    /// sharing a year — a car built in both would be an answer to both.
    static func farEnoughApart(_ a: GamePhoto, _ b: GamePhoto) -> Bool {
        guard let first = a.askYear, let second = b.askYear,
              abs(first - second) >= generationGap else { return false }
        if let x = a.generationYears, let y = b.generationYears, x.overlaps(y) { return false }
        return true
    }
}

// MARK: - People

/// How a question about a person is worded, wherever the person comes from — Famous Faces,
/// Film Stars, Sports Stars.
///
/// "Which one is Audrey Hepburn?" asks about a picture. These ask about the person: "Who is
/// Audrey Hepburn?", "Which actress is Audrey Hepburn?". A word like "actress" or "golfer"
/// is used only when it is true of all four people in the round, so it never narrows the
/// field — "which actress" beside three actors would be the answer, not the question.
nonisolated enum PeopleWording {

    static func isAboutPeople(_ theme: GameTheme) -> Bool {
        theme == .film || theme == .sports
    }

    /// The wordings for "which of these is {x}", most general first. `{x}` is the name.
    static func named(among photos: [GamePhoto], theme: GameTheme? = nil) -> [String] {
        var templates = ["Who is {x}?", "Which person is {x}?"]
        switch theme {
        case .film?: templates.append("Which film star is {x}?")
        case .sports?: templates.append("Which athlete is {x}?")
        default: break
        }
        if let noun = sharedNoun(of: photos, theme: theme) {
            templates.append("Which \(noun) is {x}?")
        }
        return templates
    }

    /// The one word true of everybody in the round, or nil.
    static func sharedNoun(of photos: [GamePhoto], theme: GameTheme?) -> String? {
        let nouns = photos.map { noun(for: $0, theme: theme) }
        guard let first = nouns.first, let noun = first,
              nouns.allSatisfy({ $0 == noun }) else { return nil }
        return noun
    }

    private static func noun(for photo: GamePhoto, theme: GameTheme?) -> String? {
        switch theme {
        case .film?:
            // The cluster reads "actress golden age", "actor modern".
            guard let word = photo.cluster?.split(separator: " ").first else { return nil }
            return ["actress", "actor"].contains(String(word)) ? String(word) : nil
        case .sports?:
            return sportNouns[photo.cluster ?? ""]
        default:
            // Famous Faces: the role read from each person's own description.
            return photo.subject.flatMap { roleNouns[$0] }
        }
    }

    private static let sportNouns = [
        "American football": "football player", "baseball": "baseball player",
        "basketball": "basketball player", "ice hockey": "hockey player",
        "soccer": "soccer player", "tennis": "tennis player",
        "golf": "golfer", "boxing": "boxer",
    ]

    private static let roleNouns = [
        "leader": "leader", "musician": "musician", "writer": "writer",
        "scientist": "scientist", "artist": "artist", "actor": "performer",
        "athlete": "athlete", "philosopher": "philosopher", "explorer": "explorer",
    ]
}
