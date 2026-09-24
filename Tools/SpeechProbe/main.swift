//
//  Tools/SpeechProbe — can the recogniser we ask for actually hear a number?
//
//  Answering out loud stopped working and I could not tell whether the app was mishearing
//  the number, never hearing anything, or refusing to listen at all. Those need different
//  fixes and I had already guessed twice. This runs the exact path the app runs — an
//  on-device `SFSpeechRecognizer` fed from an audio buffer — on speech synthesised here,
//  so the answer is measured rather than assumed.
//

import AVFoundation
import Speech

@MainActor
func authorise() async -> Bool {
    let status = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    return status == .authorized
}

@MainActor
func hear(_ phrase: String, onDeviceOnly: Bool) async -> String? {
    guard let recogniser = SFSpeechRecognizer(locale: Locale.current) else {
        print("   no recogniser for \(Locale.current.identifier)"); return nil
    }
    print("   supportsOnDeviceRecognition: \(recogniser.supportsOnDeviceRecognition), "
        + "isAvailable: \(recogniser.isAvailable)")
    guard recogniser.isAvailable else { return nil }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = onDeviceOnly

    // Say the phrase into buffers rather than out loud, and hand those to the recogniser.
    let synthesiser = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: phrase)
    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        ?? AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        var finished = false
        synthesiser.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                if !finished { finished = true; continuation.resume() }
                return
            }
            request.append(pcm)
        }
    }
    request.endAudio()

    return await withCheckedContinuation { continuation in
        var answered = false
        _ = recogniser.recognitionTask(with: request) { result, error in
            guard !answered else { return }
            if let result, result.isFinal {
                answered = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            } else if let error {
                answered = true
                continuation.resume(returning: "error: \(error.localizedDescription)")
            }
        }
    }
}

@main
struct Probe {
    static func main() async {
        guard await authorise() else {
            print("not authorised to recognise speech on this Mac"); return
        }

        print("locale: \(Locale.current.identifier)\n")
        for phrase in ["three", "number two", "the third one", "four"] {
            print("saying \u{201C}\(phrase)\u{201D}")
            let heard = await hear(phrase, onDeviceOnly: true)
            let number = heard.flatMap { SpokenNumbersCopy.number(in: $0, upTo: 4) }
            print("   on-device heard: \(heard ?? "nothing") → \(number.map(String.init) ?? "no number")\n")
        }
    }
}

/// A copy of the app's parser, so this tool needs nothing from the app target.
enum SpokenNumbersCopy {
    static func number(in text: String, upTo count: Int) -> Int? {
        let cardinals = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                         "won": 1, "to": 2, "too": 2, "tree": 3, "for": 4, "fore": 4]
        let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5]
        var lastCardinal: Int?
        var lastOrdinal: Int?
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let piece = String(token)
            if let digit = Int(piece), (1...count).contains(digit) { lastCardinal = digit }
            else if let ordinal = ordinals[piece], ordinal <= count { lastOrdinal = ordinal }
            else if let cardinal = cardinals[piece], cardinal <= count { lastCardinal = cardinal }
        }
        return lastOrdinal ?? lastCardinal
    }
}
