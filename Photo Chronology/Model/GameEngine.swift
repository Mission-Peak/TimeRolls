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
    let objects = ObjectTagger()
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

    private(set) var generator = LevelGenerator()
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
        if settings.adoptNewPacks() {
            settings.save()
        }
        // Only ask for the photo library if the player actually wants their own photos
        // in play. Someone who chose the built-in sets has already answered this.
        if library.access == .notDetermined, settings.useAllPhotos {
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

        startTaggingIfWanted()

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
        startTaggingIfWanted()
        if availableThemes.isEmpty {
            phase = .noContent(noContentReason())
        } else if case .noContent = phase {
            beginSession()
        } else if case .playing = phase {
            // The photos on screen may have just been switched off — deal a fresh set
            // rather than leaving a level built from sources that are no longer in play.
            nextLevel()
        }
    }

    private func refreshPools() {
        generator.personal = objects.annotate(places.annotate(library.photos))
        generator.pack = PublicPackLibrary.photos(enabledPackIDs: settings.enabledPackIDs)
        generator.allowObjects = settings.objectsThemeEnabled
        availableThemes = generator.availableThemes(knob: knob)
    }

    /// Classification is incremental: each chunk of photos that comes back can unlock
    /// the Objects theme mid-session, so a first run doesn't wait on the whole library.
    private func startTaggingIfWanted() {
        guard settings.objectsThemeEnabled, library.access.canRead else {
            objects.stop()
            return
        }
        objects.startTagging(library.photos) { [weak self] in
            guard let self else { return }
            refreshPools()
            if case .noContent = phase, !availableThemes.isEmpty {
                beginSession()
            }
        }
    }

    private func noContentReason() -> String {
        if !library.access.canRead && settings.enabledPackIDs.isEmpty {
            return "iRecollect needs either photo access or at least one photo pack turned on."
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
        stats.recordSessionStart(together: settings.togetherMode)
        telemetry.record(EngagementEvent(kind: .sessionStart,
                                         togetherMode: settings.togetherMode))
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
                                         levelsInSession: sessionLevelTotal,
                                         togetherMode: settings.togetherMode))
        Task { await telemetry.flush() }
        phase = .sessionComplete
    }

    // MARK: - Levels

    private func chooseTheme() -> GameTheme? {
        // A theme the player picked wins over the rotation, as long as it can still
        // be played with the photos currently in play.
        if let pinned = settings.pinnedTheme, availableThemes.contains(pinned) {
            return pinned
        }
        return ThemeRotation.next(from: availableThemes, last: lastTheme)
    }

    // MARK: - What the player chose

    /// nil pins nothing — the app mixes the themes, which is the default.
    func choose(theme: GameTheme?) {
        settings.pinnedTheme = theme
        settings.save()
        if case .playing = phase { nextLevel() }
    }

    /// The first-run choice made by someone playing without their own photos. Applied
    /// before the session starts, so it doesn't reload the library twice.
    func applyOnboardingChoice(packIDs: Set<String>) async {
        settings.useAllPhotos = false
        settings.enabledPackIDs = packIDs
        settings.knownPackIDs.formUnion(PublicPackLibrary.packs.map(\.id))
        settings.save()
        await completeFirstRun()
    }

    /// Which sets of photos are in play. `useOwnPhotos` is ignored without access.
    func chooseSources(useOwnPhotos: Bool, packIDs: Set<String>) {
        Task {
            // Turning their own photos on is the moment to ask for access, not before.
            if useOwnPhotos, library.access == .notDetermined {
                await library.requestAccess()
            }
            settings.useAllPhotos = useOwnPhotos && library.access.canRead
            settings.enabledPackIDs = packIDs
            // Remember every pack we offered, so the new-pack migration doesn't switch
            // the ones they turned down back on at the next launch.
            settings.knownPackIDs.formUnion(PublicPackLibrary.packs.map(\.id))
            settings.save()
            await applySettingsChange()
        }
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
                                         blendedPackPhotos: level.usesPackPhotos,
                                         togetherMode: settings.togetherMode))

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

    /// The annotated pool, for the coverage report.
    var taggedPool: [GamePhoto] {
        generator.personal + generator.pack
    }

    /// Throws away every cached label and looks again — for testing allow-list changes.
    func reclassifyPhotos() {
        objects.reset()
        refreshPools()
        startTaggingIfWanted()
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
            ("Photos looked at", objectsProgress),
            ("Things found", objectsFound),
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

    private var objectsProgress: String {
        guard settings.objectsThemeEnabled else { return "off" }
        if objects.unavailableReason != nil {
            return "classifier unavailable — packs only"
        }
        let pending = objects.pendingCount(in: library.photos)
        let done = library.photos.count - pending
        return pending > 0
            ? "\(done) of \(library.photos.count) (working…)"
            : "\(done) of \(library.photos.count)"
    }

    private var objectsFound: String {
        let found = objects.coverage(in: generator.personal + generator.pack)
            .filter { $0.matches > 0 }
        guard !found.isEmpty else { return "none yet" }
        return "\(found.count) categories, top: \(found.prefix(3).map(\.category.displayName).joined(separator: ", "))"
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
