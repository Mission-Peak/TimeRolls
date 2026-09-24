//
//  AlreadyMissed.swift
//  Time Rolls
//
//  A question somebody got wrong is not asked of them again.
//
//  Not the whole theme, and not the whole photograph — the *pairing* of the two. Somebody
//  who could not pick the Eiffel Tower out of four monuments is never asked to pick the
//  Eiffel Tower again, while the Eiffel Tower stays perfectly usable as one of the three
//  wrong answers in somebody else's round, and a different photograph of Paris can still
//  be asked about.
//
//  The reasoning is the same one behind everything else here: there is no score, no
//  failure and nothing to practise. A question that was hard once is not a gap to be
//  drilled — it is a question this person does not enjoy, and the game has hundreds of
//  others.
//

import Foundation

nonisolated enum AlreadyMissed {

    /// How a pairing is written down: what was asked, and which photograph was the answer.
    ///
    /// Both halves matter. The subject alone would retire "which one has a dog in it"
    /// across an entire library after one wrong tap; the photograph alone would retire a
    /// picture that is perfectly answerable under a different question.
    static func key(subject: String, answer: String) -> String {
        "\(subject)\u{001F}\(answer)"
    }

    /// Whether this round has been got wrong before.
    ///
    /// A round with no subject — Chronology asks about dates rather than a thing — is
    /// never retired. "Which photo is older" has no pairing to remember: the same four
    /// photographs in a different order is a different question.
    static func wasMissed(subject: String?, answer: String, among missed: Set<String>) -> Bool {
        guard let subject, !subject.isEmpty else { return false }
        return missed.contains(key(subject: subject, answer: answer))
    }
}
