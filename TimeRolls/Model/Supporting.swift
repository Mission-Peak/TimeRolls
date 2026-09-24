//
//  Supporting.swift
//  Time Rolls
//
//  When, and whether, to mention that the app can be supported.
//
//  Two things shape every rule here, and neither is about money.
//
//  The person holding the iPad may have memory difficulties. Asking them for money is not
//  something this app should ever do — they may not remember having been asked, may not
//  remember whether they already gave, and cannot reasonably consent to a purchase made
//  in the middle of a game. So the note is for the caregiver, it appears where a caregiver
//  is, and it never appears while somebody is playing.
//
//  And it is asked once, ever. Not once a week, not once a version. An app that asks
//  again has decided that the first "no" did not count.
//

import Foundation

nonisolated enum Supporting {

    /// How long somebody should have been playing before it is mentioned at all.
    static let afterDays = 7

    /// And how much playing. A week of the calendar with two sessions in it is not a week
    /// of the app being useful to anybody.
    static let afterSessions = 5

    /// Whether to show the one-time note.
    ///
    /// Deliberately conservative on every axis: long enough that the app has proved
    /// useful, and never at all for somebody who opened it twice and put it down.
    static func shouldAsk(firstPlayed: Date?,
                          sessions: Int,
                          alreadyAsked: Bool,
                          now: Date = Date()) -> Bool {
        guard !alreadyAsked, let firstPlayed else { return false }
        guard sessions >= afterSessions else { return false }
        let days = now.timeIntervalSince(firstPlayed) / 86_400
        return days >= Double(afterDays)
    }
}
