//
//  GameEngine.swift
//  Photo Chronology
//
//  Owns the session: curation, feedback, adaptive difficulty, telemetry (spec §3).
//  Nothing here penalises the player — no scores, no fail states, no visible clock.
//

import Foundation
import Observation

@Observable
@MainActor
final class GameEngine {

    enum Phase: Equatable {
        case firstRun
        case preparing
        case playing
        case sessionComplete
        /// Not enough photos anywhere to build a level — with every pack off, say.
        case noContent(String)
    }

    // Dependencies
    let library = PhotoLibraryService()
    let places = PlaceResolver()
    let images = ImageProvider()
    let stats = StatsStore()
    let telemetry = TelemetryQueue()

    // State
    var settings: CaregiverSettings
    private(set) var phase: Phase = .preparing
    private(set) var level: Level?
    private(set) var knob: DifficultyKnob
    private(set) var attempts = 0
    private(set) var wrongIDs: Set<String> = []
    private(set) var answeredCorrectly = false
    private(set) var levelsThisSession = 0
    private(set) var availableThemes: [GameTheme] = []
    private(set) var levelIndex = 0

    /// Computed, so flipping the caregiver's black-and-white setting shows up at once.
    var isMonochromeLevel: Bool {
        settings.shouldUseMonochrome(levelIndex: levelIndex)
    }

    private var generator = LevelGenerator()
    private var levelStarted = Date()
    private var levelCounter = 0
    private var lastTheme: GameTheme?
    private var sessionLevelTotal = 0

    var sessionTarget: Int? {
        settings.levelsPerSession > 0 ? settings.levelsPerSession : nil
    }

    init() {
        let loaded = CaregiverSettings.load()
        settings = loaded
        knob = loaded.startingDifficulty.knob
        phase = loaded.hasCompletedFirstRun ? .preparing : .firstRun
    }

    // MARK: - Lifecycle

    func start() async {
        guard phase != .firstRun else { return }
        await prepare()
    }

    func completeFirstRun() async {
        settings.hasCompletedFirstRun = true
        settings.save()
        phase = .preparing
        await prepare()
    }

    func requestPhotoAccess() async {
        await library.requestAccess()
    }

    /// Rebuild the photo index and start a session. Safe to re-run any time.
    func prepare() async {
        phase = .preparing
        if library.access == .notDetermined {
            await library.requestAccess()
        }
        await library.reload(settings: settings)
        refreshPools()

        // Geocoding happens in the background; Places simply gets better as it lands.
        Task { [weak self] in
            guard let self else { return }
            await places.resolveClusters(in: library.photos, limit: 10)
            refreshPools()
            if case .playing = phase, level == nil { nextLevel() }
        }

        guard !availableThemes.isEmpty else {
            phase = .noContent(noContentReason())
            return
        }
        beginSession()
    }

    /// The caregiver changed the starting difficulty — drop the adaptive drift.
    func resetDifficulty() {
        knob = settings.startingDifficulty.knob
        availableThemes = generator.availableThemes(knob: knob)
    }

    func applySettingsChange() async {
        settings.save()
        knob.photoCount = settings.startingDifficulty.knob.photoCount
        await library.reload(settings: settings)
        refreshPools()
        if availableThemes.isEmpty {
            phase = .noContent(noContentReason())
        } else if case .noContent = phase {
            beginSession()
        }
    }

    private func refreshPools() {
        generator.personal = places.annotate(library.photos)
        generator.pack = PublicPackLibrary.photos(enabledPackIDs: settings.enabledPackIDs)
        availableThemes = generator.availableThemes(knob: knob)
    }

    private func noContentReason() -> String {
        if !library.access.canRead && settings.enabledPackIDs.isEmpty {
            return "Photo Chronology needs either photo access or at least one photo pack turned on."
        }
        if !library.access.canRead {
            return "No photo access yet, and the chosen packs don't have enough photos."
        }
        return "This photo selection is too small to build a level. Try including more albums or turning on a photo pack."
    }

    // MARK: - Session

    private func beginSession() {
        levelsThisSession = 0
        sessionLevelTotal = 0
        stats.recordSessionStart()
        telemetry.record(EngagementEvent(kind: .sessionStart))
        phase = .playing
        nextLevel()
    }

    func continueSession() {
        levelsThisSession = 0
        phase = .playing
        nextLevel()
    }

    func endSession() {
        telemetry.record(EngagementEvent(kind: .sessionEnd,
                                         levelsInSession: sessionLevelTotal))
        Task { await telemetry.flush() }
        phase = .sessionComplete
    }

    // MARK: - Levels

    private func chooseTheme() -> GameTheme? {
        guard !availableThemes.isEmpty else { return nil }
        guard availableThemes.count > 1 else { return availableThemes[0] }
        // Alternate themes most of the time so a session doesn't feel like one long drill.
        if let last = lastTheme, Double.random(in: 0...1) < 0.7 {
            return availableThemes.first { $0 != last } ?? availableThemes.randomElement()
        }
        return availableThemes.randomElement()
    }

    private func nextLevel() {
        attempts = 0
        wrongIDs = []
        answeredCorrectly = false

        guard let theme = chooseTheme() else {
            phase = .noContent(noContentReason())
            return
        }

        var generated = generator.makeLevel(theme: theme, knob: knob)
        if generated == nil {
            // Theme dried up (Places often does) — drop it and try the others.
            availableThemes.removeAll { $0 == theme }
            for fallback in availableThemes {
                if let level = generator.makeLevel(theme: fallback, knob: knob) {
                    generated = level
                    break
                }
            }
        }

        guard let level = generated else {
            phase = .noContent(noContentReason())
            return
        }

        lastTheme = level.theme
        levelIndex = levelCounter
        levelCounter += 1
        levelStarted = Date()
        self.level = level
    }

    // MARK: - Answering

    enum Feedback {
        case correct
        case tryAgain
        case ignored
    }

    /// Wrong taps dim the tile and invite another try — no penalty, no fail state (spec §3.1).
    @discardableResult
    func select(_ photo: GamePhoto) -> Feedback {
        guard let level, !answeredCorrectly else { return .ignored }
        attempts += 1

        guard photo.id == level.correctPhotoID else {
            wrongIDs.insert(photo.id)
            return .tryAgain
        }

        answeredCorrectly = true
        let elapsed = Date().timeIntervalSince(levelStarted)
        stats.recordLevelCompleted()
        sessionLevelTotal += 1

        telemetry.record(EngagementEvent(kind: .levelCompleted,
                                         theme: level.theme.rawValue,
                                         wasCorrect: attempts == 1,
                                         attempts: attempts,
                                         durationMS: Int(elapsed * 1000),
                                         difficulty: knob.level,
                                         photoSetSize: level.photos.count,
                                         blendedPackPhotos: level.usesPackPhotos))

        // Silent adaptation only (spec §2).
        knob.adapt(wasCorrect: attempts == 1, attempts: attempts)
        if settings.adaptiveTiming {
            knob.adaptToPace(seconds: elapsed)
        }
        availableThemes = generator.availableThemes(knob: knob)
        return .correct
    }

    /// "Show me different photos" — a fresh set without spending a slot in the session.
    func skip() {
        nextLevel()
    }

    func advance() {
        levelsThisSession += 1
        if let target = sessionTarget, levelsThisSession >= target {
            endSession()
        } else {
            nextLevel()
        }
    }

    // MARK: - Diagnostics (caregiver screen only)

    var diagnostics: [(String, String)] {
        var rows: [(String, String)] = [
            ("Photo access", accessDescription),
            ("Photos indexed", "\(library.photos.count)"),
            ("Geotagged", "\(library.photos.filter { $0.coordinate != nil }.count)"),
            ("Places resolved", "\(places.cache.count) location clusters"),
            ("Pack photos in play",
             "\(PublicPackLibrary.photos(enabledPackIDs: settings.enabledPackIDs).count)"),
            ("Themes available",
             availableThemes.isEmpty ? "none" : availableThemes.map(\.title).joined(separator: ", ")),
            ("Difficulty knob", String(format: "%.2f", knob.level)),
            ("Current time window", ChronologyCurator.describe(knob.chronologyTargetGap)),
            ("Events queued", "\(telemetry.pending.count) (sent \(telemetry.sentCount))"),
            ("Telemetry sink", telemetry.sink.name),
        ]
        if let note = level?.curationNote {
            rows.append(("This level", note))
        }
        if let error = places.lastErrorDescription {
            rows.append(("Last geocoding error", error))
        }
        return rows
    }

    private var accessDescription: String {
        switch library.access {
        case .granted: "Full library"
        case .limited: "Limited selection"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        }
    }
}
