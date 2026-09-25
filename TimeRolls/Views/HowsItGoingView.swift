//
//  HowsItGoingView.swift
//  Time Rolls
//
//  Tier 1 progress visibility (spec §7.2): aggregate only, on this device only.
//  Deliberately no per-person or per-place recognition trends.
//

import SwiftUI

struct HowsItGoingView: View {

    let engine: GameEngine

    var body: some View {
        MeadowScreen(title: "How's it going") {
            // The challenge first, because it is the only thing in the game that can be
            // finished, and the only number anybody is actually playing towards.
            StickerCard(fill: Meadow.cardMint) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionBanner(symbol: "calendar", title: "Today's challenge",
                                  tint: .hex(0x5FA86B), band: .white.opacity(0.75))
                    // One circle that says one thing: done, or how many are left. The
                    // stars, the grade, the days "like this" and a paragraph about the
                    // challenge all used to sit here, and the card read "23 of 8" once
                    // somebody kept playing past the goal — a number over a hundred
                    // percent that looked like a mistake.
                    DailyChallengeRing(done: engine.stats.cardsToday,
                                       goal: engine.settings.dailyCardGoal)
                }
            }

            StickerCard(fill: Meadow.cardCream) {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        StatCard(value: "\(engine.stats.sessionsThisWeek)",
                                 label: engine.stats.sessionsThisWeek == 1
                                    ? "session\nthis week" : "sessions\nthis week",
                                 symbol: "calendar", tint: .hex(0x8B8BE8))
                        StatCard(value: "\(engine.stats.dayStreak)",
                                 label: engine.stats.dayStreak == 1
                                    ? "day\nin a row" : "days\nin a row",
                                 symbol: "flame.fill", tint: .hex(0xF3A05A))
                        StatCard(value: "\(engine.stats.stats.totalLevels)",
                                 label: engine.stats.stats.totalLevels == 1
                                    ? "photo set\naltogether" : "photo sets\naltogether",
                                 symbol: "square.stack.fill", tint: .hex(0x7FB3E8))
                    }

                    // The best week there has been. Only shown once there is more than
                    // one week to compare, because "your best week is this week" says
                    // nothing — it is the only week there is.
                    if let best = engine.stats.bestWeek {
                        HStack(spacing: 10) {
                            StatCard(value: "\(best.sessions)",
                                     label: best.isThisWeek
                                        ? "best week\nso far—this one" : "sessions in\nyour best week",
                                     symbol: "trophy.fill", tint: .hex(0xE8B04B))
                        }
                    }
                }
            }

            StickerCard(fill: Meadow.cardCream) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionBanner(symbol: "star.fill", title: "Stars",
                                  tint: .hex(0xF3C765), band: .hex(0xFBEFC9))
                    HStack(spacing: 10) {
                        StatCard(value: "\(engine.stats.stats.totalStars)",
                                 label: "stars\naltogether",
                                 symbol: "star.fill", tint: .hex(0xF3C765))
                        StatCard(value: "\(engine.stats.starsThisWeek)",
                                 label: "stars\nthis week",
                                 symbol: "sparkles", tint: .hex(0x8B8BE8))
                        StatCard(value: "\(engine.stats.stats.bestRun)",
                                 // "in a row, best run" never said what was in a row, and
                                 // the singular read as "best run of one", which is an odd
                                 // thing to tell somebody about their own playing.
                                 label: "found first\ntime, best run",
                                 symbol: "flame.fill", tint: .hex(0xF3A05A))
                    }
                    if engine.stats.stats.currentRun > 0 {
                        FactRow(title: "Running now",
                                value: "\(engine.stats.stats.currentRun) in a row")
                    }
                    MeadowNote(text: "Two stars for a photo found first time, one for a "
                               + "photo that took another look — nobody finishes a round "
                               + "with nothing. A bonus star for every third in a row, "
                               + "growing as the run does. None of this is shown while "
                               + "playing: the game has no score in it, on purpose.")
                }
            }

            StickerCard(fill: Meadow.cardSky) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionBanner(symbol: "chart.bar.fill", title: "This week",
                                  tint: .hex(0x5AA9E6), band: .white.opacity(0.75))
                    WeekChart(days: engine.stats.levelsPerDayLastWeek)
                    HStack(spacing: 10) {
                        IconBadge(symbol: engine.stats.trend.symbolName, tint: .hex(0x5FBF7F))
                        Text(engine.stats.trend.label)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Meadow.title)
                        Spacer(minLength: 0)
                    }
                }
            }

            StickerCard(fill: Meadow.cardMint) {
                VStack(spacing: 10) {
                    if let last = engine.stats.stats.lastPlayed {
                        FactRow(title: "Last played",
                                value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    FactRow(title: "Photo sets this week",
                            value: "\(engine.stats.levelsThisWeek)")
                }
            }

            MeadowNote(text: "These are engagement numbers, not a memory assessment. "
                       + "Time Rolls does not track which people or places were recognised, "
                       + "and nothing here should be read as a sign of how someone is doing "
                       + "medically.")
        }
    }

    /// One number on a white tile — the three of them read as a row of badges rather
    /// than as a table.
    private struct StatCard: View {
        let value: String
        let label: String
        let symbol: String
        let tint: Color

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(Meadow.title)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Meadow.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private struct FactRow: View {
        let title: String
        let value: String

        var body: some View {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Meadow.title)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Meadow.body)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.white.opacity(0.7),
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Meadow.title)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(day.count > 0
                                  ? AnyShapeStyle(LinearGradient(
                                        colors: [Meadow.hillFar, Meadow.hillNear],
                                        startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.55)))
                            .frame(height: max(8, 76 * CGFloat(day.count) / CGFloat(peak)))
                        Text(day.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 122)
            .accessibilityLabel("Photo sets completed each day this week")
        }
    }
}


/// Today's challenge, as one circle.
///
/// It fills with green as rolls are played, and says "Complete!" once the challenge is
/// done. Until then the middle says how many rolls are still to go — "3 rolls left" —
/// which is the only thing worth knowing before it is done. It does not count past the goal: somebody who plays on after
/// finishing has finished, and "23 of 8" said otherwise.
///
/// It lives here and only here: the game itself never shows a score. Nothing happens when
/// the goal is met — no unlock, no nag when it isn't — because the moment a target starts
/// pushing back, it stops being a kindness and starts being a test.
struct DailyChallengeRing: View {

    let done: Int
    let goal: Int

    private var met: Bool { goal <= 0 || done >= goal }
    private var left: Int { max(goal - done, 0) }
    /// How much of the circle is filled. Stops at full, however far past the goal.
    private var progress: Double { goal <= 0 ? 1 : min(Double(done) / Double(goal), 1) }

    private static let green = Color.hex(0x5FA86B)
    private static let size: CGFloat = 176

    var body: some View {
        ZStack {
            // The track, and the green filling round it roll by roll from the top.
            Circle()
                .stroke(Meadow.muted.opacity(0.25), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Self.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            VStack(spacing: 2) {
                if met {
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .black))
                    Text("Complete!")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                } else {
                    Text("\(left)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Meadow.title)
                    Text(left == 1 ? "roll left" : "rolls left")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                }
            }
            .foregroundStyle(Self.green)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeOut(duration: 0.4), value: met)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(met ? "Today's challenge is complete"
                                : "\(left) \(left == 1 ? "roll" : "rolls") left in today's challenge")
    }
}
