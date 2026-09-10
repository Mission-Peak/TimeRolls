//
//  StatsStore.swift
//  Photo Chronology
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
        let key = Self.dayFormatter.string(from: Date())
        stats.sessionsByDay[key, default: 0] += 1
        stats.totalSessions += 1
        stats.lastPlayed = Date()
        save()
    }

    func recordLevelCompleted() {
        let key = Self.dayFormatter.string(from: Date())
        stats.levelsByDay[key, default: 0] += 1
        stats.totalLevels += 1
        stats.lastPlayed = Date()
        save()
    }

    // MARK: - Derived

    var sessionsThisWeek: Int {
        countingBack(days: 7, in: stats.sessionsByDay)
    }

    var levelsThisWeek: Int {
        countingBack(days: 7, in: stats.levelsByDay)
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
