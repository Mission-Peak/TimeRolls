//
//  AlbumNames.swift
//  Time Rolls
//
//  Which of somebody's album names can carry a question.
//
//  An album is the only thing in a personal library that a person has already curated.
//  "Hawaii 2019" or "Dad's 80th" is a human being asserting what a set of photographs is
//  — which is exactly what the packs have and what the rest of a camera roll lacks. A
//  question built on it needs no model and cannot be wrong about the photographs, only
//  about whether the name is worth saying aloud.
//
//  So the only judgement here is that: is this a name a person chose, or one the phone
//  chose? "Recents" and "IMG_2021" are not occasions. Everything is rejected by rule,
//  never by guess, because a question that reads "Which photo is from Untitled Album?"
//  is worse than no question at all.
//

import Foundation

nonisolated enum AlbumNames {

    /// Names the phone, an app, or a default made up. None of these is an occasion.
    private static let notOccasions: Set<String> = [
        "recents", "recently added", "recently saved", "recently deleted", "favorites",
        "favourites", "camera roll", "all photos", "my photos", "photos", "library",
        "screenshots", "screen recordings", "selfies", "portrait", "panoramas", "videos",
        "live photos", "bursts", "slo-mo", "time-lapse", "cinematic", "animated",
        "hidden", "imports", "untitled", "untitled album", "new album", "album",
        "shared", "shared album", "whatsapp", "instagram", "telegram", "messenger",
        "downloads", "saved", "documents", "misc", "stuff", "random", "temp", "test",
    ]

    /// Fragments that give away a machine-made name wherever they appear.
    private static let machineFragments = ["img_", "dsc_", "dcim", "screenshot", "untitled"]

    /// The fewest photographs an album needs before its name means anything.
    ///
    /// Three, matching the rule Places already uses for a place: one photograph somewhere
    /// is an accident, three is a visit. An album of one is usually somebody starting to
    /// organise and stopping.
    static let fewestPhotographs = 3

    /// Whether a round may ask "Which photo is from …?" about this album.
    static func canCarryAQuestion(_ name: String, photographs: Int) -> Bool {
        guard photographs >= fewestPhotographs else { return false }
        let tidied = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = tidied.lowercased()

        guard tidied.count >= 3, tidied.count <= 40 else { return false }
        guard !notOccasions.contains(lowered) else { return false }
        guard !machineFragments.contains(where: { lowered.contains($0) }) else { return false }
        // A name has to say something. "2019" alone is a year, not an occasion, and
        // "..." is somebody's placeholder.
        guard tidied.contains(where: \.isLetter) else { return false }
        // At least one word of real length, so "a", "xx" and "ok" don't qualify.
        let words = lowered.split(whereSeparator: { !$0.isLetter })
        guard words.contains(where: { $0.count >= 3 }) else { return false }
        return true
    }

    /// Whether two album names are far enough apart to appear in the same round.
    ///
    /// "Italy" and "Italy 2019" are the same holiday to the person who named them, and a
    /// round asking which photograph is from one of them has two defensible answers.
    static func areDistinct(_ one: String, _ other: String) -> Bool {
        let first = one.lowercased().trimmingCharacters(in: .whitespaces)
        let second = other.lowercased().trimmingCharacters(in: .whitespaces)
        if first == second { return false }
        return !first.contains(second) && !second.contains(first)
    }
}
