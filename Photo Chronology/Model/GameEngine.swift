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
    /// The kind of question the player picked from the chip. Deliberately not saved:
    /// it lasts for this session and goes back to a mix at the next one, so nobody
    /// returns to find the app narrowed to one theme by a choice they've forgotten.
    private(set) var pinnedTheme: GameTheme?

    /// Computed, so flipping the caregiver's black-and-white setting shows up at once.
    var isMonochromeLevel: Bool {
        settings.shouldUseMonochrome(levelIndex: levelIndex)
    }

    private(set) var generator = LevelGenerator()
    /// A level generated and made ready in the background, so photographs that live
    /// online are already on the device before anyone sees the round.
    private var pendingLevel: Level?
    private var prepareTask: Task<Void, Never>?
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
        var settingsChanged = settings.adoptNewPacks()
        settingsChanged = settings.healOrphanedPackChoices() || settingsChanged
        if settingsChanged {
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
        // It keeps going in waves rather than stopping after the first handful: until
        // enough of the player's own places are named, Places counts as sparse and the
        // photo packs carry it, which is not what anyone wants from a library full of
        // real holidays.
        Task { [weak self] in
            guard let self else { return }
            repeat {
                await places.resolveClusters(in: library.photos, limit: 25)
                refreshPools()
                if case .playing = phase, level == nil { nextLevel() }
            } while places.hasUnresolvedClusters(in: library.photos) && !Task.isCancelled
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
        let unavailable = RemoteImageCache.shared.unavailable
        generator.pack = PublicPackLibrary.photos(enabledPackIDs: settings.enabledPackIDs)
            .filter { photo in
                guard case let .pack(_, itemID) = photo.origin else { return true }
                return !unavailable.contains(itemID)
            }
        generator.allowObjects = settings.objectsThemeEnabled
        generator.packThemeSupport = PublicPackLibrary.packThemeSupport()
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
        // Every session starts on a mix, whatever was pinned last time.
        pinnedTheme = nil
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
        if let pinned = pinnedTheme, availableThemes.contains(pinned) {
            return pinned
        }
        return ThemeRotation.next(from: availableThemes, last: lastTheme)
    }

    // MARK: - What the player chose

    /// nil pins nothing — the app mixes the themes, which is the default.
    func choose(theme: GameTheme?) {
        pinnedTheme = theme
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

        // A level prepared during the last round is ready to go now.
        if let ready = pendingLevel {
            pendingLevel = nil
            install(ready)
            prepareUpcoming()
            return
        }

        guard let level = generateLevel() else {
            phase = .noContent(noContentReason())
            return
        }
        install(level)

        Task { [weak self] in
            guard let self else { return }
            await ensurePhotographs(for: level)
            prepareUpcoming()
        }
    }

    private func install(_ level: Level) {
        lastTheme = level.theme
        levelIndex = levelCounter
        levelCounter += 1
        levelStarted = Date()
        self.level = level
    }

    private func generateLevel() -> Level? {
        guard let theme = chooseTheme() else { return nil }
        if let level = generator.makeLevel(theme: theme, knob: knob) { return level }

        // Theme dried up (Places often does) — drop it and try the others.
        availableThemes.removeAll { $0 == theme }
        for fallback in availableThemes {
            if let level = generator.makeLevel(theme: fallback, knob: knob) { return level }
        }
        return nil
    }

    /// Build the next round ahead of time and make sure its photographs are on the
    /// device, so moving on is instant even when a pack is carried as metadata only.
    private func prepareUpcoming() {
        prepareTask?.cancel()
        prepareTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<3 {
                guard !Task.isCancelled, let candidate = generateLevel() else { return }
                if await ensurePhotographs(for: candidate) {
                    pendingLevel = candidate
                    return
                }
                // Something in that set couldn't be fetched; those photographs are out
                // of the pool now, so try again with what's left.
            }
        }
    }

    /// Fetch any photographs this level needs. Returns false if some couldn't be had.
    @discardableResult
    private func ensurePhotographs(for level: Level) async -> Bool {
        let items = level.photos.compactMap { photo -> PackItem? in
            guard case let .pack(packID, itemID) = photo.origin else { return nil }
            return PublicPackLibrary.item(packID: packID, itemID: itemID)
        }
        .filter { $0.remoteURL != nil && !RemoteImageCache.shared.isAvailableOffline($0) }
        guard !items.isEmpty else { return true }

        let before = RemoteImageCache.shared.unavailable
        await RemoteImageCache.shared.prefetch(items)
        let newlyUnavailable = RemoteImageCache.shared.unavailable.subtracting(before)
        guard newlyUnavailable.isEmpty else {
            refreshPools()       // keep the dead ones out of future rounds
            return false
        }
        return true
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
        if let level {
            rows.append(("This level", level.curationNote))
            rows.append(("Photos in this level", generator.packShare(of: level)))
        }
        rows.append(("Photos fetched and kept",
                     "\(RemoteImageCache.shared.cachedCount) "
                        + "(\(RemoteImageCache.shared.bytesOnDisk / 1_000_000) MB)"))
        rows.append(("Places still to name",
                     places.hasUnresolvedClusters(in: library.photos) ? "working…" : "all done"))
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
