//
//  Chime.swift
//  Time Rolls
//
//  The sound half of "Sound and touch cues".
//
//  There was no sound. The switch fired a haptic and nothing else, and an iPad has no
//  Taptic Engine at all — so on the device this app is mostly played on, turning the
//  cues on did literally nothing.
//
//  The notes are generated rather than shipped as a clip. Three sine tones with a soft
//  decay is a smaller and cleaner chime than any recording, it needs no asset in the
//  bundle and no licence, and the pitch and length can be tuned here rather than in an
//  editor. Nothing about it is loud: this is a game played in a quiet room.
//

import AVFoundation

@MainActor
final class Chime {

    static let shared = Chime()

    enum Tone { case correct, tryAgain }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var tones: [Tone: AVAudioPCMBuffer] = [:]
    private var ready = false

    private init() {}

    func play(_ tone: Tone) {
        guard start(), let buffer = tones[tone] else { return }
        // `.interrupts` so a quick second tap replaces the note rather than queueing
        // behind it — two chimes overlapping sounds like a mistake.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Built on the first cue rather than at launch, so a session played in silence
    /// never starts an audio engine at all.
    private func start() -> Bool {
        if ready { return true }
        do {
            // The session belongs to SpokenAudio, which is the only thing allowed to set
            // a category. The chime used to set its own — `.playback`, once, on the first
            // note it ever played — and that first note happens on the first answer of the
            // first round, while the microphone is open waiting for somebody to say a
            // number. It would have closed the microphone for the rest of the session, a
            // few minutes after the voice fix that opened it.
            SpokenAudio.prepareForSpeaking()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.9
            try engine.start()
        } catch {
            // No audio route, or a session another app holds. The game is playable
            // without a chime, so this is not worth telling anybody about.
            return false
        }
        tones[.correct] = render(notes: [(523.25, 0), (659.25, 0.09), (783.99, 0.18)],
                                 seconds: 0.85, peak: 0.60)
        // Low, soft, and *rising* — A3 up to C4.
        //
        // It used to fall, G4 down to E4, and a falling interval is read as
        // disappointment by everybody everywhere. That is the wrong thing for this game to
        // say: a wrong tap here is somebody looking again, not somebody failing, and the
        // sound should be the one you would make yourself if you were sitting beside them.
        //
        // Rising without being mistaken for the right answer, which is a bright three-note
        // climb high above this one. Two notes, low in the register where sound reads as
        // warm, and quiet enough to be an invitation rather than a verdict.
        tones[.tryAgain] = render(notes: [(220.00, 0), (261.63, 0.12)],
                                  seconds: 0.55, peak: 0.30)
        ready = true
        return true
    }

    /// Sine tones, each fading out on its own, summed into one buffer.
    private func render(notes: [(frequency: Double, start: Double)],
                        seconds: Double,
                        peak: Float) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        for frame in 0 ..< Int(frames) {
            let time = Double(frame) / rate
            var value = 0.0
            for note in notes where time >= note.start {
                let age = time - note.start
                // A struck-note envelope: quick on, slow off. The 0.008s rise is there
                // to stop the click a square start makes.
                let attack = min(age / 0.008, 1)
                let decay = exp(-age * 4.5)
                value += sin(2 * .pi * note.frequency * age) * attack * decay
            }
            samples[frame] = Float(value / Double(notes.count)) * peak
        }
        return buffer
    }
}
