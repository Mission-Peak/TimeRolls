//
//  RoundAuditRules.swift
//  Time Rolls
//
//  The decisions the round audit makes that have nothing to do with a model.
//
//  Kept apart from RoundAudit.swift, which needs UIKit and FoundationModels and so can
//  only be exercised on a device with Apple Intelligence switched on. These two rules
//  are the ones that must hold everywhere — including on every device that will never
//  run the audit at all — so they live where the harness can reach them.
//

import Foundation

nonisolated enum RoundAuditRules {

    /// What the model said about a round it was shown.
    enum Outcome: Equatable {
        /// It picked the photograph curation had picked.
        case agreed
        /// It picked a different one. On Objects that means the question is wrong about
        /// what is in the photographs; on Places it means the answer isn't findable.
        case chose(String)
        /// More than one photograph would do, or none clearly would.
        case arguable
        /// No verdict: no model, no Apple Intelligence, no answer in time, an error.
        case unjudged(String)

        /// Whether the round survives.
        ///
        /// The asymmetry is the whole design. Disagreement is evidence against a round;
        /// silence is not evidence of anything, and a round dropped for silence would
        /// mean a device with a busy model quietly plays a worse game than one without.
        var keepsRound: Bool {
            switch self {
            case .agreed, .unjudged: true
            case .chose, .arguable: false
            }
        }
    }

    /// What the model called the photograph, tidied up.
    ///
    /// It does not always answer with the label it was given: `[photo 1]` and
    /// `#/$defs/ImageReference` both came back during measurement. The first is our
    /// answer wearing brackets; the second is the model quoting the schema at us. Only
    /// a label we actually handed it counts as an answer — anything else is a non-answer
    /// and keeps the round, because a round must never be thrown away over punctuation.
    static func labelSaid(_ raw: String, amongst labels: [String]) -> String? {
        let tidied = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'[]()."))
            .lowercased()
        return labels.first { $0.lowercased() == tidied }
    }

    /// Whether this round's question is the model's business at all.
    ///
    /// Only questions a photograph can answer by itself. Two kinds are ruled out, for
    /// the same reason in different clothes — the model cannot see what makes the answer
    /// true, so its disagreement is not evidence of anything:
    ///
    /// **Chronology, always.** "Which of these is older" is answered by the date in the
    /// file, which is certain. A model would be reading the grain and the haircuts.
    ///
    /// **Places, when the photographs are someone's own.** "Which photo is from Virginia"
    /// is answered by GPS. Nothing in a picture of a back garden says Virginia, so the
    /// model would disagree with almost every such round and quietly delete a whole theme
    /// from anyone playing with their own photographs. The player is not guessing from
    /// the pixels either — they are remembering their own garden, which the model can
    /// never do. Pack rounds are different: "which photo shows the Colosseum" is a
    /// question about a famous thing that is right there in the frame, and measurement
    /// says the model answers it about four times in five.
    static func judges(theme: GameTheme, usesPersonalPhotos: Bool) -> Bool {
        switch theme {
        case .chronology: false
        case .objects: true
        case .places: !usesPersonalPhotos
        // Occasions, never. The answer is which album somebody filed the photograph in,
        // which is not in the photograph — the model would be guessing at "Dad's 80th"
        // from a cake, and disagreeing with a fact.
        }
    }
}
