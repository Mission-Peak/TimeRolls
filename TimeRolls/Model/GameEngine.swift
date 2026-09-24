//
//  GameEngine.swift
//  Time Rolls
//
//  Owns the session: curation, feedback, adaptive difficulty, telemetry (spec §3).
//  Nothing here penalises the player — no scores, no fail states, no visible clock.
//

import Foundation
import Observation
import UIKit

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
    let audit = RoundAudit()
    let narrator = Narrator()
    let intake = PhotoIntake()
    let voiceAnswers = VoiceAnswers()
    let stats = StatsStore()
    let telemetry = TelemetryQueue()
    /// Apple's on-device model, allowed to reword a question and nothing else.
    let phrasing = QuestionPhrasing()

    // State
    var settings: CaregiverSettings
    private(set) var phase: Phase = .preparing
    private(set) var level: Level?
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
    /// Notable places near this iPad, when the caregiver has asked for them.
    let localTrivia = LocalTrivia()
    /// A level generated and made ready in the background, so photographs that live
    /// online are already on the device before anyone sees the round.
    private var pendingLevel: Level?
    private var prepareTask: Task<Void, Never>?
    private var levelStarted = Date()
    private var levelCounter = 0
    private var lastTheme: GameTheme?
    private var sessionLevelTotal = 0

    init() {
        let loaded = CaregiverSettings.load()
        settings = loaded
        phase = loaded.hasCompletedFirstRun ? .preparing : .firstRun
    }

    // MARK: - Lifecycle

    func start() async {
        // Pack photographs are classified when the pack is built, but the wording of the
        // question comes from the shipped theme table, so a table that gets rephrased does
        // not need every pack rebuilt. This is where the two meet.
        GamePhoto.identifyQuestion = { id in
            PhotoThemeIndex.shared.themes.first { $0.id == id }?.identify
        }
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

    /// Ask for nearby places, if the caregiver has switched Local Trivia on. Nothing
    /// waits on it — the answer arrives later and joins the pool on the next refresh.
    func startLocalTriviaIfWanted() {
        guard settings.localTriviaEnabled else { return }
        localTrivia.begin()
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
    func applySettingsChange() async {
        settings.save()
        await library.reload(settings: settings)
        refreshPools()
        startTaggingIfWanted()
        startLocalTriviaIfWanted()
        if availableThemes.isEmpty {
            phase = .noContent(noContentReason())
        } else if case .noContent = phase {
            beginSession()
        } else if case .playing = phase {
            // The photos on screen may have just been switched off — deal a fresh set
            // rather than leaving a level built from sources that are no longer in play.
            discardPreparedLevel()
            nextLevel()
        }
    }

    private func refreshPools() {
        // Photographs that could not be fetched last time are not offered again: an
        // iCloud photograph that will not come down is a blank card, and a blank card
        // is a question nobody can answer.
        generator.excluded = settings.excludedPhotoIDs
        generator.missedPairings = stats.stats.missedPairings
        generator.setAsideByDescription = Set(
            intake.verdicts.filter { $0.value.setAsideBecause != nil }.map(\.key))
        // Yesterday's rotation has no claim on somebody's storage.
        RemoteImageCache.shared.pruneToBudget()
        let readable = library.photos.filter { !images.unavailablePersonalIDs.contains($0.id) }
        generator.personal = objects.annotate(places.annotate(readable))
        let unavailable = RemoteImageCache.shared.unavailable
        generator.pack = PublicPackLibrary.photos(enabledPackIDs: settings.enabledPackIDs)
            .filter { photo in
                guard case let .pack(_, itemID) = photo.origin else { return true }
                return !unavailable.contains(itemID)
            }
        // Local Trivia joins the pool like any other pack once it has arrived.
        if settings.localTriviaEnabled, let local = localTrivia.pack {
            generator.pack += local.items.map { item in
                GamePhoto(id: "pack:\(local.id):\(item.id)",
                          origin: .pack(packID: local.id, itemID: item.id),
                          creationDate: nil,
                          coordinate: item.coordinate,
                          placeName: item.placeName,
                          subject: nil,
                          title: item.credit?.title,
                          fact: item.fact)
            }
        }
        generator.packThemeSupport = PublicPackLibrary.packThemeSupport()
        generator.packChronologyPrompts = PublicPackLibrary.chronologyPrompts()
        generator.birthDatedPacks = PublicPackLibrary.birthDatedPackIDs()
        generator.examinesPhotos = objects.unavailableReason == nil
        generator.visualDistance = { [objects] first, second in
            objects.visualDistance(first.id, second.id)
        }
        generator.conceptScore = { [objects] photo, concept in
            objects.conceptScore(photo.id, concept: concept)
        }
        generator.showsAPlace = { [objects] photo in
            objects.showsAPlace(photo.id)
        }
        generator.bestConcept = { [objects] photo in
            objects.bestConcept(photo.id)
        }
        availableThemes = generator.availableThemes()
    }

    /// Classification is incremental: each chunk of photos that comes back can unlock
    /// the Objects theme mid-session, so a first run doesn't wait on the whole library.
    private func startTaggingIfWanted() {
        guard library.access.canRead else {
            objects.stop()
            return
        }
        objects.startTagging(library.photos) { [weak self] in
            guard let self else { return }
            refreshPools()
            if case .noContent = phase, !availableThemes.isEmpty {
                beginSession()
            }
            // Describe a few more once the classifier has finished a chunk, so the two
            // passes take turns rather than competing for the device.
            describeAFewMore()
        }
    }

    private func noContentReason() -> String {
        if !library.access.canRead && settings.enabledPackIDs.isEmpty {
            return "Time Rolls needs either photo access or at least one photo pack turned on."
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
        // The round waiting in the wings was built for the old choice — throw it away,
        // or picking "Places" hands you one more round of something else first.
        discardPreparedLevel()
        if case .playing = phase { nextLevel() }
    }

    /// Forget anything prepared in the background, after a change that would have
    /// produced a different round.
    private func discardPreparedLevel() {
        prepareTask?.cancel()
        prepareTask = nil
        pendingLevel = nil
    }

    /// The first-run choice made by someone playing without their own photos. Applied
    /// before the session starts, so it doesn't reload the library twice.
    /// Record the pack choice without finishing onboarding — the voice step comes after.
    func applyOnboardingChoice(packIDs: Set<String>) {
        settings.useAllPhotos = false
        settings.enabledPackIDs = packIDs
        settings.knownPackIDs.formUnion(PublicPackLibrary.packs.map(\.id))
        settings.save()
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
        remember(level)
        startListeningIfWanted(for: level)
    }

    /// Listen for a spoken number, for this round only.
    ///
    /// A number said out loud is the same answer as a tap, so it goes through `select`
    /// exactly as a tap does — same wrong-answer handling, same stars, same everything. A
    /// second route to the same door, never a different door.
    /// Pick the microphone up for the round in play, if the player asked to answer aloud.
    /// Used when the sound switch is turned back on mid-round.
    func startListeningIfWanted() {
        guard let level else { return }
        startListeningIfWanted(for: level)
    }

    private func startListeningIfWanted(for level: Level) {
        guard settings.voiceAnswers else { return }
        narrator.onFinishedSpeaking = { [weak self] in self?.voiceAnswers.stopHoldingOff() }
        voiceAnswers.onNumber = { [weak self] number in
            guard let self, let level = self.level, !self.answeredCorrectly else { return }
            guard number >= 1, number <= level.photos.count else { return }
            select(level.photos[number - 1])
        }
        voiceAnswers.onNext = { [weak self] in
            guard let self, self.answeredCorrectly else { return }
            advance()
        }
        voiceAnswers.listen(upTo: level.photos.count)
    }

    @ObservationIgnored private var lastSpokenLine: String?

    /// Read the round's question aloud — on the way in, and whenever "Again" is pressed.
    ///
    /// Everything spoken goes through here or `say`, so the microphone is always told to
    /// hold off. A view that reaches past this and talks to the narrator directly is a
    /// view that makes the game answer its own question.
    func speakQuestion() {
        guard let level else { return }
        say(level.livelyPrompt ?? level.prompt)
    }

    /// Say something to the player, if they asked to be spoken to.
    private func say(_ line: String) {
        guard settings.narration, !line.isEmpty else { return }
        lastSpokenLine = line
        // Deafen the microphone for roughly as long as this takes to say, so it does not
        // hear the game and answer on the player's behalf.
        voiceAnswers.holdOffWhile(saying: line)
        narrator.say(line, voiceIdentifier: settings.voiceIdentifier)
    }

    /// Ask the on-device model about a handful of photographs the rules have already let
    /// through. Downstream of every filter, and only ever able to remove.
    private func describeAFewMore() {
        let candidates = generator.personal.filter {
            !settings.excludedPhotoIDs.contains($0.id) && !$0.looksLikeDocument
        }
        intake.start(on: candidates, using: images)
    }

    /// Whether setup is open over the top of a round in progress.
    ///
    /// A session does not stop just because somebody opened setup. The round kept its
    /// countdown running behind the sheet, so a caregiver changing the text size would
    /// close it and find the game two questions further on than they left it, with the
    /// player none the wiser about what happened to their photograph. Nothing should move
    /// while somebody is looking at something else.
    private(set) var isPaused = false

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        narrator.stop()
        voiceAnswers.stop()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        // Pick the microphone back up if it was listening, but do not start talking again
        // — the question was read out before the interruption and repeating it unasked is
        // the app talking over whatever was going on in the room.
        if let level { startListeningIfWanted(for: level) }
    }

    /// Stop listening the moment the round is over — the microphone has no business being
    /// open while somebody reads the answer, talks to whoever is with them, or puts the
    /// iPad down.
    func stopListening() {
        voiceAnswers.stop()
    }

    /// How many photographs back the generator remembers. Long enough to cover a
    /// session — eight rounds of four or five — so the same faces don't come round
    /// again while somebody is still playing.
    private static let recentWindow = 60
    private var recentOrder: [String] = []

    /// The photographs lately shown, newest first, so a caregiver can strike one off
    /// without having to catch it during a round. Kept in memory only: it is a view of
    /// this session, not a second copy of anybody's library.
    private(set) var recentlyShown: [GamePhoto] = []

    /// Never show this photograph again, and take it out of play immediately.
    func exclude(_ photo: GamePhoto) {
        settings.excludedPhotoIDs.insert(photo.id)
        settings.save()
        recentlyShown.removeAll { $0.id == photo.id }
        // The next round is built while the last one is being played, so by the time
        // somebody strikes a photograph off it may already be sitting in a round nobody
        // has seen yet. Filtering the pool would not touch that one, and it would come
        // up once more — which, for the photograph somebody has just asked never to see
        // again, is the only failure that really matters here.
        if pendingLevel?.photos.contains(where: { $0.id == photo.id }) == true {
            pendingLevel = nil
        }
        refreshPools()
        prepareUpcoming()
    }

    /// Every photograph the game could draw on, newest first.
    ///
    /// Not what has been shown — what *could* be. Reviewing after the fact is shutting a
    /// gate the player has already walked through, and for the photographs this control
    /// exists for, being seen once is the whole of the harm.
    var reviewablePhotos: [GamePhoto] {
        generator.personal.sorted {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
    }

    /// Photographs from the same day as this one, so one decision can cover a whole
    /// afternoon. A hospital visit, a funeral, a last Christmas — the thing somebody
    /// wants left out is almost never a single frame, and asking them to find each one
    /// among nine hundred is asking them to give up.
    func sameDay(as photo: GamePhoto) -> [GamePhoto] {
        guard let date = photo.creationDate else { return [] }
        let calendar = Calendar.current
        return generator.personal.filter {
            guard let other = $0.creationDate else { return false }
            return calendar.isDate(other, inSameDayAs: date)
        }
    }

    func sameMonth(as photo: GamePhoto) -> [GamePhoto] {
        guard let date = photo.creationDate else { return [] }
        let calendar = Calendar.current
        return generator.personal.filter {
            guard let other = $0.creationDate else { return false }
            return calendar.isDate(other, equalTo: date, toGranularity: .month)
        }
    }

    /// Photographs taken near this one — the ward, the house, the church.
    func samePlace(as photo: GamePhoto, within metres: Double = 500) -> [GamePhoto] {
        guard let here = photo.coordinate else { return [] }
        return generator.personal.filter {
            guard let there = $0.coordinate else { return false }
            return here.distance(to: there) <= metres
        }
    }

    /// Strike off many at once. Returns how many were newly left out.
    @discardableResult
    func exclude(_ photos: [GamePhoto]) -> Int {
        let ids = Set(photos.map(\.id)).subtracting(settings.excludedPhotoIDs)
        guard !ids.isEmpty else { return 0 }
        settings.excludedPhotoIDs.formUnion(ids)
        settings.save()
        recentlyShown.removeAll { ids.contains($0.id) }
        if pendingLevel?.photos.contains(where: { ids.contains($0.id) }) == true {
            pendingLevel = nil
        }
        refreshPools()
        prepareUpcoming()
        return ids.count
    }

    func allowAgain(_ id: String) {
        settings.excludedPhotoIDs.remove(id)
        settings.save()
        refreshPools()
    }

    /// How many Things subjects back to remember. Long enough that a short session
    /// never repeats a question, short enough that a small catalogue still has somewhere
    /// to go.
    private static let recentCategoryWindow = 6
    private var recentCategoryOrder: [String] = []

    private var recentPlaceOrder: [String] = []

    private func remember(_ level: Level) {
        if let tag = level.focusTag {
            // Each theme remembers its own questions. They were sharing one list, which
            // was harmless only because Places never wrote to it.
            switch level.theme {
            case .places:
                recentPlaceOrder = Self.rememberAsked(tag, in: recentPlaceOrder)
                generator.recentPlaces = recentPlaceOrder
            case .objects, .chronology:
                recentCategoryOrder = Self.rememberAsked(tag, in: recentCategoryOrder)
                generator.recentCategories = recentCategoryOrder
            }
        }
        rememberPhotos(level)
    }

    private static func rememberAsked(_ tag: String, in order: [String]) -> [String] {
        var order = order.filter { $0 != tag }
        order.append(tag)
        if order.count > recentCategoryWindow {
            order.removeFirst(order.count - recentCategoryWindow)
        }
        return order
    }

    /// The photographs from the round just played, for the end-of-session screen.
    private(set) var lastLevelPhotos: [GamePhoto] = []

    /// The player's own photographs seen this session, newest first.
    ///
    /// The whole point of the game is that it brings up pictures somebody had forgotten
    /// they owned. Finding one again and then having to go hunting through Photos to send
    /// it to anybody is the moment lost, so the end of a session offers them directly.
    ///
    /// Only their own. A pack photograph is a public-domain picture of a stranger's
    /// wedding, and nobody wants to send that to their daughter.
    private(set) var ownPhotosThisSession: [GamePhoto] = []

    /// Cleared at the start of a session, and capped — this is what somebody has just
    /// looked at, not an archive.
    private static let sharableWindow = 12

    private func rememberPhotos(_ level: Level) {
        lastLevelPhotos = level.photos
        for photo in level.photos where photo.isPersonal {
            ownPhotosThisSession.removeAll { $0.id == photo.id }
            ownPhotosThisSession.insert(photo, at: 0)
        }
        if ownPhotosThisSession.count > Self.sharableWindow {
            ownPhotosThisSession.removeLast(ownPhotosThisSession.count - Self.sharableWindow)
        }
        for photo in level.photos where !recentOrder.contains(photo.id) {
            recentOrder.append(photo.id)
        }
        for photo in level.photos where !recentlyShown.contains(where: { $0.id == photo.id }) {
            recentlyShown.insert(photo, at: 0)
        }
        if recentlyShown.count > Self.recentWindow {
            recentlyShown.removeLast(recentlyShown.count - Self.recentWindow)
        }
        if recentOrder.count > Self.recentWindow {
            recentOrder.removeFirst(recentOrder.count - Self.recentWindow)
        }
        generator.recentlyUsed = Set(recentOrder)
    }

    private func generateLevel() -> Level? {
        guard let theme = chooseTheme() else { return nil }
        if let level = generator.makeLevel(theme: theme) { return level }

        // Theme dried up (Places often does) — drop it and try the others.
        availableThemes.removeAll { $0 == theme }
        for fallback in availableThemes {
            if let level = generator.makeLevel(theme: fallback) { return level }
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
                guard !Task.isCancelled, var candidate = generateLevel() else { return }
                if await ensurePhotographs(for: candidate) {
                    // A round the model can't answer is one the player can't answer.
                    // Dropping it here is free: nobody is waiting on this round yet,
                    // and there are two more tries before we ship whatever we have.
                    if settings.checkedRounds,
                       await !audit.approves(candidate, using: images) {
                        continue
                    }
                    // Reworded while the player is still on the round before this one,
                    // so the question never changes under their eyes and a slow model
                    // never holds anything up.
                    if settings.livelyQuestions {
                        candidate.livelyPrompt = await phrasing.phrasing(for: candidate)
                    }
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
            // Asked once, got wrong, never asked again — the subject and this answer
            // together, so the photograph stays usable elsewhere.
            if let subject = level.focusTag, !subject.isEmpty {
                stats.rememberMissed(subject: subject, answer: level.correctPhotoID)
                generator.missedPairings = stats.stats.missedPairings
            }
            say(Encouragement.next(from: Encouragement.tryAgain, after: lastSpokenLine))
            return .tryAgain
        }

        answeredCorrectly = true
        voiceAnswers.stop()
        say(Encouragement.next(from: Encouragement.praise, after: lastSpokenLine))
        let elapsed = Date().timeIntervalSince(levelStarted)
        stats.recordLevelCompleted()
        // Counted here, shown only in How's it going: the game itself stays without a
        // score, which is the whole point of it.
        stats.recordStars(firstTime: attempts == 1)
        sessionLevelTotal += 1

        telemetry.record(EngagementEvent(kind: .levelCompleted,
                                         theme: level.theme.rawValue,
                                         wasCorrect: attempts == 1,
                                         attempts: attempts,
                                         durationMS: Int(elapsed * 1000),
                                         photoSetSize: level.photos.count,
                                         blendedPackPhotos: level.usesPackPhotos))

        availableThemes = generator.availableThemes()
        return .correct
    }

    /// "Show me different photos" — a fresh set without spending a slot in the session.
    func skip() {
        nextLevel()
    }

    func advance() {
        levelsThisSession += 1
        if hasJustFinishedTodaysChallenge() {
            endSession()
        } else {
            nextLevel()
        }
    }

    /// Whether this is the moment the day's challenge was met, and it has not been
    /// marked yet.
    ///
    /// The game used to stop every eight rounds whatever was going on, which turned a
    /// good afternoon into a series of interruptions and gave somebody who wanted to keep
    /// playing a screen to get past. Now there is one stopping point in a day: the moment
    /// the challenge is finished. After that the session runs for as long as anybody
    /// wants, and the congratulations do not come round again until tomorrow.
    private func hasJustFinishedTodaysChallenge() -> Bool {
        let goal = settings.dailyCardGoal
        guard goal > 0 else { return false }
        guard settings.lastCelebratedDay != StatsStore.today else { return false }
        guard stats.hasMetChallenge(goal: goal) else { return false }
        settings.lastCelebratedDay = StatsStore.today
        settings.save()
        return true
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
}
