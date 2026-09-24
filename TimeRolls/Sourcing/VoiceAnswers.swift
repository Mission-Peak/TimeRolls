//
//  VoiceAnswers.swift
//  Time Rolls
//
//  Answering out loud: "two".
//
//  Tapping a photograph is the whole interface, and for some hands it is the hardest part
//  of the game — a tremor, arthritis, a finger that lands between two tiles. Every
//  photograph is numbered on screen, so saying the number is the same answer by another
//  route. Nobody has to: it sits alongside tapping and never replaces it.
//
//  Two rules it must not break:
//
//  **Nothing leaves the device.** `requiresOnDeviceRecognition` is set, and if this device
//  cannot recognise speech on its own then the feature does not run at all — it does not
//  quietly fall back to sending a care home's conversation to a server (spec §11).
//
//  **It listens only while a round is open, and only when switched on.** Not during the
//  reveal, not on the settings screens, never in the background.
//

import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class VoiceAnswers {

    enum Permission { case notAsked, allowed, refused, unavailable }

    private(set) var permission: Permission = .notAsked
    private(set) var isListening = false
    /// The last thing heard, for the caregiver screen — so "it isn't working" can be
    /// looked at rather than guessed at.
    private(set) var lastHeard: String?

    /// Called with the number the player said, 1-based.
    var onNumber: ((Int) -> Void)?
    /// Somebody asked for the next round out loud.
    var onNext: (() -> Void)?

    @ObservationIgnored private let recogniser = SFSpeechRecognizer(locale: Locale.current)
    /// Rebuilt every time listening starts.
    ///
    /// A long-lived engine resolves its input format once, when it is first touched — and
    /// that is before the audio session has become a recording session, so the format it
    /// remembers can be the wrong one or none at all. A fresh engine asks the session that
    /// is actually running now.
    @ObservationIgnored private var engine = AVAudioEngine()
    /// Whether this round still wants to be listened to, as opposed to the recogniser
    /// having simply stopped of its own accord.
    @ObservationIgnored private var wantsToListen = false
    /// What went wrong last, in words, for the caregiver screen.
    private(set) var lastProblem: String?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// Numbers already acted on in this round, so one "two" is not counted three times as
    /// the recogniser refines what it heard.
    @ObservationIgnored private var alreadySaid: Set<Int> = []

    func refreshPermission() {
        guard let recogniser, recogniser.supportsOnDeviceRecognition else {
            permission = .unavailable
            return
        }
        permission = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: AVAudioApplication.shared.recordPermission == .granted
            ? .allowed : .notAsked
        case .denied, .restricted: .refused
        case .notDetermined: .notAsked
        @unknown default: .unavailable
        }
    }

    func requestPermission() async {
        guard let recogniser, recogniser.supportsOnDeviceRecognition else {
            permission = .unavailable
            return
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            permission = speech == .notDetermined ? .notAsked : .refused
            return
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        permission = microphone ? .allowed : .refused
    }

    /// How many photographs this round has, so listening can be resumed after the voice
    /// has finished reading something out.
    @ObservationIgnored private var roundSize = 0

    /// Ignore what is heard while the app itself is talking.
    ///
    /// This replaces stopping and restarting the microphone around every spoken line,
    /// which is what broke this after it had been working: pausing was easy and resuming
    /// depended on a delegate callback arriving, and arriving in the right order against
    /// the next pause. Miss one and the game is deaf for the rest of the session with
    /// nothing on screen to say so.
    ///
    /// A deaf *window* cannot fail that way. The microphone stays open the whole time and
    /// numbers heard during the window are simply not acted on, so the worst case is that
    /// it ignores somebody for a second too long rather than for ever. The window is
    /// measured from the words themselves rather than from a callback, for the same
    /// reason — "Which walk came first?" ends in an ordinal, and a recogniser hearing the
    /// question would otherwise answer it.
    @ObservationIgnored private var ignoreUntil = Date.distantPast

    func holdOffWhile(saying text: String) {
        let words = max(text.split(separator: " ").count, 1)
        let spoken = min(max(Double(words) * 0.42, 1.2), 7)
        ignoreUntil = Date().addingTimeInterval(spoken + 0.4)
    }

    /// The voice finished early — start hearing again rather than waiting out the estimate.
    func stopHoldingOff() {
        ignoreUntil = min(ignoreUntil, Date().addingTimeInterval(0.3))
    }

    /// Start listening for this round. Safe to call again; it restarts.
    func listen(upTo count: Int) {
        roundSize = count
        // Ask the system what it has already been told, rather than trusting what this
        // object remembers.
        //
        // This is what stopped answering out loud from working. Permission was only ever
        // read when the caregiver screen opened, so it began every launch as "not asked":
        // somebody would allow the microphone, it would work beautifully for the rest of
        // that run, and then be deaf from the next launch onwards with the toggle still
        // showing on. The grant was never lost — only this object's memory of it was.
        if permission != .allowed { refreshPermission() }
        guard permission == .allowed else {
            lastProblem = "the microphone is not allowed for Time Rolls"
            return
        }
        guard let recogniser, recogniser.isAvailable else {
            lastProblem = "the recogniser is busy"
            return
        }
        wantsToListen = true
        stop(releasingSession: false)
        alreadySaid = []

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // The line that keeps a room's conversation on the device.
        request.requiresOnDeviceRecognition = true
        self.request = request

        SpokenAudio.prepareForListening()

        // A new engine each time, asked for its format *after* the session is recording.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            lastProblem = "the microphone reported no format"
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            lastProblem = "the microphone would not start"
            return
        }
        lastProblem = nil
        isListening = true

        task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let said = result.bestTranscription.formattedString
                    self.lastHeard = said
                    if Date() >= self.ignoreUntil {
                        if SpokenNumbers.asksForTheNextRound(said) {
                            self.onNext?()
                        } else if let number = SpokenNumbers.number(in: said, upTo: count),
                                  !self.alreadySaid.contains(number) {
                            self.alreadySaid.insert(number)
                            self.onNumber?(number)
                        }
                    }
                }
                if let error { self.lastProblem = Self.plainly(error) }
                // The recogniser finishes on its own after a stretch of quiet — it is
                // built for dictation, where somebody says a sentence and stops. Here the
                // quiet is the *normal* state: the question is read out, the player looks
                // at four photographs, thinks, and only then says a number. By the time
                // they speak, a dictation-shaped recogniser has long since closed.
                //
                // That is why this stopped hearing anybody. So when it ends by itself and
                // the round is still open, it starts again.
                if error != nil || result?.isFinal == true {
                    self.restartIfStillWanted(upTo: count)
                }
            }
        }
    }

    /// Begin again after the recogniser closed itself, as long as the round is still open.
    private func restartIfStillWanted(upTo count: Int) {
        guard wantsToListen, !isListening else { return }
        stop(releasingSession: false)
        Task { @MainActor in
            // A beat, so a recogniser that is failing repeatedly cannot spin.
            try? await Task.sleep(for: .milliseconds(400))
            guard wantsToListen else { return }
            listen(upTo: count)
        }
    }

    /// An error in words somebody can read out to me, rather than a number.
    nonisolated private static func plainly(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("1101") || text.lowercased().contains("no speech") {
            return "heard nothing"
        }
        if text.contains("kAFAssistantErrorDomain") { return "the recogniser gave up" }
        return text.prefix(70).description
    }

    /// What it is doing, for the caregiver screen — because "it isn't working" is very
    /// hard to act on and "on-device recognition isn't available" is not.
    var diagnostics: String {
        guard let recogniser else { return "No recogniser for this language" }
        var notes: [String] = []
        notes.append(recogniser.supportsOnDeviceRecognition
                     ? "on-device recognition ready" : "on-device recognition NOT available")
        notes.append(recogniser.isAvailable ? "recogniser available" : "recogniser busy")
        notes.append(isListening ? "listening now" : "not listening")
        if Date() < ignoreUntil { notes.append("holding off while the voice talks") }
        if let lastProblem { notes.append("last problem: \(lastProblem)") }
        return notes.joined(separator: " · ")
    }

    func stop() {
        stop(releasingSession: true)
    }

    func stop(releasingSession: Bool) {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isListening = false
        if releasingSession {
            wantsToListen = false
            roundSize = 0
            SpokenAudio.stopListening()
        }
    }

}
