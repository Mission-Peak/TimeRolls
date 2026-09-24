//
//  SpokenNumbers.swift
//  Time Rolls
//
//  Turning what somebody said into which photograph they meant.
//
//  Kept apart from VoiceAnswers.swift, which needs the Speech framework and a microphone
//  and so can only run on a device with somebody talking at it. This is the part that can
//  be wrong in ways nobody would notice until an eighty-year-old said "four" and the game
//  chose the first photograph, so it is the part the harness reads.
//

import Foundation

nonisolated enum SpokenNumbers {

    /// The number somebody said, if they said one.
    ///
    /// Two rules, both learned from the fixtures below rather than guessed at.
    ///
    /// **The last number wins, not the first.** "No, not one — three" is how people
    /// correct themselves out loud, and the correction is the answer.
    ///
    /// **An ordinal beats a plain number.** "The third one" ends with the word *one*,
    /// which is not a number there at all but a pronoun standing in for "photograph" —
    /// read plainly it picks the first photograph when somebody clearly asked for the
    /// third. So if anything ordinal was said, that is what they meant.
    /// Whether somebody asked for the next round out loud.
    ///
    /// Several words, because "next" is only the one somebody would write down. "Move on",
    /// "go on" and "carry on" are what people actually say, and a player who says one of
    /// them and gets nothing concludes the feature does not work rather than that they
    /// used the wrong word.
    static func asksForTheNextRound(_ text: String) -> Bool {
        let said = text.lowercased()
        let asks = ["next", "move on", "go on", "carry on", "keep going", "another one",
                    "next one", "next photo", "next photos", "continue"]
        return asks.contains { said.contains($0) }
    }

    static func number(in text: String, upTo count: Int) -> Int? {
        let cardinals = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                         // What the recogniser actually returns for these, spoken quickly
                         // by somebody who is not enunciating for a machine.
                         "won": 1, "to": 2, "too": 2, "tree": 3, "for": 4, "fore": 4]
        let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5]

        var lastCardinal: Int?
        var lastOrdinal: Int?
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let piece = String(token)
            if let digit = Int(piece), (1...count).contains(digit) {
                lastCardinal = digit
            } else if let ordinal = ordinals[piece], ordinal <= count {
                lastOrdinal = ordinal
            } else if let cardinal = cardinals[piece], cardinal <= count {
                lastCardinal = cardinal
            }
        }
        return lastOrdinal ?? lastCardinal
    }
}
