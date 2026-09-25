//
//  Curators.swift
//  Time Rolls
//
//  Curation and difficulty logic (spec §5). Two rules run through all of it:
//  the right answer is always unambiguous (errorless design, §2), and the
//  distractors are always plausible rather than obviously-wrong filler (§5.3).
//

import Foundation
import CoreLocation

/// How much a distractor looks like the answer.
///
/// The spec asks for distractors "near enough in time, place or appearance to require
/// an actual decision", and appearance was the one of the three nothing could measure.
/// A feature print gives a number for it, so this is the same lever the other two
/// themes already have: gentle rounds take the photographs that look least like the
/// answer, hard rounds take the ones that look most like it.
enum Resemblance {

    /// Candidates ordered along that axis, and a roll of the difficulty knob to decide
    /// which end to take from. Photographs nothing is known about — not yet looked at,
    /// or a pack photograph the tagger never saw — keep their place in the shuffle
    /// rather than being ranked as though they were the least alike.
    static func ranked(_ candidates: [GamePhoto],
                       like answer: GamePhoto,
                       distance: ((GamePhoto, GamePhoto) -> Double?)?,
                       noCloserThan floor: Double = 0,
                       alikeChance: Double = DifficultyKnob.chanceOfAlikeDistractors)
    -> [GamePhoto] {
        guard let distance, candidates.count > 2 else { return candidates.shuffled() }
        var known: [(GamePhoto, Double)] = []
        var unknown: [GamePhoto] = []
        for candidate in candidates {
            if let measured = distance(candidate, answer) {
                // Alike is the point; identical is not. A photograph that looks the
                // same as the answer makes the round a coin toss dressed as a decision
                // — three anonymous streets beside the one that is really Shibuya.
                guard measured >= floor else { continue }
                known.append((candidate, measured))
            } else {
                unknown.append(candidate)
            }
        }
        guard known.count > 2 else { return candidates.shuffled() }
        let wantsAlike = Double.random(in: 0...1) < alikeChance
        let sorted = known
            .sorted { wantsAlike ? $0.1 < $1.1 : $0.1 > $1.1 }
            .map(\.0)
        // The player's own photograph goes to the front of the queue.
        //
        // The pool holds exactly one of theirs among a couple of thousand pack
        // photographs, so leaving the choice to chance meant most rounds never picked it:
        // measured, a third of rounds came out with none of their photographs in at all.
        // Putting it first does not force it into the round — it still has to clear every
        // rule below, the same as any other candidate — it only means the round looks at
        // it before it looks at the fifteen hundredth picture of somebody else's holiday.
        let (mine, theirs) = (sorted + unknown.shuffled())
            .reduce(into: ([GamePhoto](), [GamePhoto]())) { split, photo in
                if photo.isPersonal { split.0.append(photo) } else { split.1.append(photo) }
            }
        return mine + theirs
    }
}

/// What has been asked lately, and how to choose something that has not.
///
/// One helper for the memory and one for reading it, so the two cannot disagree. They did:
/// the engine appended each kind to the end of its list, and the rotation read the list as
/// most-recent-first. So on a real device, once every kind had come up once, the rotation
/// tried the *most* recent kind first and the same question came back round after round.
/// The harness built its own list the other way round and passed. Both now go through
/// `remembering`, and `Recency` is the only thing that reads the result.
nonisolated enum Recency {

    /// How many recent kinds or wordings are worth remembering. Enough to hold every
    /// wording of every kind at once, so no kind's last wording falls out of memory
    /// before that kind comes round again and gets asked the same way.
    static let window = 64

    /// `recent` with `tag` moved to the front. Most recent first, always.
    static func remembering(_ tag: String, in recent: [String]) -> [String] {
        Array(([tag] + recent.filter { $0 != tag }).prefix(window))
    }

    /// `options` ordered with the longest-unused first. Anything never used goes first;
    /// ties keep their given order, so the choice is stable rather than random.
    static func leastRecentFirst<T>(_ options: [T], key: (T) -> String,
                                    recent: [String]) -> [T] {
        options.enumerated().sorted { lhs, rhs in
            let l = recent.firstIndex(of: key(lhs.element)) ?? Int.max
            let r = recent.firstIndex(of: key(rhs.element)) ?? Int.max
            if l != r { return l > r }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// One of several ways of asking the same thing, the one used longest ago.
    static func wording(_ variants: [String], recent: [String]) -> String {
        leastRecentFirst(variants, key: { $0 }, recent: recent).first ?? variants[0]
    }

    /// A template chosen by how long ago it was used, and filled in.
    ///
    /// The memory holds templates — "Which one shows {x}?" — not finished sentences, so
    /// "Which one shows a lion?" and "Which one shows Louis Pasteur?" count as the same
    /// shape of question and are not asked back to back. Comparing finished sentences
    /// against a memory of templates matches nothing, and quietly picks the first wording
    /// every time.
    ///
    /// Remembered per kind of question. Kinds share sentences — "which of these is {x}?"
    /// asks about a mammal and about Louis Pasteur — and when the memory was shared, one
    /// kind using a wording could push another kind back onto the wording it used last
    /// time. Keyed by kind, each kind goes round its own wordings in turn.
    static func choose(_ templates: [String], kind: String, x: String = "",
                       plural: String = "",
                       recent: [String]) -> (text: String, wording: String) {
        let key = { (template: String) in "\(kind)|\(template)" }
        let template = leastRecentFirst(templates, key: key, recent: recent).first
            ?? templates[0]
        let text = template
            .replacingOccurrences(of: "{xs}", with: plural)
            .replacingOccurrences(of: "{x}", with: x)
        return (text, key(template))
    }
}

enum ChronologyCurator {

    /// Buckets the pool into time windows and samples inside one of them.
    /// Tight windows make a hard level; wide ones make an easy one — the time-delta
    /// lever from spec §5.1.
    static func makeLevel(pool: [GamePhoto],
                          prompts: [String: String] = [:],
                          birthDatedPacks: Set<String> = [],
                          personalSpan: TimeInterval? = nil,
                          recentAsks: [String] = [],
                          recentWordings: [String] = [],
                          visualDistance: ((GamePhoto, GamePhoto) -> Double?)? = nil) -> Level? {
        guard var level = assemble(pool: pool, prompts: prompts,
                                   birthDatedPacks: birthDatedPacks,
                                   personalSpan: personalSpan, recentAsks: recentAsks,
                                   visualDistance: visualDistance) else { return nil }
        // Worded here, once, from the photographs the round ended up with. The paths
        // that build a round each wrote their own sentence; choosing among several
        // wordings in one place is what stops any of them being asked the same way twice.
        let phrase = phrasing(for: level.photos, prompts: prompts,
                              birthDatedPacks: birthDatedPacks, recent: recentWordings)
        level.prompt = phrase.text
        level.wording = phrase.wording
        if level.ask == nil { level.ask = phrase.ask }
        return level
    }

    private static func assemble(pool: [GamePhoto],
                                 prompts: [String: String],
                                 birthDatedPacks: Set<String>,
                                 personalSpan: TimeInterval?,
                                 recentAsks: [String],
                                 visualDistance: ((GamePhoto, GamePhoto) -> Double?)?) -> Level? {
        let dated = pool
            .filter { $0.creationDate != nil }
            .sorted { $0.creationDate! < $1.creationDate! }
        let wanted = DifficultyKnob.photoCount
        guard dated.count >= 3 else { return nil }
        let count = min(wanted, dated.count)

        // A round of public photographs is built by picking eras, not by sliding a window
        // along the calendar. The window approach cannot satisfy the spacing rule at five
        // photographs — four public ones twenty-five years apart need a century between
        // the ends, and no window that tight contains them — so it simply failed, and
        // Time rounds stopped being built at all above four photographs.
        if let spread = eraLevel(dated: dated, count: count,
                                 prompts: prompts, birthDatedPacks: birthDatedPacks,
                                 recentAsks: recentAsks) {
            return spread
        }

        // How far apart the player's own photographs should sit, given how many
        // years of them there are. Somebody with five years of photographs cannot be
        // asked for a decade between two of them; somebody with thirty should never be
        // asked to choose between two afternoons. A share of the whole span it is.
        // Difficulty still has its say: the lever exists to move the gap, and a floor
        // that ignored it flattened gentlest and hardest into the same round.
        let personalGap = personalSpan.map {
            // The old lever scaled this by up to 0.6; at its default that came to 0.85.
            min(max($0 / Double(count), 120 * .day), 3 * .year) * 0.85
        }
        let decisiveGap = DifficultyKnob.chronologyDecisiveGap
        var span = DifficultyKnob.chronologyTargetGap * Double(count - 1) * 1.4
        if let personalGap {
            span = max(span, personalGap * Double(count) * 1.4)
        }
        // A set built only from the player's own photographs can be close together —
        // they remember. Once a public photograph is in it, the answer has to be
        // readable from the picture, which takes eras rather than years.
        if pool.contains(where: { !$0.isPersonal }) {
            span = max(span, DifficultyKnob.publicPhotographMinimumGap * Double(count))
        }

        // Widen the window until the library can actually fill a level.
        for attempt in 0..<6 {
            let windows = timeWindows(in: dated, span: span, minimumCount: count)
            if let level = sample(from: windows,
                                  dated: dated,
                                  count: count,
                                  decisiveGap: decisiveGap,
                                  span: span,
                                  prompts: prompts,
                                  birthDatedPacks: birthDatedPacks,
                                  personalGap: personalGap,
                                  visualDistance: visualDistance,
                                  relaxed: attempt > 0) {
                return level
            }
            span *= 2.5
        }

        // Last resort for a very thin library: spread picks across the whole timeline.
        return spreadFallback(dated: dated, count: count, prompts: prompts,
                              birthDatedPacks: birthDatedPacks)
    }

    /// Every maximal run of photos that fits inside `span`, holding at least `minimumCount`.
    private static func timeWindows(in dated: [GamePhoto],
                                    span: TimeInterval,
                                    minimumCount: Int) -> [Range<Int>] {
        var windows: [Range<Int>] = []
        var end = 0
        for start in dated.indices {
            if end < start { end = start }
            while end + 1 < dated.count,
                  dated[end + 1].creationDate!.timeIntervalSince(dated[start].creationDate!) <= span {
                end += 1
            }
            if end - start + 1 >= minimumCount {
                windows.append(start..<(end + 1))
            }
        }
        return windows
    }

    private static func sample(from windows: [Range<Int>],
                               dated: [GamePhoto],
                               count: Int,
                               decisiveGap: TimeInterval,
                               span: TimeInterval,
                               prompts: [String: String],
                               birthDatedPacks: Set<String>,
                               personalGap: TimeInterval?,
                               visualDistance: ((GamePhoto, GamePhoto) -> Double?)?,
                               relaxed: Bool) -> Level? {
        guard !windows.isEmpty else { return nil }

        // Prefer windows that include at least one of the player's own photos.
        let personalFirst = windows.shuffled().sorted { lhs, rhs in
            let l = dated[lhs].contains(where: \.isPersonal) ? 1 : 0
            let r = dated[rhs].contains(where: \.isPersonal) ? 1 : 0
            return l > r
        }

        // Three passes, each one giving up a little of what makes a good question:
        // first a set of one kind of thing from one pack ("which of these was the
        // earliest president"), then one pack, then whatever the library can manage.
        for (requireOneSubject, requireOnePack, requireOneKind, requireOneTheme) in
            [(true, true, true, true), (false, true, true, true),
             (false, false, true, true), (false, false, true, false),
             (false, false, false, false)] {
        for window in personalFirst.prefix(24) {
            var slice = Array(dated[window])
            if requireOnePack, let dominant = commonest(slice.compactMap(packID(of:))) {
                // The player's own photographs always stay; it is the public ones that
                // have to agree, so the question can name what they have in common.
                slice = slice.filter { packID(of: $0) == nil || packID(of: $0) == dominant }
            }
            if requireOneSubject {
                guard let dominant = commonest(slice.compactMap(\.subject)) else { continue }
                slice = slice.filter { $0.subject == dominant }
            }
            if requireOneTheme {
                // Occasions first: four birthdays across thirty years is a better round
                // than four assorted photographs that happen to be far apart, and the
                // question can then name the occasion.
                let dominant = commonest(slice.compactMap(\.themeID))
                if let dominant {
                    let themed = slice.filter { $0.themeID == dominant }
                    if themed.count >= count { slice = themed }
                }
            }
            if requireOneKind {
                // Faces with faces, scenery with scenery. A round of the player's own
                // photographs that mixes a wedding portrait with a beach and a birthday
                // cake asks them to compare three unlike things; a row of faces, or a
                // row of places, reads as one question.
                let faces = slice.filter(\.showsPeople)
                let rest = slice.filter { !$0.showsPeople }
                slice = faces.count >= count ? faces : (rest.count >= count ? rest : slice)
            }
            guard slice.count >= count else { continue }
            // The oldest photo in the window is the answer; it has to be clearly oldest.
            let oldest = slice[0]
            var gap = relaxed ? decisiveGap * 0.4 : decisiveGap
            if let personalGap, slice.allSatisfy(\.isPersonal) {
                gap = max(gap, personalGap)
            }
            if slice.contains(where: { !$0.isPersonal }) {
                // Never relaxed: fifty years is a floor, not a preference.
                gap = max(gap, DifficultyKnob.publicPhotographMinimumGap)
            }
            let eligible = slice.dropFirst().filter {
                $0.creationDate!.timeIntervalSince(oldest.creationDate!) >= gap
            }
            guard eligible.count >= count - 1 else { continue }

            // Spread the distractors out in time as well, so the reveal doesn't show
            // three photos from the same month (spec §5.3).
            // Time still decides who is eligible — that is what makes the answer
            // decisive. Appearance decides which of the eligible are asked, and the
            // spread then keeps them apart in time as before.
            let ranked = Resemblance.ranked(Array(eligible), like: oldest,
                                            distance: visualDistance)
            let shortlist = Array(ranked.prefix(max((count - 1) * 4, 10)))
            let spreadOut = spread(shortlist, anchor: oldest, count: count - 1)

            // Two rules, and they apply to different photographs.
            //
            // Between public photographs, a generation. The old rule held only between
            // two of the player's own, so two pack photographs could sit a year apart and
            // the round offered two wrong answers nobody could tell apart — a stranger's
            // 2014 picture against a stranger's 2016 one is not a question.
            //
            // Between the player's own, the old spacing stands: they remember, so months
            // can be enough, and demanding a generation would need a library spanning
            // seventy-five years.
            let ownGap = max(personalGap ?? 0, 20 * 3600)
            var distractors: [GamePhoto] = []
            for candidate in spreadOut + shortlist where distractors.count < count - 1 {
                guard !distractors.contains(where: { $0.id == candidate.id }) else { continue }
                let tooClose = ([oldest] + distractors).contains { chosen in
                    let apart = abs(chosen.creationDate!
                        .timeIntervalSince(candidate.creationDate!))
                    if !chosen.isPersonal && !candidate.isPersonal {
                        // Only where the years are about the subjects. "Who was born
                        // first" needs a generation between the people; "which photograph
                        // is older" between two 2015 uploads is not that question and the
                        // rule would only stop rounds being built.
                        guard chosen.dateIsAboutTheSubject,
                              candidate.dateIsAboutTheSubject else { return false }
                        return apart < DifficultyKnob.everyPublicPairMinimumGap
                    }
                    if chosen.isPersonal && candidate.isPersonal { return apart < ownGap }
                    // One of each: no floor. The player's photograph is placed by the
                    // rule below rather than by distance.
                    return false
                }
                if !tooClose { distractors.append(candidate) }
            }
            guard distractors.count == count - 1 else { continue }

            // The player's own photograph is the most recent thing in the round.
            //
            // A round is one of theirs among public ones, and the public ones are decades
            // apart and readable as eras. Their own picture is not readable that way by
            // anybody else, and it is not meant to be the answer — it is the familiar
            // thing in the middle of the unfamiliar. Putting it at the recent end makes
            // that true rather than hoped for: the answer to "which came first" is always
            // one of the public photographs.
            let assembled = [oldest] + distractors
            let publicDates = assembled.filter { !$0.isPersonal }.compactMap(\.creationDate)
            let mine = assembled.filter(\.isPersonal)
            if let latestPublic = publicDates.max(), !mine.isEmpty {
                guard mine.allSatisfy({ $0.creationDate! > latestPublic }) else { continue }
            }
            let runnerUpGap = distractors
                .map { $0.creationDate!.timeIntervalSince(oldest.creationDate!) }
                .min() ?? 0

            let chosen = assembled
            return Level(theme: .chronology,
                         prompt: prompt(for: chosen, prompts: prompts,
                                        birthDatedPacks: birthDatedPacks),
                         photos: chosen.shuffled(),
                         correctPhotoID: oldest.id,
                         curationNote: note(runnerUp: runnerUpGap, span: span,
                                            photos: [oldest] + distractors),
                         hint: eraHint(for: oldest, birthDatedPacks: birthDatedPacks))
        }
        }
        return nil
    }

    private nonisolated static func packID(of photo: GamePhoto) -> String? {
        guard case let .pack(packID, _) = photo.origin else { return nil }
        return packID
    }

    /// The value that turns up most often, or nil if there are none.
    private static func commonest(_ values: [String]) -> String? {
        var tally: [String: Int] = [:]
        for value in values { tally[value, default: 0] += 1 }
        return tally.max { $0.value < $1.value }?.key
    }

    /// Ask about the subject, not the photograph. A row of presidents deserves "Who came
    /// first?"; a row of a family's own photographs is still "Which photo is older?".
    /// The written question, in its first wording. Paths that build a round still call
    /// this; `makeLevel` rewords the finished round through `phrasing` before it leaves.
    private static func prompt(for photos: [GamePhoto],
                               prompts: [String: String],
                               birthDatedPacks: Set<String>) -> String {
        phrasing(for: photos, prompts: prompts, birthDatedPacks: birthDatedPacks,
                 recent: []).text
    }

    /// A sentence, which kind of question it is, and which wording it came from.
    struct Phrase: Sendable {
        var text: String
        var wording: String
        var ask: String
    }

    /// The ways of asking each Time question.
    ///
    /// The first of each list is the sentence the game has always used, so a round with no
    /// memory behind it reads exactly as before. The others say the same thing in other
    /// words, so a session does not ask "who was born first?" nine times over. Every one
    /// says what the dates mean — born, painted, taken — because "which is older" about a
    /// row of portraits reads as a question about the photographs.
    enum Wordings {
        static let older = ["Which photo is older?",
                            "Which of these photos was taken first?",
                            "Which photo was taken earliest?"]
        static let cameFirst = ["Which came first?",
                                "Which of these came first?"]
        static let bornFirst = ["Which {x} was born first?",
                                "Which of these {xs} was born earliest?",
                                "Of these {xs}, who was born first?"]
        static let earliest = ["Which of these was the earliest {x}?",
                               "Which {x} came first?"]
        /// Keyed by the sentence a pack's manifest gives, so a pack that writes its own
        /// question keeps it and only the packs listed here are reworded.
        static let packQuestion: [String: [String]] = [
            "Who was born first?": ["Who was born first?",
                                    "Which of these people was born first?",
                                    "Who was born earliest?"],
            "Which one was painted first?": ["Which one was painted first?",
                                             "Which of these was the earliest painting?",
                                             "Which painting is the oldest?"],
        ]
    }

    static func phrasing(for photos: [GamePhoto],
                         prompts: [String: String],
                         birthDatedPacks: Set<String>,
                         recent: [String]) -> Phrase {
        func pick(_ templates: [String], ask: String, x: String = "") -> Phrase {
            let chosen = Recency.choose(templates, kind: ask, x: x,
                                        plural: PersonRole.plural(x), recent: recent)
            return Phrase(text: chosen.text, wording: chosen.wording, ask: ask)
        }
        // Every photograph the player's own, and every one the same occasion: ask about
        // the occasion. "Which birthday came first?" is a question about their life
        // rather than about their photo library.
        if photos.allSatisfy(\.isPersonal), photos.count > 1 {
            let themes = Set(photos.compactMap(\.themeID))
            if themes.count == 1,
               let question = photos.first?.themeQuestion,
               photos.allSatisfy({ $0.themeQuestion != nil }) {
                return Phrase(text: question, wording: question, ask: "occasion")
            }
        }

        var found: Set<String> = []
        var subjects: Set<String> = []
        for photo in photos {
            // One of the player's own photographs in the set and it is their photograph
            // being placed, so ask about the photograph.
            guard case let .pack(packID, _) = photo.origin else {
                return pick(Wordings.older, ask: "older")
            }
            if let prompt = prompts[packID] { found.insert(prompt) }
            if let subject = photo.subject { subjects.insert(subject) }
        }
        // All of one kind: name the kind. This is the question someone would actually
        // ask out loud — "which of these was the earliest president" — and it tells the
        // player what to look at, which "which photo is older" never does.
        if subjects.count == 1, let subject = subjects.first,
           photos.allSatisfy({ $0.subject != nil }) {
            // When the dates are birthdays, say so: "which of these was the earliest
            // singer" sounds like a question about the photographs.
            if photos.allSatisfy({ isBirthDated($0, packs: birthDatedPacks) }) {
                return pick(Wordings.bornFirst, ask: "role", x: subject)
            }
            return pick(Wordings.earliest, ask: "role", x: subject)
        }
        // All public, but from different packs: still not "which photo", because nobody
        // is judging the photograph.
        if found.count == 1, let base = found.first {
            return pick(Wordings.packQuestion[base] ?? [base], ask: "era")
        }
        return pick(Wordings.cameFirst, ask: "mixed")
    }

    /// "The earliest one here is from the 1900s." The same shape as the Places hint —
    /// it narrows the field without naming a photograph. Only for public photographs: a
    /// decade is no help at all when the set is somebody's own pictures from one summer.
    private static func eraHint(for answer: GamePhoto,
                                birthDatedPacks: Set<String>) -> String? {
        guard !answer.isPersonal, let date = answer.creationDate else { return nil }
        let year = Calendar.current.component(.year, from: date)
        if isBirthDated(answer, packs: birthDatedPacks) {
            return "The earliest one here was born in the \(year / 10 * 10)s."
        }
        return "The earliest one here is from the \(year / 10 * 10)s."
    }

    /// Whether this photograph's date is a birthday rather than a date of exposure.
    private static func isBirthDated(_ photo: GamePhoto, packs: Set<String>) -> Bool {
        guard case let .pack(packID, _) = photo.origin else { return false }
        return packs.contains(packID)
    }

    /// Farthest-point sampling on the time axis: keeps distractors distinct from the
    /// target *and* from each other, while staying inside the difficulty window.
    private static func spread(_ candidates: [GamePhoto],
                               anchor: GamePhoto,
                               count: Int) -> [GamePhoto] {
        guard candidates.count > count else { return candidates }
        var pool = candidates.shuffled()
        var chosen = [pool.removeFirst()]

        func minimumGap(_ photo: GamePhoto, from reference: [GamePhoto]) -> TimeInterval {
            reference
                .map { abs($0.creationDate!.timeIntervalSince(photo.creationDate!)) }
                .min() ?? 0
        }

        while chosen.count < count, !pool.isEmpty {
            let reference = chosen + [anchor]
            let pick = pool.indices.max {
                minimumGap(pool[$0], from: reference) < minimumGap(pool[$1], from: reference)
            }
            chosen.append(pool.remove(at: pick ?? 0))
        }
        return chosen
    }

    /// Pick one photograph per era, oldest first, each a generation after the last.
    ///
    /// This is the round the game actually wants when public photographs are involved:
    /// four people born decades apart, or four photographs from four different eras, so
    /// the answer can be read off the picture rather than guessed. Walking the sorted
    /// list and taking the next photograph that is far enough along finds that directly,
    /// where sampling a window only finds it by luck.
    ///
    /// The player's own photograph goes on the end, as the most recent thing in the
    /// round — so it is never the answer, and the public photographs carry the question.
    private static func eraLevel(dated: [GamePhoto],
                                 count: Int,
                                 prompts: [String: String],
                                 birthDatedPacks: Set<String>,
                                 recentAsks: [String] = []) -> Level? {
        // Only packs whose years are facts about their subjects. This is the "who was
        // born first" round; a pack of photographs dated by upload has no eras to pick.
        let subjectDated = dated.filter { !$0.isPersonal && $0.dateIsAboutTheSubject }
        guard subjectDated.count >= count else { return nil }

        // One pack, and the question follows from it.
        //
        // Mixing them produced a round of three portraits and a painting, which no single
        // question fits: "who was born first" is wrong for the painting and "which was
        // painted first" is wrong for the people, so it fell back to "which occurred
        // first" — a question about nothing anybody could see. Each pack asks its own
        // question because each pack knows what its dates mean.
        let byPack = Dictionary(grouping: subjectDated) { packID(of: $0) ?? "" }
        guard let eligible = byPack.values
            .filter({ $0.count >= count })
            .shuffled()
            .max(by: { $0.count < $1.count })
        else { return nil }

        // No photograph of the player's in this round, and that is the point rather than
        // an omission.
        //
        // "Who was born first" is a question about the people in the pictures. A
        // photograph of somebody's dinner has no birth year, so the only place it could
        // sit is as a fourth option that is never the answer — and a player works that out
        // in two rounds and stops looking at it. It also made incoherent rounds: three
        // portraits and a plate of food is not one question.
        //
        // Their own photographs carry Places, Things and Occasions, where the question is
        // about what a picture shows and theirs can genuinely be the answer. And "which
        // photo is older" between two of their own is still asked — by the path below,
        // where they were there and they remember.
        let wantedPublic = count

        // Two ways of asking a pack of people: all four of one kind — "which musician was
        // born first?" — or four from anywhere in the pack. Whichever was asked longer
        // ago goes first. A kind needs a couple more members than a round holds, or every
        // round of it would be the same four people.
        // Roles are looked for across every pack of people, not only the pack this round
        // happened to draw — or half the time it draws the paintings, which have no
        // roles, and the question almost never comes up.
        let people = byPack.values.flatMap { $0 }.filter { $0.subject != nil }
        let byRole = Dictionary(grouping: people) { "\(packID(of: $0) ?? "")|\($0.subject!)" }
            .filter { $0.value.count >= wantedPublic + 2 }
        for kind in Recency.leastRecentFirst(["role", "era"], key: { $0 }, recent: recentAsks) {
            let from: [GamePhoto]
            if kind == "role" {
                guard let group = byRole.values.shuffled().first else { continue }
                from = group
            } else {
                from = eligible
            }
            if var level = spread(from, count: wantedPublic, prompts: prompts,
                                  birthDatedPacks: birthDatedPacks) {
                level.ask = kind
                return level
            }
        }
        return nil
    }

    /// Four photographs from `eligible`, each far enough in time from every other that
    /// the answer can be read from the pictures.
    private static func spread(_ eligible: [GamePhoto], count wantedPublic: Int,
                               prompts: [String: String],
                               birthDatedPacks: Set<String>) -> Level? {
        // Pick at random and keep whatever fits, rather than walking the list from a
        // starting point and taking the first photograph far enough along. Walking chose
        // nearly the same set every time — 85% of photographs came round again inside the
        // last forty rounds — because the eligible photograph after any given one is
        // almost always the same photograph.
        let gap = DifficultyKnob.everyPublicPairMinimumGap
        for _ in 0..<14 {
            var picked: [GamePhoto] = []
            for candidate in eligible.shuffled() {
                let clashes = picked.contains {
                    abs($0.creationDate!.timeIntervalSince(candidate.creationDate!)) < gap
                }
                if !clashes { picked.append(candidate) }
                if picked.count == wantedPublic { break }
            }
            guard picked.count == wantedPublic else { continue }
            picked.sort { $0.creationDate! < $1.creationDate! }

            let oldest = picked[0]
            let chosen = picked
            let runnerUp = picked.dropFirst().first
                .map { $0.creationDate!.timeIntervalSince(oldest.creationDate!) } ?? 0
            return Level(theme: .chronology,
                         prompt: prompt(for: chosen, prompts: prompts,
                                        birthDatedPacks: birthDatedPacks),
                         photos: chosen.shuffled(),
                         correctPhotoID: oldest.id,
                         curationNote: "eras · " + note(runnerUp: runnerUp, span: nil,
                                                        photos: chosen),
                         hint: eraHint(for: oldest, birthDatedPacks: birthDatedPacks))
        }
        return nil
    }

    /// Sparse-library path: take the oldest photo and spread the distractors out.
    private static func spreadFallback(dated: [GamePhoto],
                                       count: Int,
                                       prompts: [String: String],
                                       birthDatedPacks: Set<String>) -> Level? {
        guard dated.count >= 3 else { return nil }
        let oldest = dated[0]
        // Even here. A level of public photographs closer together than half a century
        // is unanswerable, and no level at all beats an unanswerable one.
        let dated = dated.enumerated().filter { index, photo in
            // Fifty years whenever either side is a public photograph — not only when
            // both are. A stranger's photograph next to one of the player's own is
            // still a stranger's photograph, and still unplaceable inside a decade.
            index == 0 || (photo.isPersonal && oldest.isPersonal)
                || !(photo.dateIsAboutTheSubject && oldest.dateIsAboutTheSubject)
                || photo.creationDate!.timeIntervalSince(oldest.creationDate!)
                    >= DifficultyKnob.publicPhotographMinimumGap
        }.map(\.element)
        guard dated.count >= count else { return nil }

        // Spread across the range first, then anything else that fits. This used to take
        // the spread picks and stop, checking each only against the oldest — so two
        // distractors could sit months apart and the round offered two wrong answers from
        // the same year.
        var order: [GamePhoto] = []
        let stride = max(1, (dated.count - 1) / (count - 1))
        var index = stride
        while index < dated.count {
            order.append(dated[index])
            index += stride
        }
        // Their own photographs first among the rest, for the same reason the resemblance
        // ranking puts them first: one of theirs against two thousand of everybody else's
        // is not a draw anybody wins.
        let rest = dated.dropFirst().shuffled()
        order += rest.filter(\.isPersonal) + rest.filter { !$0.isPersonal }

        var picks: [GamePhoto] = []
        for candidate in order where picks.count < count - 1 {
            guard !picks.contains(where: { $0.id == candidate.id }) else { continue }
            // A generation between public photographs, here as everywhere else.
            let tooClose = ([oldest] + picks).contains { chosen in
                guard !chosen.isPersonal, !candidate.isPersonal,
                      chosen.dateIsAboutTheSubject, candidate.dateIsAboutTheSubject
                else { return false }
                return abs(chosen.creationDate!.timeIntervalSince(candidate.creationDate!))
                    < DifficultyKnob.everyPublicPairMinimumGap
            }
            if !tooClose { picks.append(candidate) }
        }
        guard picks.count == count - 1 else { return nil }

        // And the player's own photograph sits at the recent end.
        let newestPublic = ([oldest] + picks).filter { !$0.isPersonal }
            .compactMap(\.creationDate).max()
        if let newestPublic {
            guard ([oldest] + picks).filter(\.isPersonal)
                .allSatisfy({ $0.creationDate! > newestPublic }) else { return nil }
        }
        let runnerUp = picks.map { $0.creationDate!.timeIntervalSince(oldest.creationDate!) }.min() ?? 0
        return Level(theme: .chronology,
                     prompt: prompt(for: [oldest] + picks, prompts: prompts,
                                    birthDatedPacks: birthDatedPacks),
                     photos: ([oldest] + picks).shuffled(),
                     correctPhotoID: oldest.id,
                     curationNote: "sparse library · " + note(runnerUp: runnerUp,
                                                              span: nil,
                                                              photos: [oldest] + picks))
    }

    private static func note(runnerUp: TimeInterval,
                             span: TimeInterval?,
                             photos: [GamePhoto]) -> String {
        let personal = photos.filter(\.isPersonal).count
        var parts = ["gap to runner-up \(Self.describe(runnerUp))"]
        if let span { parts.append("window \(Self.describe(span))") }
        parts.append("\(personal) personal + \(photos.count - personal) pack")
        return parts.joined(separator: " · ")
    }

    static func describe(_ interval: TimeInterval) -> String {
        let years = Int(interval / .year)
        let months = Int((interval - Double(years) * .year) / (30.44 * .day))
        if years > 0 { return months > 0 ? "\(years)y \(months)m" : "\(years)y" }
        if months > 0 { return "\(months)m" }
        return "\(max(1, Int(interval / .day)))d"
    }
}

enum PlacesCurator {

    /// How alike two photographs may look before one cannot stand beside the other.
    ///
    /// Well above the duplicate threshold, because this is not about the same moment
    /// twice: it is about a round of four photographs that could each be the answer.
    static let tooAlike = 0.32

    /// How far apart two places have to be before they count as different places.
    ///
    /// Well beyond a day's errands: the point is that the player should never have to
    /// tell one suburb from the next one along, which is a question about postcodes
    /// rather than about anywhere they remember being.
    static let minimumSeparation: CLLocationDistance = 120_000

    /// The ways of asking a Places question. The first of each is what the game has
    /// always said.
    enum Wordings {
        static let place = ["Which photo is from {x}?",
                            "Which one was taken in {x}?",
                            "Which of these is in {x}?"]
        static let landmark = ["Which photo is from {x}?",
                               "Which one shows {x}?",
                               "Which of these is {x}?"]
    }

    /// Two ways of asking about places — by where a photograph was taken, and by which
    /// landmark it shows — tried longest-unasked first, then worded so the same sentence
    /// is not asked twice running.
    static func makeLevel(pool: [GamePhoto],
                          prompts: [String: String] = [:],
                          recentPlaces: [String] = [],
                          recentAsks: [String] = [],
                          recentWordings: [String] = [],
                          visualDistance: ((GamePhoto, GamePhoto) -> Double?)? = nil) -> Level? {
        for kind in Recency.leastRecentFirst(["place", "landmark"], key: { $0 },
                                             recent: recentAsks) {
            if kind == "landmark" {
                if let level = landmarkLevel(pool: pool, recentPlaces: recentPlaces,
                                             recentWordings: recentWordings) {
                    return level
                }
                continue
            }
            guard var level = placeLevel(pool: pool, recentPlaces: recentPlaces,
                                         visualDistance: visualDistance),
                  let asked = level.focusTag else { continue }
            let chosen = Recency.choose(Wordings.place, kind: "place", x: asked,
                                        recent: recentWordings)
            level.prompt = chosen.text
            level.wording = chosen.wording
            level.ask = "place"
            return level
        }
        return nil
    }

    /// "Which photo is from the Eiffel Tower?"
    ///
    /// The landmarks pack names every photograph, and a place is recognised by what is in
    /// it as often as by where it is: nobody needs to know that the tower is in the
    /// seventh arrondissement to pick it out. So this asks for the landmark itself, beside
    /// three other landmarks — and, where the round has room for one, a photograph of the
    /// player's own that was taken nowhere near it.
    ///
    /// "Nowhere near" is the rule that keeps the question honest. Their own holiday
    /// photograph taken under the Eiffel Tower is a second right answer, and nothing on
    /// the screen would say which was meant.
    private nonisolated static func landmarkLevel(pool: [GamePhoto], recentPlaces: [String],
                                                  recentWordings: [String]) -> Level? {
        let wanted = DifficultyKnob.photoCount
        let landmarks = pool.filter {
            !$0.isPersonal && !($0.title ?? "").isBlank && $0.coordinate != nil
                && !($0.placeName ?? "").isBlank
        }
        guard landmarks.count >= wanted else { return nil }
        let stale = Set(recentPlaces)
        let targets = landmarks.shuffled().sorted { lhs, rhs in
            (stale.contains(lhs.title!) ? 1 : 0) < (stale.contains(rhs.title!) ? 1 : 0)
        }

        for target in targets.prefix(12) {
            guard let title = target.title, let here = target.coordinate else { continue }

            // One of the player's own, far enough away that it cannot show the landmark.
            let theirs = pool.filter(\.isPersonal).filter { photo in
                guard let there = photo.coordinate else { return false }
                return there.distance(to: here) > Self.landmarkClearance
            }.randomElement()
            let publicWanted = wanted - (theirs == nil ? 0 : 1)
            let others = landmarks
                .filter { $0.id != target.id && $0.title != title }
                .shuffled()
                .prefix(publicWanted - 1)
            guard others.count == publicWanted - 1 else { continue }

            let photos = ([target] + others + (theirs.map { [$0] } ?? [])).shuffled()
            let chosen = Recency.choose(Wordings.landmark, kind: "landmark",
                                        x: Self.inSentence(title), recent: recentWordings)

            // A hint that narrows the field without naming the answer: its country, when
            // no other photograph in the round is from there too.
            let country = target.countryName?.nilIfBlank
            let sharesCountry = photos.contains { $0.id != target.id && $0.countryName == country }
            let hint = (country != nil && !sharesCountry) ? "It's in \(country!)." : nil

            return Level(theme: .places,
                         prompt: chosen.text,
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "landmark · \(title) · "
                            + "\(landmarks.count) landmarks in play",
                         focusTag: title,
                         hint: hint,
                         ask: "landmark",
                         wording: chosen.wording)
        }
        return nil
    }

    /// How far from a landmark one of the player's own photographs has to have been
    /// taken before it cannot be of that landmark. A few kilometres takes in anything
    /// with the landmark on the horizon.
    static let landmarkClearance: CLLocationDistance = 5_000

    /// "The Eiffel Tower" in the middle of a sentence: "the Eiffel Tower".
    nonisolated static func inSentence(_ title: String) -> String {
        title.hasPrefix("The ") ? "the " + title.dropFirst(4) : title
    }

    /// Exactly one photo from the target place, plus plausible distractors from
    /// elsewhere. Harder levels draw those distractors from nearby places (spec §5.2–5.3).
    private static func placeLevel(pool: [GamePhoto],
                                   recentPlaces: [String],
                                   visualDistance: ((GamePhoto, GamePhoto) -> Double?)?) -> Level? {
        // `placeName != nil` is not enough: a photograph whose place resolved to ""
        // passed that test, grouped itself under an empty key, and asked "Which photo is
        // from ?". A name has to say something before a question can be built on it.
        let named = pool.filter { !($0.placeName ?? "").isBlank && $0.coordinate != nil }
        let byPlace = Dictionary(grouping: named) { $0.placeName! }
        guard byPlace.count >= 3 else { return nil }

        let wanted = DifficultyKnob.photoCount
        let count = min(wanted, byPlace.count)

        // Somewhere the player actually went, rather than somewhere they passed
        // through. One photograph at a place is a car park, a petrol station, a shopping
        // centre next to the place they meant to visit; several is a visit. Pack
        // photographs are exempt — a landmark is a landmark on one photograph.
        //
        // And so is their one photograph, when one is all the pool holds. Rounds are three
        // parts public to one part personal now, so a pool arrives with a single
        // photograph of theirs in it: its place has a count of one, this rule threw it out
        // every time, and Places produced three hundred rounds in a row without a single
        // one of their photographs in. Whether that place was really visited is decided
        // before the pool is built, where the whole library can be counted — see
        // `LevelGenerator.pool(for:)`.
        let onlyOneOfTheirs = named.count(where: \.isPersonal) <= 1
        let visited = byPlace.filter { _, photos in
            photos.contains(where: { !$0.isPersonal }) || photos.count >= 3
                || (onlyOneOfTheirs && photos.contains(where: \.isPersonal))
        }
        let usable = visited.count >= 3 ? visited : byPlace

        // Anything asked about lately goes to the back, then the player's own photos come
        // first. Without the first half of that rule, a library whose personal photographs
        // cluster in one state asks about that state nearly every round: the ordering
        // below is stable, the same place keeps winning it, and the game feels like it
        // knows one question. Things has had this memory for weeks; Places never got it.
        let stale = Set(recentPlaces)
        let placeNames = usable.keys.shuffled().sorted { lhs, rhs in
            let lFresh = stale.contains(lhs) ? 0 : 1
            let rFresh = stale.contains(rhs) ? 0 : 1
            if lFresh != rFresh { return lFresh > rFresh }
            let l = usable[lhs]!.contains(where: \.isPersonal) ? 1 : 0
            let r = usable[rhs]!.contains(where: \.isPersonal) ? 1 : 0
            return l > r
        }

        for targetName in placeNames.prefix(12) {
            guard let target = usable[targetName]?.randomElement(),
                  let targetCoordinate = target.coordinate else { continue }

            // Other places, nearest first.
            let others = byPlace
                .filter { $0.key != targetName }
                .compactMap { name, photos -> (String, GamePhoto, CLLocationDistance)? in
                    guard let photo = photos.randomElement(),
                          let coordinate = photo.coordinate else { return nil }
                    return (name, photo, targetCoordinate.distance(to: coordinate))
                }
                // Two towns in the same county are the same place to anybody being
                // asked: McLean, Fairfax and Springfield are fifteen miles apart and
                // nobody sorts their own photographs by which of them they were in.
                // A round needs answers that differ at the scale people think at.
                .filter { $0.2 >= Self.minimumSeparation }
                .filter { widerPart(of: $0.0) == nil
                            || widerPart(of: $0.0) != widerPart(of: targetName) }
                .filter { candidate in
                    guard let theirs = candidate.1.countryCode,
                          let ours = target.countryCode else { return true }
                    return theirs != ours || !isAbroad(target)
                }
                .sorted { $0.2 < $1.2 }

            guard others.count >= count - 1 else { continue }

            // Hard levels want the nearer neighbours; gentle levels want far-flung ones.
            // "Near" is now never nearer than the floor above.
            let nearby = others.filter { $0.2 <= DifficultyKnob.placesNeighbourRadius }
            let candidates = nearby.count >= count - 1 ? nearby : others
            // Geography picks the shortlist — nearer neighbours for a hard round, far
            // ones for a gentle one — and appearance picks from within it. The window is
            // wider than the number needed, because candidates are dropped below when
            // they sit too close to one already chosen.
            let window = max((count - 1) * 3, 8)
            // The far end. The lever used to take the near end above its halfway point,
            // which it spent most of its life below anyway.
            let shortlist = Array(candidates.suffix(window))
            // Always the ones that look most like the answer, whatever the difficulty.
            //
            // Elsewhere the difficulty knob decides whether distractors resemble the
            // answer; here it must not. Three landscapes beside one photograph of a
            // living room is not a hard question or an easy one, it is an incoherent
            // one — and Places already has its own lever in how near the other places
            // are.
            // Always the alike end here. Places picks its distractors by distance on the
            // map, and a round of four photographs that look nothing like each other is
            // not a hard question or an easy one, it is an incoherent one.
            let ordered = Resemblance.ranked(shortlist.map(\.1), like: target,
                                             distance: visualDistance,
                                             noCloserThan: Self.tooAlike,
                                             alikeChance: 1)
            let byID = Dictionary(shortlist.map { ($0.1.id, $0) },
                                  uniquingKeysWith: { first, _ in first })

            // Every photograph in the round has to be far from every other one, not
            // just from the answer. Three towns in one county are still three towns in
            // one county when the fourth photograph is in Chicago.
            var distractors: [(String, GamePhoto, CLLocationDistance)] = []
            for photo in ordered {
                guard distractors.count < count - 1, let candidate = byID[photo.id] else {
                    continue
                }
                let clashes = distractors.contains { chosen in
                    guard let a = chosen.1.coordinate, let b = candidate.1.coordinate else {
                        return false
                    }
                    if a.distance(to: b) < Self.minimumSeparation { return true }
                    if let first = chosen.1.countryCode, let second = candidate.1.countryCode,
                       first == second, isAbroad(chosen.1) {
                        // Both abroad and both in the same country: the question would
                        // name that country and have two answers.
                        return true
                    }
                    let region = widerPart(of: chosen.0)
                    return region != nil && region == widerPart(of: candidate.0)
                }
                if !clashes { distractors.append(candidate) }
            }

            guard distractors.count == count - 1 else { continue }

            let nearest = distractors.map(\.2).min() ?? 0
            let photos = ([target] + distractors.map(\.1)).shuffled()
            let personal = photos.filter(\.isPersonal).count

            // Ask at the coarsest name that still points at one photograph. "McLean"
            // means nothing to most people; "Virginia" means something to everyone, and
            // is just as exact as long as no other photograph in the round is from
            // Virginia too.
            let chosenNames = [targetName] + distractors.map(\.0)
            let chosen = [target] + distractors.map(\.1)
            guard let asked = askedName(for: target, named: targetName,
                                        among: chosen, named: chosenNames)
            else { continue }

            return Level(theme: .places,
                         prompt: "Which photo is from \(asked)?",
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "nearest distractor \(Int(nearest / 1000))km · "
                            + "\(byPlace.count) places known · "
                            + "\(personal) personal + \(photos.count - personal) pack",
                         // What the question asked about, so the next round can avoid
                         // asking it again.
                         focusTag: asked,
                         // The hint names the wider place. When the question already
                         // asked by the wider place there is nothing left to add.
                         hint: asked == shortName(targetName)
                            ? regionHint(for: targetName) : nil)
        }
        return nil
    }

    /// The name to ask by: the region when only one photograph in the round comes from
    /// it, the town otherwise.
    ///
    /// Reverse geocoding hands back the town — "McLean, VA" — and a town is the one part
    /// of an address most people cannot place. The region is recognisable and, when it
    /// is unique among the four, exactly as precise.
    private nonisolated static func askedName(for photo: GamePhoto,
                                              named place: String,
                                              among chosen: [GamePhoto],
                                              named names: [String]) -> String? {
        let rivals = chosen.filter { $0.id != photo.id }

        // Abroad, ask about the country. Nobody outside Iceland can place Vík or
        // Húsavík, and "which photo is from Iceland" is the question they were going to
        // answer anyway — but only when exactly one photograph in the round is from there.
        //
        // "Exactly one" is the whole rule, and it used to be tested against `countryName`,
        // which only the player's own photographs had: reverse geocoding fills it in and
        // pack photographs were never reverse geocoded. So every pack photograph read as
        // "not from that country", and a round asked which photograph was from the United
        // States while holding three American landmarks. Packs now carry a country, and a
        // country nobody recorded still counts against asking — an unknown country is not
        // a different one.
        if let country = photo.countryName, !country.isBlank, isAbroad(photo) {
            let fromSameCountry = rivals.count { $0.countryName == country }
            let anyUnknown = rivals.contains { ($0.countryName ?? "").isBlank }
            if fromSameCountry == 0 && !anyUnknown { return country }
        }

        guard let region = widerPart(of: place) else {
            // Nothing finer than one word — a city with no state or country beside it.
            // Asking by it is fine as long as no other photograph carries the same name.
            return names.contains(where: { $0 != place && shortName($0) == shortName(place) })
                ? nil : shortName(place).nilIfBlank
        }
        let others = names.filter { $0 != place }
        guard !others.contains(where: { widerPart(of: $0) == region }) else {
            return shortName(place).nilIfBlank
        }
        // The region might itself be a country. Reverse geocoding hands back "Charlotte,
        // United States" as readily as "Charlotte, NC", and then asking by the "region"
        // asks by the country — which another photograph in the round can answer to while
        // carrying a region of its own. A landmark filed under "San Francisco, California"
        // is in the United States too, and the region comparison above cannot see it.
        let asked = spelledOut(region)
        // A rival counts as answering to this name whether it carries the country as a
        // field or only inside its place string. The test used to look at `countryName`
        // alone, and a landmark recorded as "Statue of Liberty, New York, United States"
        // with no country field of its own sailed past it — so a round asked which
        // photograph was from the United States while holding three American landmarks.
        let claims = { (photo: GamePhoto) -> Bool in
            if photo.countryName == asked || photo.countryName == region { return true }
            guard let theirs = photo.placeName else { return false }
            return theirs.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0 == region || spelledOut($0) == asked }
        }
        if rivals.contains(where: claims) {
            return shortName(place).nilIfBlank
        }
        return asked.nilIfBlank
    }

    /// Whether this photograph was taken outside the country the device is set to.
    ///
    /// At home the useful name is the state or county — "Virginia" means something to
    /// somebody who lives there. Abroad it is the country, and the town means nothing.
    private nonisolated static func isAbroad(_ photo: GamePhoto) -> Bool {
        guard let code = photo.countryCode else { return false }
        guard let home = Locale.current.region?.identifier else { return true }
        return code.caseInsensitiveCompare(home) != .orderedSame
    }

    private nonisolated static func widerPart(of place: String) -> String? {
        let parts = place.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1, let wider = parts.last, wider != parts[0] else { return nil }
        return wider
    }

    /// "Giza, Egypt" -> "Giza is in Egypt." Nil when the place is stored as a bare
    /// name, which is what personal photos usually give after reverse geocoding a
    /// single-part locality.
    static func regionHint(for place: String) -> String? {
        let parts = place.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1, let wider = parts.last, wider != parts[0] else { return nil }
        return "\(shortName(place)) is in \(spelledOut(wider))."
    }

    /// Reverse geocoding hands back "Inverness, CA", and "CA" on its own is no help to
    /// somebody reading it out loud — it could be California or Canada. Two-letter codes
    /// that are US states are spelled out; anything else short is left as it is.
    private nonisolated static func spelledOut(_ region: String) -> String {
        guard region.count == 2 else { return region }
        return states[region.uppercased()] ?? region
    }

    private nonisolated static let states = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming", "DC": "Washington, D.C.",
    ]

    /// "Rome, Italy" reads better in a question than the full formatted string.
    static func shortName(_ name: String) -> String {
        name.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? name
    }
}

enum ObjectsCurator {

    /// "It's a mammal." — the kind of thing the answer is.
    ///
    /// Only worth saying when it narrows the round down. Four mammals against each other
    /// are not separated by being told the answer is a mammal, and a hint that rules
    /// nothing out is noise on a screen that should be quiet.
    private nonisolated static func namedSubjectHint(for answer: GamePhoto,
                                                     among photos: [GamePhoto]) -> String? {
        guard let kind = answer.subjectKind, !kind.isEmpty else { return nil }
        // Shown only when it points at one photograph. The test used to be whether
        // *every* other photograph shared the hint, which is far too lenient: "it's a
        // mammal" beside three photographs of which two are mammals still sends somebody
        // to a picture that is not the answer, and it does it with the app's authority
        // behind it. One other sharing it is already one too many.
        let shared = photos.contains {
            $0.id != answer.id && $0.subjectKind?.caseInsensitiveCompare(kind) == .orderedSame
        }
        guard !shared else { return nil }
        // "It's a French mime" is the wrong word for a person. A pack dated by birth is a
        // pack of people, and "they" is the honest pronoun when the app does not know
        // anybody's — it is right for one person and reads naturally for a group.
        return answer.dateIsBirth ? "They were \(kind)." : "It's \(kind)."
    }


    /// How much more like the thing the answer has to look than the runner-up does.
    ///
    /// CLIP's similarities sit in a narrow band, so this is small in absolute terms and
    /// decisive in practice: below it, two photographs are equally good answers and the
    /// round is thrown away rather than asked.
    static let secondOpinionMargin = 0.005

    /// How much a distractor may look like the thing being asked about.
    ///
    /// The rule next to this one is *relative*: the answer has to beat every distractor
    /// at being food by a margin. That is not the same as the distractors not being food,
    /// and the difference is a real round somebody played — one photograph of a meal, and
    /// another of a cat sitting beside a plate of dinner. The first scored slightly
    /// higher, so the round shipped, and the player was asked which of two photographs of
    /// food had food in it.
    ///
    /// So a distractor now has to be below the level at which the thing is *present at
    /// all*, judged on its own rather than against the answer. Set just under the floor
    /// the themes model uses to say a concept is there (0.040), because the question is
    /// no longer "is this the most foodlike picture here" but "is there any food in it".
    static let distractorCeiling = 0.034

    /// One photo that is plainly of the thing, plus distractors that plainly are not
    /// (spec §5.3, §6.3). Harder levels pull those distractors from the same family, so
    /// "which one has a dog" sits next to a cat and a horse.
    ///
    /// The question comes from the themes model, not from Apple's classifier.
    ///
    /// The classifier names what it sees from a fixed taxonomy and cannot be corrected;
    /// it called a cat a dog and a table of cold cuts fruit, and every question built on
    /// one of those was wrong before anybody saw it. The themes model reads the whole
    /// picture against a written list, says how strongly, and can be argued with by
    /// editing a sentence. So it chooses the question now, and the classifier keeps the
    /// job it is good at: saying a photograph *might* contain the thing, which is all a
    /// distractor has to be cleared of.
    /// The kinds of question a set of photographs can carry.
    ///
    /// Named here rather than left implicit in the order of a few `if let`s, because the
    /// order is now a decision — see `order(leastRecent:)`.
    enum Ask: String, CaseIterable, Sendable {
        /// "Which one shows Louis Pasteur?"
        case named
        /// "Which one was painted by Leonardo da Vinci?"
        case artist
        /// "Which photo is from your album?"
        case mine
        /// "Which photo has a dog in it?"
        case category
        /// "Which one is a mammal?" — of the animals pack, by what kind of animal it is.
        case kind

        /// The kinds to try, the longest-unasked first.
        ///
        /// `recent` is most-recent-first, so a kind's position in it is how fresh it is.
        /// Anything absent has not been asked in living memory and goes first.
        static func order(leastRecent recent: [String]) -> [Ask] {
            // Ties — kinds never asked — in alphabetical order, which is the order this
            // rotation has always used when there is nothing to go on.
            Recency.leastRecentFirst(allCases.sorted { $0.rawValue < $1.rawValue },
                                     key: \.rawValue, recent: recent)
        }
    }

    static func makeLevel(pool: [GamePhoto],
                          prompts: [String: String] = [:],
                          recentCategories: [String] = [],
                          recentAsks: [String] = [],
                          recentWordings: [String] = [],
                          visualDistance: ((GamePhoto, GamePhoto) -> Double?)? = nil,
                          conceptScore: ((GamePhoto, String) -> Double?)? = nil,
                          bestConcept: ((GamePhoto) -> String?)? = nil) -> Level? {
        let wanted = DifficultyKnob.photoCount

        // Four ways of asking about a set of photographs, tried in turn.
        //
        // `namedSubjectLevel` used to be tried first and unconditionally, which meant a
        // pack that names its photographs was *only* ever asked about by name: the other
        // questions existed and never came up. The order is rotated instead, by how long
        // it has been since each kind was last asked, so a session moves between them
        // rather than settling on one. Each still declines when it cannot build a fair
        // round, and the next kind is tried.
        for kind in Ask.order(leastRecent: recentAsks) {
            let level: Level?
            switch kind {
            case .named:
                level = namedSubjectLevel(pool: pool, wanted: wanted,
                                          visualDistance: visualDistance)
            case .artist:
                level = artistLevel(pool: pool, wanted: wanted,
                                    visualDistance: visualDistance)
            case .mine:
                level = ownPhotoLevel(pool: pool, wanted: wanted)
            case .category:
                level = categoryLevel(pool: pool, wanted: wanted, prompts: prompts,
                                      recentCategories: recentCategories,
                                      visualDistance: visualDistance,
                                      conceptScore: conceptScore,
                                      bestConcept: bestConcept)
            case .kind:
                level = kindLevel(pool: pool, wanted: wanted)
            }
            if var level {
                level.ask = kind.rawValue
                reword(&level, as: kind, recent: recentWordings)
                return level
            }
        }
        return nil
    }

    /// The ways of asking a Things question. The first of each is what the game has
    /// always said. `{x}` is the thing asked about.
    enum Wordings {
        /// A proper name: a person, a painting.
        static let namedProper = ["Which one shows {x}?",
                                  "Which of these is {x}?",
                                  "Can you find {x}?"]
        /// A common noun, with its article: "a lion", "a horse chestnut".
        static let namedCommon = ["Which photo has {x} in it?",
                                  "Which one shows {x}?",
                                  "Which of these is {x}?"]
        static let artist = ["Which one was painted by {x}?",
                             "Which of these is by {x}?",
                             "Which painting is by {x}?"]
        static let album = ["Which photo is from your album?"]
        static let category = ["Which photo has {x} in it?",
                               "Which one shows {x}?",
                               "Which of these has {x} in it?"]
        /// Questions about what kind of thing something is — "which one is a mammal?".
        /// They carry no hint: the only hint there is to give is the answer's kind, and
        /// the question has just said it.
        static let kind = ["Which one is {x}?",
                           "Which of these is {x}?",
                           "Can you spot {x}?"]
    }

    /// Puts the finished round into one of its kind's wordings.
    ///
    /// Done after the round is built rather than inside each builder, so every kind is
    /// worded by the same rule: the wording used longest ago, across all the kinds, since
    /// "which one shows …" reads the same whether it is about a lion or Louis Pasteur.
    private nonisolated static func reword(_ level: inout Level, as kind: Ask,
                                           recent: [String]) {
        guard let answer = level.photos.first(where: { $0.id == level.correctPhotoID })
        else { return }
        let chosen: (text: String, wording: String)
        switch kind {
        case .named:
            guard let name = answer.askableName else { return }
            // A pack that asks "which photo has {name} in it?" names common nouns, which
            // want their article — it was asking "which photo has lion in it?".
            if answer.namedSubjectPrompt?.contains("in it") == true {
                chosen = Recency.choose(Wordings.namedCommon, kind: "named",
                                        x: "\(article(for: name)) \(name)", recent: recent)
            } else {
                chosen = Recency.choose(Wordings.namedProper, kind: "named", x: name, recent: recent)
            }
        case .artist:
            guard let artist = answer.creator else { return }
            chosen = Recency.choose(Wordings.artist, kind: "artist", x: artist, recent: recent)
        case .mine:
            chosen = Recency.choose(Wordings.album, kind: "mine", recent: recent)
        case .category:
            // A category with a question of its own keeps it, reworded only in the one
            // way that cannot change its meaning.
            let base = level.prompt
            if base.hasPrefix("Which photo has "), base.hasSuffix(" in it?") {
                let subject = String(base.dropFirst("Which photo has ".count)
                                         .dropLast(" in it?".count))
                chosen = Recency.choose(Wordings.category, kind: "category", x: subject, recent: recent)
            } else {
                let other = base.replacingOccurrences(of: "Which one is", with: "Which of these is")
                chosen = Recency.choose(other == base ? [base] : [base, other], kind: "category",
                                        recent: recent)
            }
        case .kind:
            guard let group = level.focusTag else { return }
            chosen = Recency.choose(Wordings.kind, kind: "kind", x: group, recent: recent)
            level.hint = nil
        }
        level.prompt = chosen.text
        level.wording = chosen.wording
    }

    /// "Which one is a mammal?"
    ///
    /// The animals pack records what kind of animal each photograph is — a mammal, a bird,
    /// an insect, a reptile — and until now used it only for a hint. It is a question in
    /// its own right, and a different one from naming the animal: somebody who cannot say
    /// which is the pangolin can still say which one is not a bird.
    ///
    /// One of the kind asked about, three of other kinds, and nothing of the player's own:
    /// one of their photographs might well have a dog in it, and then the round would have
    /// two mammals and two answers. Every kind is equally likely to be asked, so the three
    /// spiders get their turn beside the two hundred and sixty-five birds.
    private nonisolated static func kindLevel(pool: [GamePhoto], wanted: Int) -> Level? {
        // Only packs whose kinds are kinds of creature. Famous Faces keeps a sentence
        // about each person in the same field, and "which one is an American novelist"
        // is a different question with a different answer.
        let creatures = pool.filter {
            !$0.isPersonal && !$0.dateIsBirth && $0.subjectKind?.nilIfBlank != nil
                && $0.title?.nilIfBlank != nil
        }
        let byKind = Dictionary(grouping: creatures) { $0.subjectKind! }
        guard byKind.count >= 2 else { return nil }

        for kind in byKind.keys.shuffled() {
            guard let target = byKind[kind]?.randomElement() else { continue }
            let others = creatures.filter { $0.subjectKind != kind }.shuffled()
            guard others.count >= wanted - 1 else { continue }
            let photos = ([target] + others.prefix(wanted - 1)).shuffled()
            return Level(theme: .objects,
                         prompt: "Which one is \(kind)?",
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "kind · \(kind) · \(byKind.count) kinds in play",
                         focusTag: kind,
                         hint: nil)
        }
        return nil
    }

    /// "Which photo has a dog in it?" — the question about what is in the picture.
    ///
    /// Lifted out of `makeLevel` so every kind of question can be tried in whatever
    /// order the rotation asks for. It used to be the tail of that function, which
    /// meant it could only ever run last, and a rotation that reached it had nowhere
    /// left to go: any kind ordered after it was skipped entirely.
    private nonisolated static func categoryLevel(
        pool: [GamePhoto], wanted: Int, prompts: [String: String],
        recentCategories: [String],
        visualDistance: ((GamePhoto, GamePhoto) -> Double?)?,
        conceptScore: ((GamePhoto, String) -> Double?)?,
        bestConcept: ((GamePhoto) -> String?)?) -> Level? {

        // Grouped by what the themes model says each photograph is, where it has
        // looked. A library it has not reached yet still plays, on the classifier's
        // tags, rather than the game going quiet while a scan finishes.
        var byCategory: [String: [GamePhoto]] = [:]
        let read = pool.filter { $0.conceptID != nil }
        if !read.isEmpty {
            for photo in read {
                guard let concept = photo.conceptID,
                      ObjectCatalog.category(id: concept) != nil else { continue }
                byCategory[concept, default: []].append(photo)
            }
        } else {
            for photo in pool {
                for tag in photo.objectTags where ObjectCatalog.category(id: tag) != nil {
                    byCategory[tag, default: []].append(photo)
                }
            }
        }
        guard !byCategory.isEmpty else { return nil }

        // Anything asked about lately goes to the back of the queue, then the player's
        // own photos come first. Without this a session asked about pumpkins three times
        // and Diwali lamps twice: the photographs were different each time, but the
        // *question* was the same, which is what anybody actually notices.
        let stale = Set(recentCategories)
        let candidates = byCategory.keys
            .filter { !ObjectCatalog.tooIncidentalToAskAbout.contains($0) }
            .shuffled().sorted { lhs, rhs in
            let lFresh = stale.contains(lhs) ? 0 : 1
            let rFresh = stale.contains(rhs) ? 0 : 1
            if lFresh != rFresh { return lFresh > rFresh }
            let l = byCategory[lhs]!.contains(where: \.isPersonal) ? 1 : 0
            let r = byCategory[rhs]!.contains(where: \.isPersonal) ? 1 : 0
            return l > r
        }

        let preferSameFamily = Double.random(in: 0...1) < DifficultyKnob.objectsSameFamilyChance

        for categoryID in candidates.prefix(12) {
            guard let category = ObjectCatalog.category(id: categoryID) else { continue }
            // Of the photographs read as this thing, ask about the clearest one — and
            // never about a portrait.
            //
            // A picture of somebody standing on a boat is a picture of *them*. The boat
            // may well be the strongest thing the model can name in it, and the player
            // still has to hunt the frame for a bit of rail behind a shoulder to know why
            // their own photograph is the answer. A face this large means the photograph
            // is about the face, whatever else is in it.
            let holders = (byCategory[categoryID] ?? [])
                .filter { !$0.isAPortrait }
                .sorted { $0.conceptScore > $1.conceptScore }
            guard let target = holders.first.map({ best in
                // Among those within a whisker of the best, pick at random, or the same
                // photograph would be the answer every time the question came up.
                holders.filter { $0.conceptScore >= best.conceptScore - 0.01 }
                    .randomElement() ?? best
            }) else { continue }

            // A distractor must not even arguably contain the target category —
            // the classifier's hint counts against it, and so does the themes model's
            // reading.
            let clean = pool.filter {
                $0.id != target.id
                    && !$0.possibleObjectTags.contains(categoryID)
                    && $0.conceptID != categoryID
            }
            // Prefer photos that clearly show *something* — a blank wall is filler.
            // Either model vouching for it is enough.
            let recognisable = clean.filter { !$0.objectTags.isEmpty || $0.conceptID != nil }

            let sameFamily = recognisable.filter { photo in
                photo.objectTags.contains {
                    ObjectCatalog.category(id: $0)?.family == category.family
                }
            }
            let otherFamily = recognisable.filter { photo in
                !photo.objectTags.contains {
                    ObjectCatalog.category(id: $0)?.family == category.family
                }
            }

            let preferred: [GamePhoto]
            if preferSameFamily {
                preferred = sameFamily.count >= wanted - 1 ? sameFamily : recognisable
            } else {
                preferred = otherFamily.count >= wanted - 1 ? otherFamily : recognisable
            }

            // One photo per category among the distractors, so the reveal reads well.
            var distractors: [GamePhoto] = []
            var usedTags = Set([categoryID])
            // Of the photographs that are safely not the answer, take the ones that
            // look most like it on a hard round and least like it on a gentle one.
            let ordered = Resemblance.ranked(preferred, like: target,
                                             distance: visualDistance)
            for photo in ordered where distractors.count < wanted - 1 {
                let tags = photo.objectTags
                guard tags.isDisjoint(with: usedTags) else { continue }
                distractors.append(photo)
                usedTags.formUnion(tags)
            }
            // Top up from photographs the classifier has actually looked at and found
            // something in — never from untagged ones.
            //
            // This used to fall back to any "clean" photo, and an untagged photo is clean
            // only because nothing is known about it: it may be pending classification,
            // or the classifier may have failed on it, or it may be full of the very
            // thing being asked about. That is how "which photo has a tree in it?" came
            // to sit a Christmas tree next to a photograph of a bare winter wood and call
            // the wood wrong. Absence of evidence was being read as evidence of absence.
            if distractors.count < wanted - 1 {
                let topUp = recognisable.shuffled().sorted {
                    $0.objectTags.intersection(usedTags).count
                        < $1.objectTags.intersection(usedTags).count
                }
                for photo in topUp where distractors.count < wanted - 1 {
                    guard !distractors.contains(photo) else { continue }
                    distractors.append(photo)
                    usedTags.formUnion(photo.objectTags)
                }
            }
            // Better no level than an ambiguous one: if the library cannot supply enough
            // photographs that are known not to contain the subject, this category is
            // skipped and the next one is tried.
            guard distractors.count == wanted - 1 else { continue }

            // A second opinion, from a model that has never seen the classifier's tags.
            //
            // The classifier called a table of cold cuts "fruit", and missed the food
            // sitting next to a cat — one false yes and one false no, and between them
            // they make a question with no answer or with two. So before a round is
            // allowed out: the photograph being asked about has to look more like the
            // thing than any other photograph in the round does, by a clear margin.
            if let conceptScore {
                let targetScore = conceptScore(target, categoryID)
                let rivals = distractors.compactMap { conceptScore($0, categoryID) }
                if let targetScore, rivals.count == distractors.count {
                    guard let closest = rivals.max(),
                          targetScore > closest + Self.secondOpinionMargin else { continue }
                    // And no distractor may plainly contain the thing, however far ahead
                    // the answer is. Beating the others is not the same as their not
                    // having any.
                    guard closest < Self.distractorCeiling else { continue }
                }
            }
            // Stronger still: of everything this game can ask about, the answer has to
            // look most like the thing being asked about, and no distractor may.
            //
            // The margin above only says the answer beats the others at being a dog;
            // a photograph of a cat beats a plate of food at being a dog. This says the
            // photograph *is* a dog, in the opinion of a model that never saw the tag.
            if let bestConcept {
                if let targetBest = bestConcept(target) {
                    guard targetBest == categoryID else { continue }
                }
                guard !distractors.contains(where: { bestConcept($0) == categoryID }) else {
                    continue
                }
            }

            let photos = ([target] + distractors).shuffled()
            let personal = photos.filter(\.isPersonal).count
            let familyNote = preferSameFamily && sameFamily.count >= wanted - 1
                ? "same-family distractors"
                : "mixed distractors"

            return Level(theme: .objects,
                         prompt: category.question,
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "\(category.id) · \(familyNote) · "
                            + "\(byCategory.count) categories in play · "
                            + "\(personal) personal + \(photos.count - personal) pack",
                         focusTag: categoryID)
        }
        return nil
    }

    /// "Which photo has a lion in it?" — when the pack already knows it is a lion.
    ///
    /// The Animals pack carries a hand-written name and a Wikipedia sentence for every
    /// photograph, and for a long time the game threw both away and asked "which one is
    /// a mammal?" The coarse question was not caution about the photographs; it was
    /// caution about the *classifier*, which can only be trusted on broad categories when
    /// it is looking at a stranger's camera roll. None of that applies here. Nobody
    /// guessed these: a person looked one up, wrote down what it was, and the sentence
    /// under the answer names it too.
    ///
    /// Asking by name also makes the round a better round. "Which one is a mammal?"
    /// beside a bird, a fish and a lizard is a biology question with a giveaway; "which
    /// photo has a lion in it?" beside a tiger, a leopard and a bear is four animals and
    /// a real decision. So the distractors here are chosen by *name* rather than by
    /// class, which is only safe because the pack promises one creature per photograph.
    private static func namedSubjectLevel(pool: [GamePhoto],
                                          wanted: Int,
                                          visualDistance: ((GamePhoto, GamePhoto) -> Double?)?)
        -> Level? {

        // Only photographs that carry a name worth asking by, one per name.
        //
        // `askableName` rather than `title`: a plant whose only name is its binomial has
        // a title, and asking "Which photo has Cephalanthera damasonium in it?" is a
        // spelling test rather than a question. Eight of the 540 plants and ten of the
        // 532 animals have no English name, and they sit out the identify rounds.
        var byName: [String: GamePhoto] = [:]
        for photo in pool {
            guard !photo.isPersonal, let title = photo.askableName else { continue }
            let name = plainName(title)
            guard !name.isEmpty, byName[name] == nil else { continue }
            byName[name] = photo
        }
        guard byName.count >= wanted else { return nil }

        for (name, target) in byName.shuffled() {
            // Everything that can stand beside it without the answer being arguable.
            let companions = byName
                .filter { ObjectCatalog.canStandTogether(name, $0.key) }
                .map(\.value)
            guard companions.count >= wanted - 1 else { continue }

            // From the same pack where there are enough. "Which one shows the Mona Lisa?"
            // is a fair question beside a lion — the lion is plainly not the Mona Lisa —
            // and a strange one to be asked. Four paintings is a round about paintings;
            // a painting between two animals and a landmark is a shuffled deck.
            let fromSamePack = companions.filter { $0.packID == target.packID }
            let pool = fromSamePack.count >= wanted - 1 ? fromSamePack : companions

            // Alike, but never so alike that the round becomes a coin toss.
            let ordered = Resemblance.ranked(pool, like: target,
                                             distance: visualDistance)
            let distractors = Array(ordered.prefix(wanted - 1))
            guard distractors.count == wanted - 1 else { continue }

            // Every pair, not just each against the answer: a round holding both a hare
            // and a rabbit is unfair even when the answer is a lion.
            let names = ([target] + distractors).compactMap { $0.askableName.map(plainName) }
            guard names.count == wanted else { continue }
            var allStand = true
            for (index, one) in names.enumerated() {
                for other in names.dropFirst(index + 1)
                where !ObjectCatalog.canStandTogether(one, other) {
                    allStand = false
                }
            }
            guard allStand else { continue }

            let photos = ([target] + distractors).shuffled()
            // The pack's own phrasing where it has one. "Which photo has a mona lisa in
            // it?" is what happens without this: the Mona Lisa is not *in* a photograph,
            // it is what the photograph shows.
            let asked = target.namedSubjectPrompt
                .map { $0.replacingOccurrences(of: "{name}", with: target.askableName ?? name) }
                ?? "Which photo has \(article(for: name)) \(name) in it?"
            return Level(theme: .objects,
                         prompt: asked,
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "named subject · \(name) · "
                            + "\(byName.count) names in play",
                         focusTag: name,
                         hint: namedSubjectHint(for: target, among: photos))
        }
        return nil
    }

    /// "Which one was painted by Leonardo da Vinci?"
    ///
    /// The painter is a fact the pack has carried all along and curation could not see:
    /// `creator` sat in the manifest beside `credit`, which names whoever photographed the
    /// painting rather than whoever painted it. For a public-domain work the two usually
    /// read the same and they answer different questions.
    ///
    /// One work by the artist asked about, three by other artists. The three are checked
    /// against the answer's artist by name, not by pack: two Caravaggios in a round would
    /// make the question have two answers.
    private nonisolated static func artistLevel(
        pool: [GamePhoto], wanted: Int,
        visualDistance: ((GamePhoto, GamePhoto) -> Double?)?) -> Level? {

        var byArtist: [String: [GamePhoto]] = [:]
        for photo in pool {
            guard !photo.isPersonal, let artist = photo.creator?.nilIfBlank,
                  photo.title?.nilIfBlank != nil else { continue }
            byArtist[artist, default: []].append(photo)
        }
        // Three other artists have to exist, or there is nothing to stand beside the
        // answer that is not also by them.
        guard byArtist.count >= wanted else { return nil }

        for (artist, works) in byArtist.shuffled() {
            guard let target = works.randomElement() else { continue }
            let others = byArtist
                .filter { $0.key != artist }
                .compactMap { $0.value.randomElement() }
            guard others.count >= wanted - 1 else { continue }

            // Alike where the difficulty asks for it, as everywhere else.
            let ordered = Resemblance.ranked(others, like: target,
                                             distance: visualDistance)
            let distractors = Array(ordered.prefix(wanted - 1))
            guard distractors.count == wanted - 1,
                  !distractors.contains(where: { $0.creator == artist }) else { continue }

            let photos = ([target] + distractors).shuffled()
            return Level(theme: .objects,
                         prompt: "Which one was painted by \(artist)?",
                         photos: photos,
                         correctPhotoID: target.id,
                         curationNote: "by artist · \(artist) · "
                            + "\(byArtist.count) artists in play",
                         focusTag: Ask.artist.rawValue,
                         hint: nil)
        }
        return nil
    }

    /// "Which photo is from your album?"
    ///
    /// The three-to-one rule already puts exactly one of the player's own photographs in
    /// most rounds, and that arrangement is itself a question worth asking: picking your
    /// own picture out of a row is recognition of the easiest and most personal kind, and
    /// it needs no date, no place and no classifier to have looked at anything.
    ///
    /// Exactly one, never more. Two of somebody's own photographs in the row makes the
    /// question have two answers, and nothing about the round says which was meant. A pool
    /// with none of their photographs in it — somebody playing on the packs alone — simply
    /// cannot carry this question, and the curator declines.
    private nonisolated static func ownPhotoLevel(pool: [GamePhoto], wanted: Int) -> Level? {
        let mine = pool.filter(\.isPersonal)
        let theirs = pool.filter { !$0.isPersonal }
        guard !mine.isEmpty, theirs.count >= wanted - 1 else { return nil }

        // A photograph of the player's that a pack could plausibly have shipped is a
        // cruel question. Their own pictures of scenery and landmarks are exactly the
        // ones a stock set is full of, so the question is asked about the rest: faces,
        // rooms, meals, the things only they have.
        let unmistakable = mine.filter { !$0.hidesSurroundings && !$0.looksLikeDocument }
        guard let target = (unmistakable.isEmpty ? mine : unmistakable).randomElement()
        else { return nil }

        let distractors = Array(theirs.shuffled().prefix(wanted - 1))
        guard distractors.count == wanted - 1 else { return nil }

        let photos = ([target] + distractors).shuffled()
        return Level(theme: .objects,
                     prompt: "Which photo is from your album?",
                     photos: photos,
                     correctPhotoID: target.id,
                     curationNote: "your own · 1 personal + \(distractors.count) pack",
                     focusTag: Ask.mine.rawValue,
                     hint: nil)
    }

    /// "A lion" → "lion". The packs write titles as a phrase; the question needs the noun.
    private static func plainName(_ title: String) -> String {
        var name = title.lowercased()
        for article in ["a ", "an ", "the "] where name.hasPrefix(article) {
            name = String(name.dropFirst(article.count))
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    private static func article(for name: String) -> String {
        "aeiou".contains(name.first ?? "x") ? "an" : "a"
    }
}

// MARK: - Occasions


