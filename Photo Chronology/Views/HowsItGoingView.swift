//
//  HowsItGoingView.swift
//  Photo Chronology
//
//  Tier 1 progress visibility (spec §7.2): aggregate only, on this device only.
//  Deliberately no per-person or per-place recognition trends.
//

import SwiftUI

struct HowsItGoingView: View {

    let engine: GameEngine

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    StatCard(value: "\(engine.stats.sessionsThisWeek)",
                             label: engine.stats.sessionsThisWeek == 1
                                ? "session\nthis week" : "sessions\nthis week",
                             symbol: "calendar")
                    StatCard(value: "\(engine.stats.dayStreak)",
                             label: engine.stats.dayStreak == 1 ? "day\nin a row" : "days\nin a row",
                             symbol: "flame")
                    StatCard(value: "\(engine.stats.stats.totalLevels)",
                             label: engine.stats.stats.totalLevels == 1
                                ? "photo set\naltogether" : "photo sets\naltogether",
                             symbol: "square.stack")
                }
                .padding(.vertical, 6)
            }

            Section("This week") {
                WeekChart(days: engine.stats.levelsPerDayLastWeek)
                    .padding(.vertical, 8)
                Label(engine.stats.trend.label, systemImage: engine.stats.trend.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(Palette.accent)
            }

            Section {
                if let last = engine.stats.stats.lastPlayed {
                    LabeledContent("Last played",
                                   value: last.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Photo sets this week", value: "\(engine.stats.levelsThisWeek)")
                if engine.stats.togetherSessionsThisWeek > 0 {
                    LabeledContent("Played together",
                                   value: "\(engine.stats.togetherSessionsThisWeek) of "
                                        + "\(engine.stats.sessionsThisWeek) sessions")
                }
            }

            Section {
                Text("These are engagement numbers, not a memory assessment. iRecollect "
                     + "does not track which people or places were recognised, and nothing here "
                     + "should be read as a sign of how someone is doing medically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("How's it going")
    }

    private struct StatCard: View {
        let value: String
        let label: String
        let symbol: String

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(Palette.accent)
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private struct WeekChart: View {
        let days: [(label: String, count: Int)]

        private var peak: Int { max(days.map(\.count).max() ?? 0, 1) }

        var body: some View {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        Text(day.count > 0 ? "\(day.count)" : " ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(day.count > 0 ? Palette.accent : Palette.accent.opacity(0.15))
                            .frame(height: max(6, 72 * CGFloat(day.count) / CGFloat(peak)))
                        Text(day.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 118)
            .accessibilityLabel("Photo sets completed each day this week")
        }
    }
}
