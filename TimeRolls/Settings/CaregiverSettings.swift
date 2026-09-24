//
//  CaregiverSettings.swift
//  Time Rolls
//
//  Caregiver setup state (spec §7.1). Soft-gated, never authenticated, stored
//  on-device only — including the optional plain-text labels.
//

import Foundation

struct CaregiverSettings: Codable, Equatable, Sendable {

    enum TextScale: String, Codable, CaseIterable, Sendable, Identifiable {
        // "Largest" was removed: at that size the question wrapped to three lines and
        // pushed the photographs off the screen, which costs more than the type gains.
        case standard, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: "Standard"
            case .large: "Large"
            }
        }
        var multiplier: Double {
            switch self {
            case .standard: 1.0
            case .large: 1.12
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

    /// Local Trivia: notable places near this iPad, looked up at play time.
    /// Off until somebody turns it on — it is the only feature that needs location.
    var localTriviaEnabled = false

    // Difficulty & pace
    /// How many photo cards make a day's challenge.
    ///
    /// Chosen during setup and changeable here, because the right number is a fact about
    /// one person on one day — somebody recovering from a bad week and somebody who plays
    /// for an hour need different days, and neither of them is wrong.
    ///
    /// Eight by default: enough that finishing means something, few enough that a hard day
    /// still ends in "you did it". The challenge is the only thing in the app that can be
    /// failed, so the default is set low on purpose.
    var dailyCardGoal = 8

    /// The last day whose challenge was celebrated, as yyyy-MM-dd.
    ///
    /// The congratulations screen is a moment, and a moment shown twice is not one. Once
    /// the day's challenge is met the game keeps going for as long as somebody wants to
    /// play, and does not interrupt again until tomorrow.
    var lastCelebratedDay: String?

    // Accessibility
    var textScale: TextScale = .standard
    var highContrast = false
    var monochromeMode: MonochromeMode = .off
    var audioCues = true
    /// Whether Apple's on-device model may reword the questions.
    var livelyQuestions = true
    /// Whether the question is read aloud when a round opens (spec §6). Off until
    /// somebody turns it on: a device that starts talking unprompted is startling, and
    /// this is for the player who needs it rather than every player.
    var narration = false
    /// Which installed voice to use. Nil means the best one on the device.
    var voiceIdentifier: String?
    /// Whether a correct round moves on by itself after a few seconds.
    ///
    /// On, because otherwise every round ends with somebody having to find a button — and
    /// for a player who has just enjoyed getting one right, the game stopping dead is what
    /// ends the session. It is a setting because somebody who reads slowly needs it off,
    /// and they are exactly the person who would never complain about it.
    /// Whether the player can answer by saying a photo's number. Off until somebody turns
    /// it on: it needs the microphone, and a game that starts listening unasked is not a
    /// game anybody should ship to an older person's front room.
    var voiceAnswers = false
    /// Whether the on-device model plays each round before the player does, and drops
    /// the ones it can't answer. iOS 27 and Apple Intelligence only; where either is
    /// missing, this does nothing at all.
    var checkedRounds = true

    /// Everything the app makes a noise with, as one switch.
    ///
    /// The play screen's button used to toggle `narration` alone, so "Sound off" stopped
    /// the voice and left the chimes ringing — which reads as the button not working.
    /// Underneath there are still two preferences, because a caregiver may reasonably want
    /// cues without narration, but the player's button is a single idea and has to behave
    /// like one: off means silent.
    /// All three: the voice that reads the question, the chimes, and the microphone.
    ///
    /// The microphone belongs here even though it is input rather than output. "Sound off"
    /// is what somebody reaches for in a quiet ward, on a bus, or with a person asleep in
    /// the next chair — and in every one of those a device still listening for somebody to
    /// say "two" is the thing they were trying to switch off. One switch, everything the
    /// app does with sound.
    var soundOn: Bool {
        get { narration || audioCues || voiceAnswers }
        set {
            narration = newValue
            audioCues = newValue
            voiceAnswers = newValue
        }
    }

    /// Photographs a caregiver has asked never to be shown again (spec §4).
    ///
    /// Deliberately a plain list of identifiers: no learning, no embeddings, nothing
    /// inferred. Some photographs are wrong for one household for reasons no rule could
    /// ever hold — a person who has died, a hospital corridor, a house somebody lost —
    /// and the only honest way to handle that is to let someone say so and be obeyed
    /// exactly. It is also the one control here that needs no explanation to work.
    var excludedPhotoIDs: Set<String> = []

    // Optional light labelling (album or photo identifier → plain context)
    var labels: [String: String] = [:]

    var hasCompletedFirstRun = false
    /// Whether the one-time note about supporting the app has been shown. Once, ever,
    /// however it was answered — an app for somebody with memory difficulties must never
    /// be a thing that asks for money twice because it forgot it already had.
    var hasAskedAboutSupport = false

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
        localTriviaEnabled = value(.localTriviaEnabled, defaults.localTriviaEnabled)
        dailyCardGoal = value(.dailyCardGoal, defaults.dailyCardGoal)
        lastCelebratedDay = value(.lastCelebratedDay, defaults.lastCelebratedDay)
        // Anyone who had chosen "Largest" lands back on Standard: the stored word no
        // longer decodes, and the decoder's fallback is the migration.
        textScale = value(.textScale, defaults.textScale)
        highContrast = value(.highContrast, defaults.highContrast)
        monochromeMode = value(.monochromeMode, defaults.monochromeMode)
        audioCues = value(.audioCues, defaults.audioCues)
        livelyQuestions = value(.livelyQuestions, defaults.livelyQuestions)
        excludedPhotoIDs = value(.excludedPhotoIDs, defaults.excludedPhotoIDs)
        checkedRounds = value(.checkedRounds, defaults.checkedRounds)
        narration = value(.narration, defaults.narration)
        voiceIdentifier = value(.voiceIdentifier, defaults.voiceIdentifier)
        voiceAnswers = value(.voiceAnswers, defaults.voiceAnswers)
        labels = value(.labels, defaults.labels)
        hasCompletedFirstRun = value(.hasCompletedFirstRun, defaults.hasCompletedFirstRun)
        hasAskedAboutSupport = value(.hasAskedAboutSupport, defaults.hasAskedAboutSupport)
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
            + "|\(labelled)|\(excludedPhotoIDs.sorted().joined(separator: ","))"
    }

    /// Recover if every pack these settings point at has gone away — a pack removed in a
    /// later build would otherwise leave someone who had chosen only that pack, and who
    /// isn't using their own photos, with nothing to play.
    mutating func healOrphanedPackChoices() -> Bool {
        let playable = Set(PublicPackLibrary.packs.filter(\.isPlayable).map(\.id))
        guard !playable.isEmpty else { return false }
        if enabledPackIDs.intersection(playable).isEmpty {
            enabledPackIDs = playable
            return true
        }
        // Forget packs that no longer exist. They cost nothing to keep, except that
        // every count of "how many packs are on" then includes packs that are gone.
        let stale = enabledPackIDs.subtracting(playable)
        guard !stale.isEmpty else { return false }
        enabledPackIDs.subtract(stale)
        return true
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
