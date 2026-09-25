//
//  LevelGenerator.swift
//  Time Rolls
//
//  Assembles the pool for a level and hands it to the right curator.
//  Curation is re-run at play time with randomness, so the same theme yields a
//  different photo set every session (spec §3.1).
//

import Foundation

struct LevelGenerator {

    var personal: [GamePhoto] = []
    var pack: [GamePhoto] = []
    /// Which games each pack is willing to carry, by pack id.
    var packThemeSupport: [String: Set<GameTheme>] = [:]
    /// How each pack phrases "which came first".
    var packChronologyPrompts: [String: String] = [:]
    /// Packs whose dates are birthdays rather than the dates of the photographs.
    var birthDatedPacks: Set<String> = []
    /// Whether the on-device pass is running at all. It cannot load in the Simulator,
    /// and a rule that waits for it would leave Places empty there for ever.
    var examinesPhotos = true

    /// How different two photographs look, when the tagger has seen both. Injected
    /// rather than called directly: this file is also compiled by the curation harness,
    /// which has no Vision and no photo library.
    var visualDistance: ((GamePhoto, GamePhoto) -> Double?)?
    /// How much a photograph looks like a named thing, from the bundled themes model —
    /// a second opinion on what the classifier claims to have seen.
    var conceptScore: ((GamePhoto, String) -> Double?)?
    /// Whether a photograph is of somewhere rather than of somebody.
    var showsAPlace: ((GamePhoto) -> Bool?)?
    /// What the themes model thinks a photograph is most a picture of.
    var bestConcept: ((GamePhoto) -> String?)?

    /// Below this, two photographs are the same moment: one shot twice, a burst frame
    /// PhotoKit did not label, the same view a second apart. Deliberately small —
    /// throwing away a photograph that was merely similar is the worse mistake, and a
    /// set of four is a poor place to be strict.
    private let duplicateDistance = 0.22
    /// Subjects the Things game has asked about lately, freshest last.
    var recentCategories: [String] = []
    /// Which kinds of question have been asked lately, most recent first, so the objects
    /// curator can move between them rather than settling on whichever it tries first.
    var recentAsks: [String] = []
    /// The wordings used lately, most recent first, so the same sentence is not asked
    /// twice running.
    var recentWordings: [String] = []
    /// Places and albums asked about lately, kept apart from Things so a place name can
    /// never silence a subject that happens to share its spelling.
    var recentPlaces: [String] = []
    /// Photographs from the last few rounds. Curation steps around them whenever the
    /// library can spare them: with a few hundred photographs and no memory at all,
    /// random sampling shows the same faces again and again, which is what makes a
    /// large catalogue feel small.
    var recentlyUsed: Set<String> = []

    /// Photographs the on-device model described as notes to self rather than memories.
    /// Applied beside the caregiver's own list, and for the same reason: neither is a
    /// judgement the round-building rules could make for themselves.
    var setAsideByDescription: Set<String> = []

    /// Questions this player has already got wrong, and is not asked again.
    var missedPairings: Set<String> = []

    /// Photographs a caregiver has struck off (spec §4). Applied in `pool(for:)`, which
    /// is the one door every level and every availability check comes through — a filter
    /// applied anywhere else is a filter something eventually walks around.
    var excluded: Set<String> = []

    /// How many of a round's photographs should be the player's own.
    ///
    /// One, with the rest from the packs — three to one at the usual four-photograph
    /// round. This is a reversal of what the app did before, and worth saying why.
    ///
    /// The old rule treated a pack photograph as a garnish: blended in on a one-in-three
    /// roll, at most two per round, and only for libraries under a hundred and twenty
    /// photographs. That was right when a pack held twenty-four pictures and the player's
    /// own library was all the content there was. It stopped being right once the packs
    /// held thousands — a player with a full camera roll was seeing almost none of them,
    /// three packs were effectively invisible, and the same personal photographs came
    /// round again and again while a thousand public ones went unshown.
    ///
    /// One personal photograph per round is also what makes the game work for somebody
    /// who has very few. A library of thirty pictures can carry a round a day for a long
    /// time when it only has to supply one photograph of the four.
    ///
    /// It is a target, not a guarantee. A round is built by a curator working to its own
    /// rules — dates, places, themes — and the ratio is reached by asking it a few times
    /// and taking the closest answer, never by forcing a photograph into a round it does
    /// not belong in.
    static let personalPhotosWanted = 1

    /// How many times to ask for a round before settling for the closest ratio so far.
    /// Eight was not enough. A curator picks by its own rules and a quarter of its
    /// answers come out with none of the player's photographs in them; asking more times
    /// is cheap — a level is built from photographs already in memory — and it is the
    /// only lever that does not distort what a round is allowed to contain.
    private let attemptsAtTheRatio = 24

    /// How many years of the player's own photographs there are, end to end. Nil when
    /// there are too few dated ones to say.
    var personalSpan: TimeInterval? {
        let dates = personal.compactMap(\.creationDate).sorted()
        guard let first = dates.first, let last = dates.last, dates.count >= 3 else {
            return nil
        }
        let span = last.timeIntervalSince(first)
        return span > 30 * .day ? span : nil
    }


    // MARK: - Availability

    func canPlay(_ theme: GameTheme) -> Bool {
        switch theme {
        case .chronology:
            return pool(for: theme, forceBlend: true)
                .filter { $0.creationDate != nil }.count >= 3
        case .places:
            let places = Set(pool(for: theme, forceBlend: true)
                .compactMap(\.placeName))
            return places.count >= 3
        case .objects:
            // Needs a subject plus enough photos that plainly don't contain it.
            return ObjectsCurator.makeLevel(
                pool: pool(for: theme, forceBlend: true)) != nil
        }
    }

    func availableThemes() -> [GameTheme] {
        GameTheme.allCases.filter { canPlay($0) }
    }

    // MARK: - Generation

    func makeLevel(theme: GameTheme) -> Level? {
        // Aim for one of the player's own and the rest from the packs. Curation is random,
        // so asking a few times and keeping the closest gets there without ever putting a
        // photograph into a round where it does not belong.
        //
        // A library with nothing usable for this theme lands on zero and stays there, and
        // that is the right answer rather than a failure: an all-pack round is a real
        // round, and refusing to build one would leave a player with no photographs of
        // their own staring at an empty screen.
        var best: Level?
        var bestDistance = Int.max
        for _ in 0..<attemptsAtTheRatio {
            // `continue`, not `break`. Each attempt is offered a different photograph of
            // the player's, and some of them cannot make a round — a `break` here threw
            // the whole round away on the first unlucky draw, and a library that could
            // easily have answered was reported as having nothing to ask about.
            guard let level = freshQuestion(theme: theme),
                  showsEachSubjectOnce(level) else { continue }
            let mine = level.photos.count(where: \.isPersonal)
            let distance = abs(mine - Self.personalPhotosWanted)
            if distance == 0 { return level }
            if distance < bestDistance {
                best = level
                bestDistance = distance
            }
        }
        if let best { return best }
        // Nothing at all could be built from a pool holding one of their photographs.
        // Open it up and take whatever round can be made.
        for _ in 0..<attemptsAtTheRatio {
            if let level = freshQuestion(theme: theme, widened: true),
               showsEachSubjectOnce(level) {
                return level
            }
        }
        return nil
    }

    /// No two photographs in a round may be of the same thing.
    ///
    /// Packs hold several photographs of each subject now — that is what makes five
    /// thousand photographs of recognisable things possible, where one-per-subject ran out
    /// at about two hundred famous paintings. The cost is that a round can be dealt two
    /// pictures of the Eiffel Tower and mark one of them wrong, which is the worst thing
    /// this game can do: it tells somebody who was right that they were not.
    ///
    /// Checked here rather than inside each curator. Every curator picks distractors its
    /// own way and would need its own version of this; one test on the finished round
    /// covers all of them, including any added later.
    private func showsEachSubjectOnce(_ level: Level) -> Bool {
        var seen: Set<String> = []
        for photo in level.photos {
            guard let subject = photo.subjectID else { continue }
            guard seen.insert(subject).inserted else { return false }
        }
        return true
    }

    /// A round this player has not already got wrong.
    ///
    /// Curation is random, so asking again is usually enough; a handful of tries keeps a
    /// library whose every question has been missed from spinning here forever, and the
    /// round it settles for is one they have seen rather than no round at all.
    private func freshQuestion(theme: GameTheme,
                               widened: Bool = false) -> Level? {
        var fallback: Level?
        for _ in 0..<6 {
            guard let level = curate(theme: theme, widened: widened)
            else { return fallback }
            guard AlreadyMissed.wasMissed(subject: level.focusTag,
                                          answer: level.correctPhotoID,
                                          among: missedPairings) else { return level }
            fallback = fallback ?? level
        }
        return fallback
    }

    private func curate(theme: GameTheme,
                        widened: Bool = false) -> Level? {
        let pool = deduplicated(setAside(recentlyUsed,
                                         from: pool(for: theme, widened: widened),
                                         theme: theme))
        switch theme {
        case .chronology:
            return ChronologyCurator.makeLevel(pool: pool,
                                               prompts: packChronologyPrompts,
                                               birthDatedPacks: birthDatedPacks,
                                               personalSpan: personalSpan,
                                               recentAsks: recentAsks,
                                               recentWordings: recentWordings,
                                               visualDistance: visualDistance)
                ?? ChronologyCurator.makeLevel(
                    pool: self.pool(for: theme, forceBlend: true, widened: widened),
                    prompts: packChronologyPrompts,
                    birthDatedPacks: birthDatedPacks,
                    personalSpan: personalSpan,
                    recentAsks: recentAsks,
                    recentWordings: recentWordings,
                    visualDistance: visualDistance)
        case .places:
            return PlacesCurator.makeLevel(pool: pool,
                                           recentPlaces: recentPlaces,
                                           recentAsks: recentAsks,
                                           recentWordings: recentWordings,
                                           visualDistance: visualDistance)
                ?? PlacesCurator.makeLevel(
                    pool: self.pool(for: theme, forceBlend: true, widened: widened),
                    recentPlaces: recentPlaces,
                    recentAsks: recentAsks,
                    recentWordings: recentWordings,
                    visualDistance: visualDistance)
        case .objects:
            return ObjectsCurator.makeLevel(pool: pool,
                                            recentCategories: recentCategories,
                                            recentAsks: recentAsks,
                                            recentWordings: recentWordings,
                                            visualDistance: visualDistance,
                                            conceptScore: conceptScore,
                                            bestConcept: bestConcept)
                ?? ObjectsCurator.makeLevel(
                    pool: self.pool(for: theme, forceBlend: true, widened: widened),
                    recentCategories: recentCategories,
                    recentAsks: recentAsks,
                    recentWordings: recentWordings,
                    visualDistance: visualDistance,
                    conceptScore: conceptScore,
                    bestConcept: bestConcept)
        }
    }

    /// Personal photos, plus pack photos when the library is thin for this theme
    /// (standalone content) or when the variety roll comes up (blending).
    /// The player's own photos that can carry this theme.
    private func usablePersonal(for theme: GameTheme) -> [GamePhoto] {
        // A receipt, a meme or a message is not a memory, whatever else it is.
        var personal = personal.filter { !$0.looksLikeDocument }
        // And of what is left, the better half of the photographs, as Apple's own
        // rating has it — but only while that leaves plenty to build rounds from. A
        // thin library would rather show a dull photograph than no photograph.
        let rated = personal.filter { $0.wasExamined }
        if rated.count >= 60 {
            let scores = rated.map(\.aesthetics).sorted()
            let median = scores[scores.count / 2]
            let good = personal.filter { !$0.wasExamined || $0.aesthetics >= median }
            if good.count >= 40 { personal = good }
        }
        return switch theme {
        case .chronology:
            personal.filter { $0.creationDate != nil }
        case .places:
            // Scanned photos, screenshots and stripped metadata leave many libraries
            // GPS-poor — this is the known gap in spec §5.2.
            //
            // A close-up of a face is dropped even when its coordinates are perfect: the
            // question is where the photograph was taken, and a selfie answers it only
            // for whoever was there.
            //
            // And only photographs the on-device pass has been through: an unexamined
            // photograph has a face prominence of zero because nobody has looked, not
            // because there is no face, and reading that as "shows its surroundings" is
            // what put three close-ups of one person in a round about McLean.
            personal.filter {
                guard $0.placeName != nil, !$0.hidesSurroundings,
                      $0.wasExamined || !examinesPhotos else { return false }
                // Four photographs of people, asking which one is from North Carolina,
                // is a question with nothing in the pictures to answer it. A photograph
                // earns a place in this game by being of somewhere.
                guard showsAPlace?($0) ?? true else { return false }
                // Outdoors is not the same as being *of* somewhere. A plate of
                // ratatouille on a terrace table is outdoors by every measure the scene
                // model has, and it is still a photograph of dinner — there is nothing in
                // it that says North Carolina, or anywhere. So a photograph whose
                // strongest reading is a thing in the foreground is not a photograph of a
                // place, however much sky is behind it.
                if let concept = bestConcept?($0),
                   ObjectCatalog.isASubjectRatherThanAPlace(concept) {
                    return false
                }
                return true
            }
        case .objects:
            // Untagged photos are still useful here: a photo the classifier found
            // nothing in is a perfectly clean distractor.
            personal
        }
    }

    /// One photograph per moment — the best one.
    ///
    /// Three shots of the same candles are three chances to offer the player two
    /// pictures that are for all purposes the same, which makes the question a coin
    /// toss dressed as a decision. Of each near-identical run, the one kept is the one
    /// where the eyes are open and the shot is in focus: a burst exists precisely
    /// because one frame of it is better than the others.
    private func deduplicated(_ photos: [GamePhoto]) -> [GamePhoto] {
        guard let visualDistance else { return photos }
        var kept: [GamePhoto] = []
        kept.reserveCapacity(photos.count)
        for photo in photos {
            // Only the recent neighbours: a library of thousands cannot afford every
            // pair, and duplicates sit next to each other in time anyway.
            let start = max(kept.count - 40, 0)
            let twin = (start ..< kept.count).first { index in
                guard let distance = visualDistance(photo, kept[index]) else { return false }
                return distance < duplicateDistance
            }
            guard let twin else {
                kept.append(photo)
                continue
            }
            if betterOfTheTwo(photo, kept[twin]) { kept[twin] = photo }
        }
        return kept
    }

    /// Which of two photographs of the same moment to keep: the better shot of whoever
    /// is in it, and failing that the better photograph.
    private func betterOfTheTwo(_ candidate: GamePhoto, _ incumbent: GamePhoto) -> Bool {
        if candidate.shotQuality > 0 || incumbent.shotQuality > 0 {
            return candidate.shotQuality > incumbent.shotQuality
        }
        return candidate.aesthetics > incumbent.aesthetics
    }

    /// Drops the recently-seen photographs, unless doing so leaves too little to build a
    /// level from. Freshness is a preference; a playable level is not.
    private func setAside(_ recent: Set<String>,
                          from photos: [GamePhoto],
                          theme: GameTheme) -> [GamePhoto] {
        guard !recent.isEmpty else { return photos }
        let fresh = photos.filter { !recent.contains($0.id) }
        switch theme {
        case .chronology:
            // Room to pick a spread rather than simply everything that is left.
            return fresh.count(where: { $0.creationDate != nil }) >= DifficultyKnob.photoCount * 3
                ? fresh : photos
        case .places:
            return Set(fresh.compactMap(\.placeName)).count >= DifficultyKnob.photoCount + 2
                ? fresh : photos
        case .objects:
            return Set(fresh.flatMap(\.objectTags)).count >= 2 ? fresh : photos
        }
    }

    /// Whether the personal library is too thin to carry this theme on its own.
    private func isSparse(for theme: GameTheme) -> Bool {
        let usable = usablePersonal(for: theme)
        switch theme {
        case .chronology:
            return usable.count < DifficultyKnob.photoCount * 3
        case .places:
            return Set(usable.compactMap(\.placeName)).count < 3
        case .objects:
            return Set(usable.flatMap(\.objectTags)).count < 2
        }
    }

    private func pool(for theme: GameTheme,
                      forceBlend: Bool = false,
                      widened: Bool = false) -> [GamePhoto] {
        let usable = usablePersonal(for: theme)
            .filter { !excluded.contains($0.id) && !setAsideByDescription.contains($0.id) }
        // Only packs that can carry this game. A pack of undatable photographs must
        // never end up in "which one is older".
        let pack = pack.filter { photo in
            guard case let .pack(packID, _) = photo.origin else { return false }
            guard !excluded.contains(photo.id) else { return false }
            return packThemeSupport[packID]?.contains(theme) ?? true
        }
        guard !pack.isEmpty else { return usable }

        // One of the player's own photographs in the pool, and no more.
        //
        // Three to one has to be a fact about every round, not an average over many. Two
        // weaker versions were tried first. Asking a curator again and keeping the closest
        // answer reached it 22 times in 900. Handing it a pool already three parts public
        // did much better — 303 in 900, and a mean of almost exactly one — but the spread
        // ran 0, 1, 2 in near-equal thirds, because a pool in a ratio only makes that ratio
        // likely, never certain.
        //
        // So the pool carries one. A round can then hold one of their photographs or none,
        // and never two, whatever the curator decides; `makeLevel` asks again with a
        // different one until the round contains it. The curator is never told which
        // photograph to use — it still picks by date, by place, by subject, and if the one
        // on offer does not belong in the round it does not go in.
        //
        // Except when that leaves nothing to ask. A Time round needs photographs far
        // enough apart in time to be readable, and a pack cannot always supply three of
        // those around one particular photograph of the player's. Rather than show an
        // empty screen, the last resort is the whole library — a round in the wrong ratio
        // beats no round, every time.
        if widened { return pack + usable }

        // Which one of theirs goes in matters for Places, and only for Places. The curator
        // asks about somewhere they went, and one photograph at a place is a car park
        // rather than a visit — a test it cannot make any more, because it is handed one
        // photograph and cannot see how many others share its place. Here the whole
        // library is in view, so the choice is made from places they photographed more
        // than once. Falling back to any of them keeps a thin library playable.
        if theme == .places {
            let byPlace = Dictionary(grouping: usable.compactMap { photo in
                photo.placeName.map { (place: $0, photo: photo) }
            }, by: \.place)
            let visited = byPlace.filter { $0.value.count >= 3 }.flatMap(\.value).map(\.photo)
            let candidates = visited.isEmpty ? usable : visited
            return pack + candidates.shuffled().prefix(Self.personalPhotosWanted)
        }
        return pack + usable.shuffled().prefix(Self.personalPhotosWanted)
    }
}
