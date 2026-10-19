//
//  AppAnalytics.swift
//  Time Rolls
//
//  Anonymous usage statistics, sent to Firebase Analytics (project "MP Backend").
//
//  The one place an event is named and given its fields, so what leaves the device can be
//  read in a single file. Every field is a category, a kind of question, a count or a
//  yes/no. Never a photo, a photo's identifier, date or place, an album name, a subject
//  the classifier found, or anything that says which person or place somebody recognised —
//  the same line Engagement.swift draws for the on-device log.
//
//  Firebase records app opens, sessions and time spent by itself. FirebaseAnalyticsCore,
//  not FirebaseAnalytics: it never reads the advertising identifier, so there is nothing to
//  ask permission to track.
//
//  Off in debug builds, so a developer's simulator and phone do not count as players;
//  launch with TIMEROLLS_ANALYTICS=1 to send from one anyway. And off whenever the player
//  turns "Share usage statistics" off in Setup.
//

import Foundation
import FirebaseCore
import FirebaseAnalytics

enum AppAnalytics {

    /// Called once, at launch.
    static func start(sharing: Bool) {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        setSharing(sharing)
    }

    /// The player's choice in Setup, and the debug-build rule above.
    static func setSharing(_ sharing: Bool) {
        #if DEBUG
        let allowed = sharing && ProcessInfo.processInfo.environment["TIMEROLLS_ANALYTICS"] == "1"
        #else
        let allowed = sharing
        #endif
        Analytics.setAnalyticsCollectionEnabled(allowed)
    }

    // MARK: - Screens

    enum Screen: String {
        case home = "Home", play = "Play", themes = "Themes", progress = "Progress",
             setup = "Setup", privacy = "Privacy", welcome = "Welcome"
    }

    static func screen(_ screen: Screen) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screen.rawValue,
            AnalyticsParameterScreenClass: screen.rawValue,
        ])
    }

    // MARK: - Themes

    /// A category switched on or off in Themes. `category` is a photo set's id
    /// ("animals", "cars"), "own_photos" or "places_near_you".
    static func themeToggled(_ category: String, on: Bool) {
        Analytics.logEvent("theme_toggled", parameters: [
            "category": category,
            "on": on ? 1 : 0,
        ])
    }

    /// What is switched on as a session starts: how many categories, and which.
    static func sessionCategories(_ categories: [String], ownPhotos: Bool) {
        Analytics.logEvent("session_categories", parameters: [
            "count": categories.count,
            "categories": String(categories.sorted().joined(separator: ",").prefix(100)),
            "own_photos": ownPhotos ? 1 : 0,
        ])
    }

    // MARK: - Rounds

    /// A round answered. `category` as above; `question` is the kind of question asked
    /// ("named", "place", "kind"…), never its words.
    static func roundCompleted(category: String, game: String, question: String,
                               firstTry: Bool, attempts: Int, seconds: Int,
                               usedOwnPhoto: Bool) {
        Analytics.logEvent("round_completed", parameters: [
            "category": category,
            "game": game,
            "question": question,
            "first_try": firstTry ? 1 : 0,
            "attempts": attempts,
            "seconds": seconds,
            "own_photo": usedOwnPhoto ? 1 : 0,
        ])
    }

    /// "Different photos": a round passed over without an answer.
    static func roundSkipped(category: String, game: String) {
        Analytics.logEvent("round_skipped", parameters: ["category": category, "game": game])
    }

    // MARK: - Daily Roll

    static func dailyRollCompleted(goal: Int) {
        Analytics.logEvent("daily_roll_completed", parameters: ["goal": goal])
    }

    /// "Play more" on Home once the day's challenge is done.
    static func playMore() {
        Analytics.logEvent("play_more", parameters: nil)
    }
}
