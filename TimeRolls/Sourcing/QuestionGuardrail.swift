//
//  QuestionGuardrail.swift
//  Time Rolls
//
//  What the on-device model is allowed to have said when it rewords a question.
//
//  Kept apart from QuestionPhrasing.swift, which imports FoundationModels and so can only
//  run on a device. These rules are plain string work, and every one of them is here
//  because something got through: this is the file the harness reads.
//

import Foundation

/// What the model is allowed to have said.
///
/// Written as a rejection list rather than an acceptance list on purpose: the failure
/// this guards against is the model adding something — a name, a number, a hint, a
/// fact — and additions are what can be checked for.
enum QuestionGuardrail {

    /// Nil when the rewording may be used, otherwise the reason it may not.
    static func reject(_ candidate: String, rewordingOf original: String, in level: Level) -> String? {
        let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count >= 8, text.count <= 80 else { return "wrong length" }
        guard text.hasSuffix("?") else { return "not a question" }
        guard text.filter({ $0 == "?" }).count == 1 else { return "more than one question" }
        guard !text.contains("\n") else { return "more than one line" }
        guard !text.contains(where: \.isNumber) else { return "contains a number" }
        guard text.range(of: "[\"'!*_#]", options: .regularExpression) == nil else {
            return "contains punctuation it should not"
        }

        let lowered = text.lowercased()
        for word in bannedWords where lowered.contains(word) {
            return "says \(word.trimmingCharacters(in: .whitespaces))"
        }

        // No word may appear that wasn't in the original, unless it is one of the
        // handful of ordinary words a rewording legitimately needs.
        //
        // This check used to look only at capitalised words, because what it was written
        // to stop was an invented name, place or decade. That let "Which walk came
        // first?" become "Which came before the quiet walk?" — no capital letter in
        // sight, and yet "quiet" is a fact about a photograph that the model made up,
        // and one the player is now expected to recognise. An invented adjective is an
        // invented fact; only its spelling was different.
        let originalWords = Set(original.split(whereSeparator: { !$0.isLetter })
                                        .map { $0.lowercased() })
        let candidateWords = text.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }
        for word in candidateWords
        where !came(word, from: originalWords) && !allowedAdditions.contains(word) {
            return "added the word \(word)"
        }

        // A reworded question may not point at one photograph. "Before the walk" makes
        // the player find the walk before they can answer, and which one that is was
        // never something they could know — the round asks them to compare the set.
        for phrase in ["before the", "after the", "than the", "before this", "after this",
                       "before that", "after that", "compared to", "next to the"]
        where lowered.contains(phrase) {
            return "points at one photo (\(phrase))"
        }

        // If the written question named the thing being compared, the rewording has to
        // keep naming it — as itself, or as "one". A question that quietly swaps the noun
        // is a question about something slightly different.
        let originalNames = originalWords.contains { waysToSayPhoto.contains($0) }
        if originalNames {
            let candidateNames = candidateWords.contains { waysToSayPhoto.contains($0) }
            guard candidateNames else { return "stopped saying which photo" }
        }

        // And the question still has to be the question that was asked.
        guard keepsTheSubject(of: original, in: lowered, level: level) else {
            return "lost what was being asked"
        }
        return nil
    }

    /// The parts of the written question that carry its meaning have to survive.
    private static func keepsTheSubject(of original: String,
                                        in lowered: String,
                                        level: Level) -> Bool {
        switch level.theme {
        case .chronology:
            // Something that means "earliest".
            return ["first", "older", "oldest", "earlier", "earliest", "before", "born"]
                .contains { lowered.contains($0) }
        // The album's name is the question. A rewording that drops or bends it is asking
        // about a different album, so the same rule as Places and Things applies.
        case .places, .objects:
            // The place or the thing has to be named, and named as it was given: these
            // are the words the player is matching the photographs against.
            let anchors = original
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count > 3 && !commonWords.contains($0.lowercased()) }
            guard !anchors.isEmpty else { return true }
            return anchors.allSatisfy { lowered.contains($0.lowercased()) }
        }
    }

    /// Whether a word in the rewording is one of the original's, allowing for a plural.
    ///
    /// "Which walk came first?" may fairly become "Which of these walks happened first?".
    /// Nothing is being added there — it is the same noun, counted differently — and a
    /// rule that cannot tell the two apart throws away the rewordings worth having.
    private static func came(_ word: String, from original: Set<String>) -> Bool {
        if original.contains(word) { return true }
        if word.hasSuffix("es"), original.contains(String(word.dropLast(2))) { return true }
        if word.hasSuffix("s"), original.contains(String(word.dropLast())) { return true }
        return original.contains(word + "s") || original.contains(word + "es")
    }

    /// Ordinary words a rewording may bring in, because they carry no fact about any
    /// photograph. Deliberately short: anything not on it is treated as an addition.
    private static let allowedAdditions: Set<String> = [
        // articles, pronouns, connectives
        "a", "an", "the", "of", "in", "on", "at", "to", "and", "or", "is", "are", "was",
        "were", "do", "does", "did", "you", "your", "it", "its", "one", "ones", "these",
        "those", "this", "that", "them", "they", "here", "we", "us", "can", "could",
        // the question itself. "Image", "shot" and "time" are deliberately absent: with
        // them allowed the model wrote "Which image shows earlier time?", which passed
        // every check here and is not a sentence anybody says. Each word on its own was
        // innocent; the set of them was enough to build something stilted out of.
        "which", "what", "whose", "photo", "photos", "photograph", "photographs",
        "picture", "pictures", "show", "shows",
        "think", "guess", "tell", "see", "look", "looks",
        // time words, which is what a Chronology question is made of
        "first", "earlier", "earliest", "older", "oldest", "came", "come", "comes",
        "happened", "happen", "occurred", "took", "place", "taken",
        "ago", "back", "further", "furthest", "long", "longest", "old", "early",
    ]

    /// The words the app calls a photograph, and what may stand in for them.
    private static let waysToSayPhoto: Set<String> = [
        "photo", "photos", "photograph", "photographs", "picture", "pictures",
        "one", "ones",
    ]

    private static let bannedWords = [
        "left", "right", "top", "bottom", "corner", "above", "below", "middle",
        "tap", "click", "choose the", "answer", "correct", "wrong", "hint",
        "number", "option", "screen", "row",
    ]

    private static let commonWords: Set<String> = [
        "which", "photo", "from", "these", "that", "this", "with", "have", "them",
        "here", "what", "when", "where", "does", "your", "came", "first", "older",
        "there", "taken", "picture",
    ]
}
