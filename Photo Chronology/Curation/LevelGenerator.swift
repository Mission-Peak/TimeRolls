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

    /// Chance of blending pack photos into an otherwise healthy personal library,
    /// for variety (spec §6.2b).
    private let blendChance = 0.35

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
        }
    }

    func availableThemes(knob: DifficultyKnob) -> [GameTheme] {
        GameTheme.allCases.filter { canPlay($0, knob: knob) }
    }

    // MARK: - Generation

    func makeLevel(theme: GameTheme, knob: DifficultyKnob) -> Level? {
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
        }
    }

    /// Personal photos, plus pack photos when the library is thin for this theme
    /// (standalone content) or when the variety roll comes up (blending).
    private func pool(for theme: GameTheme,
                      knob: DifficultyKnob,
                      forceBlend: Bool = false) -> [GamePhoto] {
        let usablePersonal: [GamePhoto]
        let sparse: Bool

        switch theme {
        case .chronology:
            usablePersonal = personal.filter { $0.creationDate != nil }
            sparse = usablePersonal.count < knob.photoCount * 3
        case .places:
            // Scanned photos, screenshots and stripped metadata leave many libraries
            // GPS-poor — this is the known gap in spec §5.2.
            usablePersonal = personal.filter { $0.placeName != nil }
            sparse = Set(usablePersonal.compactMap(\.placeName)).count < 3
        }

        guard !pack.isEmpty else { return usablePersonal }

        if forceBlend || sparse {
            return usablePersonal + pack
        }
        if Double.random(in: 0...1) < blendChance {
            let sampleSize = max(knob.photoCount, pack.count / 3)
            return usablePersonal + pack.shuffled().prefix(sampleSize)
        }
        return usablePersonal
    }
}
