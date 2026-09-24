//
//  Encouragement.swift
//  Time Rolls
//
//  What the voice says when somebody answers.
//
//  There is no score in this game and no fail state, so the words that follow a wrong tap
//  matter more than usual: they are the only thing that happens. They have to be warm,
//  short, and never a verdict — "wrong", "incorrect", "no" and anything that marks the
//  player are not in here and should not be added.
//
//  They also have to vary. Hearing the same sentence in the same voice after every single
//  wrong answer is how a kind thing turns into a nagging one, and somebody playing eight
//  rounds will hear this a dozen times in an afternoon.
//

import Foundation

nonisolated enum Encouragement {

    /// After a wrong tap. Every one of these assumes another go is coming, because it is.
    /// Warm, and none of them telling somebody what they did.
    ///
    /// "You should try again! You can do it!" was the first line here, and read at the
    /// wrong moment it is a lot: two exclamation marks, an instruction, and a reassurance
    /// nobody asked for. "Not that one" is worse — it names the mistake. What is left says
    /// only that there is another go, which is the single true and useful thing.
    static let tryAgain = [
        "Not quite — try again!",
        "You'll get it, try again.",
        "Nearly! Have another go.",
        "Close one. Try again.",
        "Not that one — you'll get it.",
        "Have another go, take your time.",
        "Almost! Try another one.",
    ]

    /// After the right answer.
    static let praise = [
        "Great job!",
        "Well done!",
        "That's the one!",
        "Lovely — well done!",
        "You got it!",
        "That's it exactly!",
        "Nicely done!",
    ]

    /// A line from the list, never the one said last.
    ///
    /// Not random: random repeats, and a repeat is exactly what this exists to avoid.
    /// Given the line said last, this returns something else.
    static func next(from lines: [String], after last: String?) -> String {
        guard !lines.isEmpty else { return "" }
        guard let last, let index = lines.firstIndex(of: last) else {
            return lines.randomElement() ?? lines[0]
        }
        let others = lines.enumerated().filter { $0.offset != index }.map(\.element)
        return others.randomElement() ?? lines[0]
    }
}
