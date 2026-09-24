//
//  StatsStore.swift
//  Time Rolls
//
//  Tier 1 progress visibility (spec §7.2): aggregate, on-device, nothing per-person
//  or per-place. Sessions, streaks, levels, rough trend — that is the whole surface.
//

import Foundation
import Observation

struct AggregateStats: Codable, Sendable {
    /// yyyy-MM-dd → count. Deliberately the coarsest useful granularity.
    var sessionsByDay: [String: Int] = [:]
    var levelsByDay: [String: Int] = [:]
    var totalLevels = 0
    var totalSessions = 0
    var lastPlayed: Date?
    /// The first day anybody played. Set once and never moved.
    var firstPlayed: Date?
    /// Stars earned, by day. Two for a round answered first time, one for a round that
    /// took more than one go — nobody leaves a round with nothing — plus a bonus for
    /// every three in a row, growing with the run.
    /// Questions somebody got wrong, as subject + answer, so they are never asked again.
    /// Play history rather than a caregiver's setting, which is why it lives here.
    var missedPairings: Set<String> = []
    var starsByDay: [String: Int] = [:]
    /// Rounds answered first time, by day. Only used to grade a finished challenge out of
    /// three, never shown as a number — "you got 6 of 8 first time" is a mark, and this
    /// game does not mark anybody.
    var firstTimeByDay: [String: Int] = [:]
    var totalStars = 0
    /// How many rounds have been answered first time, one after another.
    var currentRun = 0
    var bestRun = 0

    init() {}

    /// Tolerant, so adding a counter never discards the history already collected.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
        }
        sessionsByDay = value(.sessionsByDay, [:])
        levelsByDay = value(.levelsByDay, [:])
        totalLevels = value(.totalLevels, 0)
        totalSessions = value(.totalSessions, 0)
        lastPlayed = value(.lastPlayed, Date?.none)
        starsByDay = value(.starsByDay, [:])
        firstTimeByDay = value(.firstTimeByDay, [:])
        totalStars = value(.totalStars, 0)
        currentRun = value(.currentRun, 0)
        bestRun = value(.bestRun, 0)
    }
}

enum StatsTrend {
    case notEnoughYet
    case steady
    case moreThanBefore
    case lessThanBefore

    var label: String {
        switch self {
        case .notEnoughYet: "Just getting started"
        case .steady: "About the same as last week"
        case .moreThanBefore: "A bit more than last week"
        case .lessThanBefore: "A bit less than last week"
        }
    }

    var symbolName: String {
        switch self {
        case .notEnoughYet: "sparkles"
        case .steady: "equal.circle"
        case .moreThanBefore: "arrow.up.circle"
        case .lessThanBefore: "arrow.down.circle"
        }
    }
}

@Observable
@MainActor
final class StatsStore {

    private(set) var stats = AggregateStats()
    private static let key = "aggregate-stats-v1"

    /// The most sessions played in any one week, and whether that week is this one.
    ///
    /// Weeks rather than days on purpose. A daily best turns a quiet Tuesday into a number
    /// somebody has fallen short of, and this is a game for people who may be having a
    /// hard week for reasons that have nothing to do with it. A week is long enough that
    /// one difficult day does not show up as a loss.
    ///
    /// Nil until there is more than one week to compare, because "your best week is this
    /// week" is not a fact about anybody, it is just the only week there is.
    var bestWeek: (sessions: Int, isThisWeek: Bool)? {
        let calendar = Calendar.current
        var byWeek: [DateComponents: Int] = [:]
        for (day, count) in stats.sessionsByDay {
            guard let date = Self.dayFormatter.date(from: day) else { continue }
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            byWeek[week, default: 0] += count
        }
        guard byWeek.count > 1, let best = byWeek.max(by: { $0.value < $1.value })
        else { return nil }
        let thisWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return (best.value, best.key == thisWeek)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AggregateStats.self, from: data) {
            stats = decoded
        }
    }

    // MARK: - Recording

    func recordSessionStart() {
        if stats.firstPlayed == nil { stats.firstPlayed = Date() }
        let key = Self.dayFormatter.string(from: Date())
        stats.sessionsByDay[key, default: 0] += 1
        stats.totalSessions += 1
        stats.lastPlayed = Date()
        save()
    }

    /// Remember that this question was got wrong, so it is never asked again.
    func rememberMissed(subject: String, answer: String) {
        stats.missedPairings.insert(AlreadyMissed.key(subject: subject, answer: answer))
        save()
    }

    func recordLevelCompleted() {
        let key = Self.dayFormatter.string(from: Date())
        stats.levelsByDay[key, default: 0] += 1
        stats.totalLevels += 1
        stats.lastPlayed = Date()
        save()
    }

    /// The stars for a finished round.
    ///
    /// Two for first time, one otherwise: a wrong turn still earns something, because
    /// this is a record of somebody turning up rather than a mark out of ten. Then a
    /// bonus for every third round running — one star at three, two at six, three at
    /// nine — so a good afternoon shows up as a good afternoon.
    @discardableResult
    func recordStars(firstTime: Bool) -> (earned: Int, bonus: Int) {
        var earned = firstTime ? 2 : 1
        var bonus = 0
        if firstTime {
            stats.currentRun += 1
            stats.bestRun = max(stats.bestRun, stats.currentRun)
            if stats.currentRun % 3 == 0 {
                bonus = stats.currentRun / 3
                earned += bonus
            }
        } else {
            stats.currentRun = 0
        }
        let key = Self.dayFormatter.string(from: Date())
        stats.starsByDay[key, default: 0] += earned
        if firstTime { stats.firstTimeByDay[key, default: 0] += 1 }
        stats.totalStars += earned
        save()
        return (earned, bonus)
    }

    // MARK: - Derived

    var sessionsThisWeek: Int {
        countingBack(days: 7, in: stats.sessionsByDay)
    }

    var levelsThisWeek: Int {
        countingBack(days: 7, in: stats.levelsByDay)
    }

    var starsThisWeek: Int {
        countingBack(days: 7, in: stats.starsByDay)
    }

    var starsToday: Int {
        stats.starsByDay[Self.dayFormatter.string(from: Date())] ?? 0
    }

    /// Photo cards finished today. This is what the daily challenge counts.
    var cardsToday: Int {
        stats.levelsByDay[Self.dayFormatter.string(from: Date())] ?? 0
    }

    static var today: String { dayFormatter.string(from: Date()) }

    func hasMetChallenge(goal: Int) -> Bool {
        goal <= 0 || cardsToday >= goal
    }

    /// The day's challenge graded out of three.
    ///
    /// Out of three because that is what a person reads at a glance, and because a finer
    /// grade would invite comparing one day against another — which is the opposite of
    /// what this is for. Finishing at all is two; finishing with most rounds answered
    /// first time is three. Nobody who completes the challenge is ever shown one star.
    func starRating(goal: Int) -> Int {
        guard hasMetChallenge(goal: goal), goal > 0 else { return 0 }
        let clean = stats.firstTimeByDay[Self.today] ?? 0
        return Double(clean) >= Double(goal) * 0.75 ? 3 : 2
    }

    /// How many stars make a day. Ten is three or four rounds played well — an evening's
    /// worth, reachable on a day when someone isn't at their best, and not so low that
    /// it is met before they have settled in. It is a target, never a quota: nothing in
    /// the game changes when it is met or missed, and the player is never told either.
    static let dailyStarGoal = 10

    var metTodaysGoal: Bool { starsToday >= Self.dailyStarGoal }

    /// Days in the last week whose challenge was finished.
    func challengeDaysThisWeek(goal: Int) -> Int {
        guard goal > 0 else { return 0 }
        let calendar = Calendar.current
        return (0..<7).reduce(into: 0) { count, back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { return }
            if (stats.levelsByDay[Self.dayFormatter.string(from: day)] ?? 0) >= goal { count += 1 }
        }
    }

    /// Days in the last week where the goal was reached.
    var goalDaysThisWeek: Int {
        let calendar = Calendar.current
        return (0..<7).reduce(into: 0) { count, back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { return }
            if (stats.starsByDay[Self.dayFormatter.string(from: day)] ?? 0) >= Self.dailyStarGoal { count += 1 }
        }
    }

    /// Consecutive days played, counting today or yesterday as the anchor so a streak
    /// isn't "lost" before the day is over.
    var dayStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var cursor = Date()
        if played(on: cursor) == false, let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
            if played(on: cursor) == false { return 0 }
        }
        while played(on: cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var trend: StatsTrend {
        let recent = countingBack(days: 7, in: stats.levelsByDay)
        let previous = countingBack(days: 14, in: stats.levelsByDay) - recent
        guard recent + previous >= 6 else { return .notEnoughYet }
        if previous == 0 { return recent > 0 ? .moreThanBefore : .steady }
        let ratio = Double(recent) / Double(previous)
        if ratio > 1.25 { return .moreThanBefore }
        if ratio < 0.75 { return .lessThanBefore }
        return .steady
    }

    /// Last 7 days, oldest first — the sparkline on the "How's it going" screen.
    var levelsPerDayLastWeek: [(label: String, count: Int)] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = Self.dayFormatter.string(from: date)
            let symbol = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return (String(symbol.prefix(1)), stats.levelsByDay[key] ?? 0)
        }
    }

    private func played(on date: Date) -> Bool {
        (stats.sessionsByDay[Self.dayFormatter.string(from: date)] ?? 0) > 0
    }

    private func countingBack(days: Int, in table: [String: Int]) -> Int {
        let calendar = Calendar.current
        return (0..<days).reduce(0) { total, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return total }
            return total + (table[Self.dayFormatter.string(from: date)] ?? 0)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    func reset() {
        stats = AggregateStats()
        save()
    }
}
