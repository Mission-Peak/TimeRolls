//
//  LevelGenerator.swift
//  Photo Chronology
//
//  Assembles the pool for a level and hands it to the right curator.
//  Curation is re-run at play time with randomness, so the same theme yields a
//  different photo set every session (spec §3.1).
//

import Foundation

struct LevelGenerator {

    var personal: [GamePhoto] = []
    var pack: [GamePhoto] = []
    /// Objects looks at photo content, so the caregiver can switch it off entirely.
    var allowObjects = true
    /// Which games each pack is willing to carry, by pack id.
    var packThemeSupport: [String: Set<GameTheme>] = [:]

    /// Chance of blending pack photos into an otherwise healthy personal library,
    /// for variety (spec §6.2b).
    private let blendChance = 0.35

    /// When the player's own library can carry a theme, a pack photo is a garnish:
    /// spec §6.2b asks for pack photos blended *alongside* personal ones, not instead
    /// of them. Without this a level can come out entirely stock — the curators pick by
    /// time window or by place, and a dense pack will win a window outright.
    private let packAllowanceWhenHealthy = 1

    // MARK: - Availability

    func canPlay(_ theme: GameTheme, knob: DifficultyKnob) -> Bool {
        switch theme {
        case .chronology:
            return pool(for: theme, knob: knob, forceBlend: true)
                .filter { $0.creationDate != nil }.count >= 3
        case .places:
            let places = Set(pool(for: theme, knob: knob, forceBlend: true)
                .compactMap(\.placeName))
            return places.count >= 3
        case .objects:
            guard allowObjects else { return false }
            // Needs a subject plus enough photos that plainly don't contain it.
            return ObjectsCurator.makeLevel(
                pool: pool(for: theme, knob: knob, forceBlend: true), knob: knob) != nil
        }
    }

    func availableThemes(knob: DifficultyKnob) -> [GameTheme] {
        GameTheme.allCases.filter { canPlay($0, knob: knob) }
    }

    // MARK: - Generation

    func makeLevel(theme: GameTheme, knob: DifficultyKnob) -> Level? {
        guard !isSparse(for: theme, knob: knob) else {
            // Nothing personal to protect: the packs are the content.
            return curate(theme: theme, knob: knob)
        }

        // Otherwise keep the player's own photos in the foreground. Curation is random,
        // so a few attempts is enough; whichever came out least stock is the fallback.
        var best: Level?
        var bestCount = Int.max
        for _ in 0..<5 {
            guard let level = curate(theme: theme, knob: knob) else { break }
            let packCount = level.photos.count { !$0.isPersonal }
            if packCount <= packAllowanceWhenHealthy { return level }
            if packCount < bestCount {
                best = level
                bestCount = packCount
            }
        }
        return best
    }

    private func curate(theme: GameTheme, knob: DifficultyKnob) -> Level? {
        let pool = pool(for: theme, knob: knob)
        switch theme {
        case .chronology:
            return ChronologyCurator.makeLevel(pool: pool, knob: knob)
                ?? ChronologyCurator.makeLevel(
                    pool: self.pool(for: theme, knob: knob, forceBlend: true), knob: knob)
        case .places:
            return PlacesCurator.makeLevel(pool: pool, knob: knob)
                ?? PlacesCurator.makeLevel(
                    pool: self.pool(for: theme, knob: knob, forceBlend: true), knob: knob)
        case .objects:
            guard allowObjects else { return nil }
            return ObjectsCurator.makeLevel(pool: pool, knob: knob)
                ?? ObjectsCurator.makeLevel(
                    pool: self.pool(for: theme, knob: knob, forceBlend: true), knob: knob)
        }
    }

    /// How much of a generated level came from the packs — for diagnostics.
    func packShare(of level: Level) -> String {
        let packCount = level.photos.count { !$0.isPersonal }
        return "\(level.photos.count - packCount) personal + \(packCount) pack"
    }

    /// Personal photos, plus pack photos when the library is thin for this theme
    /// (standalone content) or when the variety roll comes up (blending).
    /// The player's own photos that can carry this theme.
    private func usablePersonal(for theme: GameTheme) -> [GamePhoto] {
        switch theme {
        case .chronology:
            personal.filter { $0.creationDate != nil }
        case .places:
            // Scanned photos, screenshots and stripped metadata leave many libraries
            // GPS-poor — this is the known gap in spec §5.2.
            personal.filter { $0.placeName != nil }
        case .objects:
            // Untagged photos are still useful here: a photo the classifier found
            // nothing in is a perfectly clean distractor.
            personal
        }
    }

    /// Whether the personal library is too thin to carry this theme on its own.
    private func isSparse(for theme: GameTheme, knob: DifficultyKnob) -> Bool {
        let usable = usablePersonal(for: theme)
        switch theme {
        case .chronology:
            return usable.count < knob.photoCount * 3
        case .places:
            return Set(usable.compactMap(\.placeName)).count < 3
        case .objects:
            return Set(usable.flatMap(\.objectTags)).count < 2
        }
    }

    private func pool(for theme: GameTheme,
                      knob: DifficultyKnob,
                      forceBlend: Bool = false) -> [GamePhoto] {
        let usable = usablePersonal(for: theme)
        // Only packs that can carry this game. A pack of undatable photographs must
        // never end up in "which one is older".
        let pack = pack.filter { photo in
            guard case let .pack(packID, _) = photo.origin else { return false }
            return packThemeSupport[packID]?.contains(theme) ?? true
        }
        guard !pack.isEmpty else { return usable }

        if forceBlend || isSparse(for: theme, knob: knob) {
            return usable + pack
        }
        if Double.random(in: 0...1) < blendChance {
            // A handful, not a third of the library. Tipping hundreds of pack photos
            // into the pool is what let them take a level over.
            return usable + pack.shuffled().prefix(knob.photoCount)
        }
        return usable
    }
}
