//
//  DescribedPhotos.swift
//  Time Rolls
//
//  Reading a description of a personal photograph and deciding whether it is a memory.
//
//  This is the judgement the rule-based filters keep half-missing. A photograph of a floor
//  taken to show a scratch has no text on it, no face, a perfectly ordinary aesthetic
//  score, and nothing the classifier can name — so every signal the pipeline has says
//  "fine", and it appears in a round asking which photo is from Virginia. It got through
//  twice after being reported.
//
//  Apple's on-device model is good at exactly the thing needed here and bad at the thing
//  it is not being asked. Measured this morning: naming a landmark, two times in three;
//  describing plainly what is in front of it, reliably. "A close-up of a wooden floor with
//  a scratch" is a description it produces easily, and no model has to be clever to see
//  that it is not a memory.
//
//  So the model describes, and these rules read. They are here, apart from the code that
//  talks to the model, because a rule that decides which of somebody's photographs the
//  game will never show is a rule that should be readable and tested rather than buried in
//  a prompt.
//

import Foundation

nonisolated enum DescribedPhotos {

    /// What a description turned out to be about.
    enum Verdict: Equatable {
        /// Worth showing: a person, a place, an occasion, a thing somebody meant to keep.
        case aMemory
        /// A note to self, a document, a screen, a surface. Named so the caregiver screen
        /// can say *why* a photograph was set aside.
        case notAMemory(String)
        /// The model said nothing useful. Keeps the photograph, like every other silence
        /// in this pipeline.
        case unknown
    }

    /// Phrases that mean somebody photographed a thing to remember a fact, not a moment.
    ///
    /// Each is a whole phrase rather than a single word, because the single words are all
    /// innocent: "screen" is in "a child in front of a television", "paper" is in "a boy
    /// with a paper hat". What gives a note to self away is the *close-up of* it.
    private static let notMemories: [(phrase: String, because: String)] = [
        ("screenshot", "a screenshot"),
        ("a screen showing", "a photo of a screen"),
        ("a computer screen", "a photo of a screen"),
        ("a phone screen", "a photo of a screen"),
        ("a television screen", "a photo of a screen"),
        ("a receipt", "a receipt"),
        ("an invoice", "a document"),
        ("a document", "a document"),
        ("a form", "a document"),
        ("a business card", "a document"),
        ("a driver's license", "a document"),
        ("a driving licence", "a document"),
        ("a passport", "a document"),
        ("a page of text", "a page of text"),
        ("a printed page", "a page of text"),
        ("a handwritten note", "a note"),
        ("a sticky note", "a note"),
        ("a price tag", "a label"),
        ("a barcode", "a label"),
        ("a qr code", "a label"),
        ("a label on", "a label"),
        ("a parking", "a reminder"),
        // Surfaces only count when the description says the picture is *of* the surface.
        // "A carpet" on its own threw away a dog asleep in front of a fire, which is the
        // exact photograph this feature exists to protect.
        ("close-up of a floor", "a surface"),
        ("close up of a floor", "a surface"),
        ("close-up of a wooden floor", "a surface"),
        ("close up of a wooden floor", "a surface"),
        ("close-up of a carpet", "a surface"),
        ("close up of a carpet", "a surface"),
        ("close-up of a wall", "a surface"),
        ("close up of a wall", "a surface"),
        ("close-up of a ceiling", "a surface"),
        ("a plain wall", "a surface"),
        ("an empty wall", "a surface"),
        ("a scratch", "damage"),
        ("a dent", "damage"),
        ("a crack in", "damage"),
        ("a stain", "damage"),
        ("a water leak", "damage"),
        ("a serial number", "a reminder"),
        ("a medication", "a reminder"),
        ("a prescription", "a reminder"),
        ("a calendar", "a reminder"),
        ("a whiteboard", "a reminder"),
        ("a menu", "a reminder"),
    ]

    /// Read a description. Nil or empty is `unknown`, never a rejection.
    static func read(_ description: String?) -> Verdict {
        guard let description else { return .unknown }
        let text = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { return .unknown }

        // A photograph with a person in it is a memory, whatever else is in the frame.
        // Somebody holding a certificate, a child beside a whiteboard, a nurse with a
        // chart — these are exactly the photographs this must never take away, and they
        // are the ones most likely to trip a phrase below.
        for sign in ["a man", "a woman", "a person", "a child", "a boy", "a girl",
                     "a baby", "people", "a group of", "a couple", "a family",
                     "smiling", "posing", "holding",
                     // And anything alive. A dog asleep on a carpet is a memory; the
                     // carpet is not what the photograph is about.
                     "a dog", "a cat", "a bird", "a horse", "a puppy", "a kitten",
                     "an animal"] where text.contains(sign) {
            return .aMemory
        }

        for (phrase, because) in notMemories where text.contains(phrase) {
            return .notAMemory(because)
        }
        return .aMemory
    }

    /// Whether a verdict means the photograph is kept.
    static func keeps(_ verdict: Verdict) -> Bool {
        switch verdict {
        case .aMemory, .unknown: true
        case .notAMemory: false
        }
    }
}
