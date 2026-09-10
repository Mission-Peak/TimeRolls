//
//  Curators.swift
//  Photo Chronology
//
//  Curation and difficulty logic (spec §5). Two rules run through all of it:
//  the right answer is always unambiguous (errorless design, §2), and the
//  distractors are always plausible rather than obviously-wrong filler (§5.3).
//

import Foundation
import CoreLocation

enum ChronologyCurator {

    /// Buckets the pool into time windows and samples inside one of them.
    /// Tight windows make a hard level; wide ones make an easy one — the time-delta
    /// lever from spec §5.1.
    static func makeLevel(pool: [GamePhoto], knob: DifficultyKnob) -> Level? {
        let dated = pool
            .filter { $0.creationDate != nil }
            .sorted { $0.creationDate! < $1.creationDate! }
        let wanted = min(max(knob.photoCount, 3), 5)
        guard dated.count >= 3 else { return nil }
        let count = min(wanted, dated.count)

        let decisiveGap = knob.chronologyDecisiveGap
        var span = knob.chronologyTargetGap * Double(count - 1) * 1.4

        // Widen the window until the library can actually fill a level.
        for attempt in 0..<6 {
            let windows = timeWindows(in: dated, span: span, minimumCount: count)
            if let level = sample(from: windows,
                                  dated: dated,
                                  count: count,
                                  decisiveGap: decisiveGap,
                                  knob: knob,
                                  span: span,
                                  relaxed: attempt > 0) {
                return level
            }
            span *= 2.5
        }

        // Last resort for a very thin library: spread picks across the whole timeline.
        return spreadFallback(dated: dated, count: count, knob: knob)
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
                               knob: DifficultyKnob,
                               span: TimeInterval,
                               relaxed: Bool) -> Level? {
        guard !windows.isEmpty else { return nil }

        // Prefer windows that include at least one of the player's own photos.
        let personalFirst = windows.shuffled().sorted { lhs, rhs in
            let l = dated[lhs].contains(where: \.isPersonal) ? 1 : 0
            let r = dated[rhs].contains(where: \.isPersonal) ? 1 : 0
            return l > r
        }

        for window in personalFirst.prefix(24) {
            let slice = Array(dated[window])
            // The oldest photo in the window is the answer; it has to be clearly oldest.
            let oldest = slice[0]
            let gap = relaxed ? decisiveGap * 0.4 : decisiveGap
            let eligible = slice.dropFirst().filter {
                $0.creationDate!.timeIntervalSince(oldest.creationDate!) >= gap
            }
            guard eligible.count >= count - 1 else { continue }

            // Spread the distractors out in time as well, so the reveal doesn't show
            // three photos from the same month (spec §5.3).
            let distractors = spread(Array(eligible), anchor: oldest, count: count - 1)
            let runnerUpGap = distractors
                .map { $0.creationDate!.timeIntervalSince(oldest.creationDate!) }
                .min() ?? 0

            return Level(theme: .chronology,
                         prompt: "Which photo is older?",
                         photos: ([oldest] + distractors).shuffled(),
                         correctPhotoID: oldest.id,
                         difficulty: knob.level,
                         curationNote: note(runnerUp: runnerUpGap, span: span,
                                            photos: [oldest] + distractors))
        }
        return nil
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

    /// Sparse-library path: take the oldest photo and spread the distractors out.
    private static func spreadFallback(dated: [GamePhoto],
                                       count: Int,
                                       knob: DifficultyKnob) -> Level? {
        guard dated.count >= 3 else { return nil }
        let oldest = dated[0]
        var picks: [GamePhoto] = []
        let stride = max(1, (dated.count - 1) / (count - 1))
        var index = stride
        while picks.count < count - 1 && index < dated.count {
            picks.append(dated[index])
            index += stride
        }
        while picks.count < count - 1, let extra = dated.dropFirst().randomElement(),
              !picks.contains(extra) {
            picks.append(extra)
        }
        guard picks.count == count - 1 else { return nil }
        let runnerUp = picks.map { $0.creationDate!.timeIntervalSince(oldest.creationDate!) }.min() ?? 0
        return Level(theme: .chronology,
                     prompt: "Which photo is older?",
                     photos: ([oldest] + picks).shuffled(),
                     correctPhotoID: oldest.id,
                     difficulty: knob.level,
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

    /// Exactly one photo from the target place, plus plausible distractors from
    /// elsewhere. Harder levels draw those distractors from nearby places (spec §5.2–5.3).
    static func makeLevel(pool: [GamePhoto], knob: DifficultyKnob) -> Level? {
        let named = pool.filter { $0.placeName != nil && $0.coordinate != nil }
        let byPlace = Dictionary(grouping: named) { $0.placeName! }
        guard byPlace.count >= 3 else { return nil }

        let wanted = min(max(knob.photoCount, 3), 5)
        let count = min(wanted, byPlace.count)

        // Favour target places where the player has their own photo.
        let placeNames = byPlace.keys.shuffled().sorted { lhs, rhs in
            let l = byPlace[lhs]!.contains(where: \.isPersonal) ? 1 : 0
            let r = byPlace[rhs]!.contains(where: \.isPersonal) ? 1 : 0
            return l > r
        }

        for targetName in placeNames.prefix(12) {
            guard let target = byPlace[targetName]?.randomElement(),
                  let targetCoordinate = target.coordinate else { continue }

            // Other places, nearest first.
            let others = byPlace
                .filter { $0.key != targetName }
                .compactMap { name, photos -> (String, GamePhoto, CLLocationDistance)? in
                    guard let photo = photos.randomElement(),
                          let coordinate = photo.coordinate else { return nil }
                    return (name, photo, targetCoordinate.distance(to: coordinate))
                }
                .sorted { $0.2 < $1.2 }

            guard others.count >= count - 1 else { continue }

            // Hard levels want the near neighbours; gentle levels want far-flung ones.
            let nearby = others.filter { $0.2 <= knob.placesNeighbourRadius }
            let candidates = nearby.count >= count - 1 ? nearby : others
            let distractors = knob.level > 0.5
                ? Array(candidates.prefix(max(count - 1, 3)).shuffled().prefix(count - 1))
                : Array(candidates.suffix(max(count - 1, 3)).shuffled().prefix(count - 1))

            guard distractors.count == count - 1 else { continue }

            let nearest = distractors.map(\.2).min() ?? 0
            let photos = ([target] + distractors.map(\.1)).shuffled()
            let personal = photos.filter(\.isPersonal).count

            return Level(theme: .places,
                         prompt: "Which photo was taken in \(shortName(targetName))?",
                         photos: photos,
                         correctPhotoID: target.id,
                         difficulty: knob.level,
                         curationNote: "nearest distractor \(Int(nearest / 1000))km · "
                            + "\(byPlace.count) places known · "
                            + "\(personal) personal + \(photos.count - personal) pack")
        }
        return nil
    }

    /// "Rome, Italy" reads better in a question than the full formatted string.
    static func shortName(_ name: String) -> String {
        name.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? name
    }
}

enum ObjectsCurator {

    /// One photo that clearly contains the category, plus distractors the classifier
    /// saw no hint of it in (spec §5.3, §6.3). Harder levels pull those distractors
    /// from the same family, so "which one has a dog" sits next to a cat and a horse.
    static func makeLevel(pool: [GamePhoto], knob: DifficultyKnob) -> Level? {
        let wanted = min(max(knob.photoCount, 3), 5)

        var byCategory: [String: [GamePhoto]] = [:]
        for photo in pool {
            for tag in photo.objectTags where ObjectCatalog.category(id: tag) != nil {
                byCategory[tag, default: []].append(photo)
            }
        }
        guard !byCategory.isEmpty else { return nil }

        // Favour categories the player has their own photo of.
        let candidates = byCategory.keys.shuffled().sorted { lhs, rhs in
            let l = byCategory[lhs]!.contains(where: \.isPersonal) ? 1 : 0
            let r = byCategory[rhs]!.contains(where: \.isPersonal) ? 1 : 0
            return l > r
        }

        let preferSameFamily = Double.random(in: 0...1) < knob.objectsSameFamilyChance

        for categoryID in candidates.prefix(12) {
            guard let category = ObjectCatalog.category(id: categoryID),
                  let target = byCategory[categoryID]?.randomElement() else { continue }

            // A distractor must not even arguably contain the target category.
            let clean = pool.filter {
                $0.id != target.id && !$0.possibleObjectTags.contains(categoryID)
            }
            // Prefer photos that clearly show *something* — a blank wall is filler.
            let recognisable = clean.filter { !$0.objectTags.isEmpty }

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
            for photo in preferred.shuffled() where distractors.count < wanted - 1 {
                let tags = photo.objectTags
                guard tags.isDisjoint(with: usedTags) else { continue }
                distractors.append(photo)
                usedTags.formUnion(tags)
            }
            // Top up if the library is too thin to be picky, preferring photos that add
            // something new — an untagged photo beats a second photo of the same thing.
            if distractors.count < wanted - 1 {
                let topUp = clean.shuffled().sorted {
                    $0.objectTags.intersection(usedTags).count
                        < $1.objectTags.intersection(usedTags).count
                }
                for photo in topUp where distractors.count < wanted - 1 {
                    guard !distractors.contains(photo) else { continue }
                    distractors.append(photo)
                    usedTags.formUnion(photo.objectTags)
                }
            }
            guard distractors.count == wanted - 1 else { continue }

            let photos = ([target] + distractors).shuffled()
            let personal = photos.filter(\.isPersonal).count
            let familyNote = preferSameFamily && sameFamily.count >= wanted - 1
                ? "same-family distractors"
                : "mixed distractors"

            return Level(theme: .objects,
                         prompt: category.question,
                         photos: photos,
                         correctPhotoID: target.id,
                         difficulty: knob.level,
                         curationNote: "\(category.id) · \(familyNote) · "
                            + "\(byCategory.count) categories in play · "
                            + "\(personal) personal + \(photos.count - personal) pack",
                         focusTag: categoryID)
        }
        return nil
    }
}
