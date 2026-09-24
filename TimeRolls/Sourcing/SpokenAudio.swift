//
//  SpokenAudio.swift
//  Time Rolls
//
//  One owner for the audio session.
//
//  There are three things in this app that want the speaker or the microphone — the
//  chime, the voice that reads the question, and the listener waiting for somebody to say
//  a number — and for a while each of them configured the shared session itself. That
//  works until two are on at once, and then it fails in the least obvious way possible:
//  the listener opens the microphone, the narrator sets the category to `.playback` half a
//  second later to read the question, and the microphone is quietly closed. Nothing
//  crashes. Nothing is logged. The game simply stops hearing anybody.
//
//  So the category is set here and nowhere else, and it is only ever *raised* — once
//  somebody is listening, reading a question aloud does not take the microphone away.
//

import AVFoundation

@MainActor
enum SpokenAudio {

    private static var configuredForListening: Bool?

    /// Configure for listening and speaking. Called by the listener.
    static func prepareForListening() {
        configure(listening: true)
    }

    /// Configure for speaking, but never downgrade a session that is already listening.
    static func prepareForSpeaking() {
        guard configuredForListening != true else { return }
        configure(listening: false)
    }

    /// The microphone is closed for good — go back to a plain playback session.
    static func stopListening() {
        guard configuredForListening == true else { return }
        configure(listening: false)
    }

    private static func configure(listening: Bool) {
        guard configuredForListening != listening else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            if listening {
                // `.defaultToSpeaker` so the question is read out of the speaker rather
                // than the earpiece, which is where `.playAndRecord` sends it otherwise —
                // an iPad on a table, read to through the earpiece, sounds broken.
                try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                        options: [.duckOthers, .defaultToSpeaker,
                                                  .allowBluetooth])
            } else {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }
            try session.setActive(true)
            configuredForListening = listening
        } catch {
            // A session that will not configure is not a reason to stop the game.
        }
    }
}
