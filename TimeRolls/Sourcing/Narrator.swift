//
//  Narrator.swift
//  Time Rolls
//
//  Reading the question aloud (spec §6).
//
//  For somebody who can see the photographs perfectly well but finds a line of text hard
//  work — failing eyesight, a stroke, or simply a tiring afternoon — the question is the
//  part of this game that stops working first. The photographs already carry themselves.
//
//  Everything here is on-device `AVSpeechSynthesizer`, so it works in a care home with no
//  signal and costs nothing per round. The voice matters more than usual: the standard
//  one is a robot, and Apple's Enhanced and Premium voices are genuinely warm. The app
//  cannot install them — there is no API to download a voice, and none to deep-link to
//  the screen that does — so it uses the best one already on the device and the caregiver
//  setup step explains, in words and pictures, how to get a better one.
//

import AVFoundation
import Observation

@Observable
@MainActor
final class Narrator {

    /// A voice offered in the picker.
    struct Choice: Identifiable, Hashable {
        let id: String
        let name: String
        /// "Premium", "Enhanced", or "Standard" — worth showing, because it is the whole
        /// difference between a person and a robot, and it is what the caregiver is being
        /// asked to go and download.
        let quality: String
        let isBest: Bool
        /// A voice somebody recorded of themselves, through Settings → Accessibility →
        /// Personal Voice.
        let isPersonal: Bool
        /// The language it speaks, written out — "Spanish (Spain)".
        let language: String
        /// Whether that is the language this device is set to.
        let isThisLanguage: Bool
    }

    /// Whether this app may use a voice the user recorded of themselves.
    ///
    /// Personal Voice is hidden from apps until it is asked for: the voices simply do not
    /// appear in `speechVoices()` while the status is anything but authorised. So an app
    /// that never asks will honestly report that no such voice exists, which is what this
    /// one did until somebody said they had recorded one.
    enum PersonalVoice {
        case notAsked, allowed, refused, unsupported
    }

    private(set) var personalVoice: PersonalVoice = .notAsked

    func refreshPersonalVoiceStatus() {
        personalVoice = switch AVSpeechSynthesizer.personalVoiceAuthorizationStatus {
        case .authorized: .allowed
        case .denied: .refused
        case .unsupported: .unsupported
        case .notDetermined: .notAsked
        @unknown default: .unsupported
        }
    }

    /// Ask once. The system puts up its own prompt and remembers the answer, so calling
    /// this again after a refusal does nothing — which is why the screen has to explain
    /// where Settings is rather than offering the button twice.
    func requestPersonalVoice() async {
        let status = await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        personalVoice = switch status {
        case .authorized: .allowed
        case .denied: .refused
        case .unsupported: .unsupported
        case .notDetermined: .notAsked
        @unknown default: .unsupported
        }
    }

    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesiser = AVSpeechSynthesizer()
    @ObservationIgnored private let watcher = SpeechWatcher()

    init() {
        synthesiser.delegate = watcher
        watcher.onFinish = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.onFinishedSpeaking?()
        }
    }

    /// Slower than Apple's default, which is pitched for someone scanning a notification.
    /// This is a question being asked of an eighty-year-old, and it is asked once.
    private let rate = AVSpeechUtteranceDefaultSpeechRate * 0.9

    /// Every voice on this device that speaks the player's language, best first.
    ///
    /// Matched on language only, not region: someone whose phone is set to en-GB and who
    /// has downloaded an en-AU voice should be offered it rather than told there is
    /// nothing. A voice in the wrong accent is a smaller problem than no voice at all.
    /// The voices worth offering in the language this device is set to.
    var available: [Choice] { choices(inThisLanguage: true) }

    /// Every other language with a voice installed — about fifty of them on a new device.
    ///
    /// Offered because plenty of people the game is for did not grow up speaking the
    /// language their iPad is set to, and a familiar accent reading the question is worth
    /// something even while the words themselves stay English. The screen says so plainly
    /// rather than implying the game has been translated, which it has not.
    var otherLanguages: [Choice] { choices(inThisLanguage: false) }

    private func choices(inThisLanguage wanted: Bool) -> [Choice] {
        let mine = Locale.current.language.languageCode?.identifier ?? "en"
        let standard = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: mine)
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let isMine = voice.language.hasPrefix(mine)
                guard isMine == wanted else { return false }
                // In this language, only the few worth choosing between. In the others,
                // anything that is not a novelty — there is no "default" to lean on, and
                // a person looking for their own language wants to find it.
                return wanted ? worthOffering(voice, standard: standard)
                              : !voice.voiceTraits.contains(.isNoveltyVoice)
            }
            .sorted { lhs, rhs in
                if rank(lhs) != rank(rhs) { return rank(lhs) > rank(rhs) }
                return languageName(lhs.language) < languageName(rhs.language)
            }
        return voices.enumerated().map { index, voice in
            Choice(id: voice.identifier,
                   name: voice.name,
                   quality: quality(of: voice),
                   isBest: wanted && index == 0,
                   isPersonal: voice.voiceTraits.contains(.isPersonalVoice),
                   language: languageName(voice.language),
                   isThisLanguage: wanted)
        }
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// Whether a voice belongs in a list somebody is asked to choose from.
    ///
    /// A device carries about forty English voices and most of them are wrong for this:
    /// fifteen are novelty voices — Bad News, Bells, Boing, Bubbles — and the rest of the
    /// standard set are the old robotic ones nobody would want reading to their mother.
    /// A picker of forty, thirty-eight of them unusable, is not a choice; it is a chore
    /// that ends with whatever was at the top.
    ///
    /// So three kinds are offered and nothing else: a voice somebody recorded of
    /// themselves, any Enhanced or Premium voice they have gone and downloaded, and the
    /// system's own default for the language. Asked for by language rather than by name,
    /// so this stays right outside en-US.
    private func worthOffering(_ voice: AVSpeechSynthesisVoice,
                               standard: AVSpeechSynthesisVoice?) -> Bool {
        if voice.voiceTraits.contains(.isPersonalVoice) { return true }
        if voice.voiceTraits.contains(.isNoveltyVoice) { return false }
        if voice.quality == .premium || voice.quality == .enhanced { return true }
        return voice.identifier == standard?.identifier
    }

    private func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        // A voice somebody recorded of themselves beats anything Apple ships, whatever
        // the synthesiser thinks of its quality. If a grandmother has recorded herself,
        // that is the voice the question should be asked in.
        if voice.voiceTraits.contains(.isPersonalVoice) { return 4 }
        return switch voice.quality {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    private func quality(of voice: AVSpeechSynthesisVoice) -> String {
        if voice.voiceTraits.contains(.isPersonalVoice) { return "Personal" }
        return switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }

    /// The chosen voice, or the best one installed. Nil lets the system decide, which is
    /// still correct — it is the last fallback, not a failure.
    func voice(preferring identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        guard let best = available.first else { return nil }
        return AVSpeechSynthesisVoice(identifier: best.id)
    }

    /// Say something. Anything already being said is dropped: a question that arrives
    /// while the last one is still going is a new round, and two voices over each other
    /// is worse than silence.
    func say(_ text: String, voiceIdentifier: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SpokenAudio.prepareForSpeaking()
        if synthesiser.isSpeaking { synthesiser.stopSpeaking(at: .immediate) }
        onStartedSpeaking?()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice(preferring: voiceIdentifier)
        utterance.rate = rate
        // A beat before it starts, so it doesn't talk over the round appearing.
        utterance.preUtteranceDelay = 0.25
        isSpeaking = true
        synthesiser.speak(utterance)
    }

    func stop() {
        guard synthesiser.isSpeaking else { return }
        synthesiser.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Whoever is listening, told to stand down while this voice is talking and to start
    /// again when it stops. Otherwise the microphone hears the question being read and
    /// tries to answer it.
    var onStartedSpeaking: (() -> Void)?
    var onFinishedSpeaking: (() -> Void)?
}

/// The synthesiser's delegate, kept separate because `AVSpeechSynthesizerDelegate` needs
/// an `NSObject` and the narrator is an `@Observable` class.
private final class SpeechWatcher: NSObject, AVSpeechSynthesizerDelegate {

    var onFinish: (@MainActor () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
}
