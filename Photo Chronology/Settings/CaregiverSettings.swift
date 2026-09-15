//
//  CaregiverSettings.swift
//  Photo Chronology
//
//  Caregiver setup state (spec §7.1). Soft-gated, never authenticated, stored
//  on-device only — including the optional plain-text labels.
//

import Foundation

struct CaregiverSettings: Codable, Equatable, Sendable {

    enum StartingDifficulty: String, Codable, CaseIterable, Sendable, Identifiable {
        case gentle, standard, challenging
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gentle: "Gentle"
            case .standard: "Standard"
            case .challenging: "Challenging"
            }
        }
        var detail: String {
            switch self {
            case .gentle: "Photos far apart in time. 3 per level."
            case .standard: "A comfortable mix. 4 per level."
            case .challenging: "Photos close together in time. 5 per level."
            }
        }
        var knob: DifficultyKnob {
            switch self {
            case .gentle: .gentle
            case .standard: .standard
            case .challenging: .challenging
            }
        }
    }

    enum TextScale: String, Codable, CaseIterable, Sendable, Identifiable {
        case standard, large, largest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: "Standard"
            case .large: "Large"
            case .largest: "Largest"
            }
        }
        var multiplier: Double {
            switch self {
            case .standard: 1.0
            case .large: 1.18
            case .largest: 1.36
            }
        }
    }

    /// The black-and-white difficulty lever. Always optional, always crisp mono —
    /// never faded sepia — and never the only difficulty axis (accessibility
    /// guardrail, spec §7.1).
    enum MonochromeMode: String, Codable, CaseIterable, Sendable, Identifiable {
        case off, occasional, always
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Off"
            case .occasional: "Some levels"
            case .always: "Every level"
            }
        }
    }

    // Photo sources
    var useAllPhotos = true
    /// Album identifier → included. A `false` entry always wins over inclusion.
    var albumSelection: [String: Bool] = [:]
    var enabledPackIDs: Set<String> = PublicPackLibrary.defaultEnabledPackIDs
    /// Packs these settings have already seen. A pack that appears later — a new build,
    /// or one delivered over OneBucket — arrives switched on rather than hidden.
    var knownPackIDs: Set<String> = []
    /// The Objects theme looks at photo content on this device. Switchable off, in which
    /// case the app stays strictly metadata-only (spec §6.3, §9).
    var objectsThemeEnabled = true

    // Difficulty & pace
    var startingDifficulty: StartingDifficulty = .standard
    /// 0 means no set length — the player stops whenever they like.
    var levelsPerSession = 8
    /// Silent only: timing is never shown to the player (spec §2).
    var adaptiveTiming = true
    /// The kind of question the player picked from the chip on the play screen.
    /// nil means a mix, which is the default and what the app did before this existed.
    var pinnedThemeID: String?
    /// Together mode: a quiet strip for a companion sitting alongside the player.
    /// Same room only — nothing is paired, sent or stored (spec §7 rationale).
    var togetherMode = false

    // Accessibility
    var textScale: TextScale = .standard
    var highContrast = false
    var monochromeMode: MonochromeMode = .off
    var audioCues = true

    // Optional light labelling (album or photo identifier → plain context)
    var labels: [String: String] = [:]

    var hasCompletedFirstRun = false

    // MARK: - Decoding
    //
    // Every key is optional on the way in, so adding a setting never discards a
    // caregiver's existing choices.

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        let defaults = CaregiverSettings()
        useAllPhotos = value(.useAllPhotos, defaults.useAllPhotos)
        albumSelection = value(.albumSelection, defaults.albumSelection)
        enabledPackIDs = value(.enabledPackIDs, defaults.enabledPackIDs)
        knownPackIDs = value(.knownPackIDs, defaults.knownPackIDs)
        objectsThemeEnabled = value(.objectsThemeEnabled, defaults.objectsThemeEnabled)
        startingDifficulty = value(.startingDifficulty, defaults.startingDifficulty)
        levelsPerSession = value(.levelsPerSession, defaults.levelsPerSession)
        adaptiveTiming = value(.adaptiveTiming, defaults.adaptiveTiming)
        togetherMode = value(.togetherMode, defaults.togetherMode)
        pinnedThemeID = value(.pinnedThemeID, defaults.pinnedThemeID)
        textScale = value(.textScale, defaults.textScale)
        highContrast = value(.highContrast, defaults.highContrast)
        monochromeMode = value(.monochromeMode, defaults.monochromeMode)
        audioCues = value(.audioCues, defaults.audioCues)
        labels = value(.labels, defaults.labels)
        hasCompletedFirstRun = value(.hasCompletedFirstRun, defaults.hasCompletedFirstRun)
    }

    // MARK: - Persistence

    private static let key = "caregiver-settings-v1"

    static func load() -> CaregiverSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CaregiverSettings.self, from: data) else {
            return CaregiverSettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    var pinnedTheme: GameTheme? {
        get { pinnedThemeID.flatMap(GameTheme.init(rawValue:)) }
        set { pinnedThemeID = newValue?.rawValue }
    }

    /// Fingerprint of everything that decides which photos are in play. Any screen that
    /// can change a source watches this, so a change made on a pushed screen takes effect
    /// straight away rather than whenever the parent happens to re-evaluate.
    var photoSourceFingerprint: String {
        let albums = albumSelection
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")
        let labelled = labels
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        return "\(useAllPhotos)|\(albums)|\(enabledPackIDs.sorted().joined(separator: ","))"
            + "|\(labelled)|\(objectsThemeEnabled)"
    }

    /// Switch on any playable pack these settings have not met before.
    /// Returns true when something changed.
    mutating func adoptNewPacks() -> Bool {
        let playable = PublicPackLibrary.packs.filter(\.isPlayable).map(\.id)
        let unseen = playable.filter { !knownPackIDs.contains($0) }
        guard !unseen.isEmpty else { return false }
        enabledPackIDs.formUnion(unseen)
        knownPackIDs.formUnion(PublicPackLibrary.packs.map(\.id))
        return true
    }

    /// Whether a given level should be shown in mono, given the caregiver's choice.
    func shouldUseMonochrome(levelIndex: Int) -> Bool {
        switch monochromeMode {
        case .off: false
        case .occasional: levelIndex % 3 == 2
        case .always: true
        }
    }
}
