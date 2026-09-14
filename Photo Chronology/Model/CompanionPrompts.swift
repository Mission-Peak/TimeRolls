//
//  CompanionPrompts.swift
//  Photo Chronology
//
//  Together mode: what the app offers a companion who is sitting alongside the player.
//
//  The evidence spine's strongest cross-cutting finding is that solo delivery of
//  reminiscence-type activities underperforms caregiver co-use (spec §7). This is the
//  cheapest way to act on that: no pairing, no network, no photo or result ever leaving
//  the device — just something useful to say to the person next to you.
//
//  Two rules shape everything here:
//   - A hint narrows, it never points. It works on a different axis from the question,
//     and it is only offered when it is actually true of exactly one photo in the set.
//   - A conversation prompt never implies the player was somewhere they weren't. Prompts
//     about a photo's own memories are reserved for the player's own photos; pack photos
//     only ever prompt about the player's life in general.
//

import Foundation

enum CompanionPrompts {

    // MARK: - Hints

    /// Gentlest first. The companion decides whether to offer any of them at all.
    static func hints(for level: Level) -> [String] {
        guard let answer = level.photos.first(where: { $0.id == level.correctPhotoID }) else {
            return [reassurance]
        }
        var result = [openingHint(for: level.theme)]
        if let narrowing = narrowingHint(for: level, answer: answer) {
            result.append(narrowing)
        }
        result.append(reassurance)
        return result
    }

    private static let reassurance =
        "There's no hurry, and nothing here can be got wrong for good."

    private static func openingHint(for theme: GameTheme) -> String {
        switch theme {
        case .chronology:
            "Look at the colours, and at what people are wearing — older photos tend to look different."
        case .places:
            "Picture what you'd actually see there: the sea, the hills, the streets."
        case .objects:
            "It might be small, or tucked away at the edge of the picture."
        }
    }

    /// A fact about the answer on a *different* axis from the question, used only when it
    /// is true of exactly one photo in the set — otherwise it would mislead.
    private static func narrowingHint(for level: Level, answer: GamePhoto) -> String? {
        let subject = level.theme == .chronology ? "The older one" : "The one you're looking for"

        // Prefer what's in the picture, then where it was taken, then when.
        if level.theme != .objects,
           let thing = uniqueObject(of: answer, in: level.photos) {
            return "\(subject) has \(thing) in it."
        }
        if level.theme != .places,
           let place = uniquePlace(of: answer, in: level.photos) {
            return "\(subject) was taken in \(place)."
        }
        if level.theme != .chronology, let decade = decade(of: answer) {
            return "\(subject) is from the \(decade)."
        }
        if level.theme == .chronology, let decade = decade(of: answer) {
            // On the time axis this still takes comparing — it names no photo.
            return "The oldest one here is from the \(decade)."
        }
        return nil
    }

    private static func uniqueObject(of photo: GamePhoto, in set: [GamePhoto]) -> String? {
        for tag in photo.objectTags.sorted() {
            guard let category = ObjectCatalog.category(id: tag) else { continue }
            let holders = set.filter { $0.possibleObjectTags.contains(tag) }
            if holders.count == 1 { return category.subject }
        }
        return nil
    }

    private static func uniquePlace(of photo: GamePhoto, in set: [GamePhoto]) -> String? {
        guard let place = photo.placeName else { return nil }
        let holders = set.filter { $0.placeName == place }
        return holders.count == 1 ? place : nil
    }

    // MARK: - Conversation

    /// The reminiscence payoff: something to ask once the photo set is open.
    /// Tailored to the answer, and careful about whose life it refers to.
    static func conversation(for level: Level) -> [String] {
        guard let answer = level.photos.first(where: { $0.id == level.correctPhotoID }) else {
            return genericPrompts
        }
        return answer.isPersonal ? personalPrompts(for: answer) : packPrompts(for: answer)
    }

    /// The player's own photo: their memory of this moment is fair to ask about.
    private static func personalPrompts(for photo: GamePhoto) -> [String] {
        var prompts: [String] = []
        if let label = photo.caregiverLabel {
            prompts.append("This one's from \(label). What do you remember about it?")
        }
        if let place = photo.placeName {
            prompts.append("This was taken in \(place). What was it like there?")
        }
        if let when = monthAndYear(of: photo) {
            prompts.append("This was \(when). What was going on around then?")
        }
        if let thing = ObjectCatalog.displayName(forFirstOf: photo.objectTags) {
            prompts.append("Tell me about the \(thing).")
        }
        prompts.append("Who else might have been there that day?")
        prompts.append("What happened just after this was taken?")
        return prompts
    }

    /// A pack photo is not their memory. Ask about their life, never about "this day".
    private static func packPrompts(for photo: GamePhoto) -> [String] {
        var prompts: [String] = []
        if let place = photo.placeName {
            prompts.append("Have you ever been to \(place)?")
        }
        if let decade = decade(of: photo) {
            prompts.append("What were you up to in the \(decade)?")
        }
        if let category = ObjectCatalog.category(id: photo.objectTags.sorted().first ?? "") {
            prompts.append("Did you ever have \(category.subject)?")
        }
        prompts.append(contentsOf: genericPrompts)
        return prompts
    }

    private static let genericPrompts = [
        "Does this remind you of anywhere you've been?",
        "What do you think was happening just outside this picture?",
        "Who does this make you think of?",
    ]

    // MARK: - Small helpers

    private static func decade(of photo: GamePhoto) -> String? {
        guard let date = photo.creationDate else { return nil }
        let year = Calendar.current.component(.year, from: date)
        return "\(year / 10 * 10)s"
    }

    private static func monthAndYear(of photo: GamePhoto) -> String? {
        guard let date = photo.creationDate else { return nil }
        return monthYearFormatter.string(from: date)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}
