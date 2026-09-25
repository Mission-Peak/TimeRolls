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
                    DailyChallengeRing(
                        done: engine.stats.cardsToday,
                        goal: engine.settings.dailyCardGoal,
                        stars: engine.stats.starRating(goal: engine.settings.dailyCardGoal),
                        starsToday: engine.stats.starsToday,
                        goalDays: engine.stats.challengeDaysThisWeek(
                            goal: engine.settings.dailyCardGoal))
                    MeadowNote(text: "The challenge is \(engine.settings.dailyCardGoal) "
                               + "photo cards, and it can be finished across the whole day. "
                               + "Afterwards the game carries on for as long as anybody "
                               + "wants to play, and does not interrupt again until "
                               + "tomorrow. Change the number in Setup.")
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


/// Today's challenge: a ring that fills, and the day's stars as a number.
///
/// The stars used to be drawn as stars — three glyphs for the day's rating, and one glyph
/// per card finished. Both are numbers pretending not to be. A reader counting glyphs to
/// find out they got two out of three has been made to do arithmetic by a picture, and
/// the row of them broke outright once the challenge could be set by hand to twenty: a
/// twenty-star row wraps, and past about eight nobody counts them anyway. The star stays
/// as one small mark beside the figure, which is what a star is good at.
///
/// It lives here and only here: the game itself never shows a score, so this is where a
/// good afternoon is allowed to look like one. Nothing happens when the goal is met — no
/// unlock, no nag when it isn't — because the moment a target starts pushing back, it
/// stops being a kindness and starts being a test.
struct DailyChallengeRing: View {

    let done: Int
    let goal: Int
    /// The day graded out of three, once the challenge is finished.
    let stars: Int
    /// Every star earned today, which is a different count entirely — two for a photo
    /// found first time, one for one that took another look, plus the run bonus.
    var starsToday: Int = 0
    let goalDays: Int

    private var progress: Double {
        goal <= 0 ? 0 : min(Double(done) / Double(goal), 1)
    }
    private var met: Bool { goal > 0 && done >= goal }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                ring
                VStack(alignment: .leading, spacing: 4) {
                    Text(met ? "Finished for today" : "\(done) of \(goal) photo cards")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Meadow.title)
                    Text(met
                         ? "Done — and the game keeps going for as long as they like"
                         : "\(goal - done) more to finish the day")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if met {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Meadow.sparkle)
                            Text("\(stars) out of 3 for today")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Meadow.title)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stars) out of three for today")
                    }
                    if goalDays > 0 {
                        Text(goalDays == 1
                             ? "One day like this in the last week"
                             : "\(goalDays) days like this in the last week")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.hex(0x1F6B43))
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            starRow
        }
        .padding(14)
        .background(.white.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(met
                            ? "Today's challenge finished, \(done) photo cards, "
                              + "\(stars) out of three, \(starsToday) stars earned."
                            : "\(done) of \(goal) photo cards done today, "
                              + "\(starsToday) stars earned.")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.hex(0xF3C765).opacity(0.25), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [.hex(0xF3C765), .hex(0xF3A05A), .hex(0xF3C765)],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            VStack(spacing: 0) {
                Image(systemName: met ? "checkmark.circle.fill" : "photo.stack")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(met ? Color.hex(0x5FA86B) : Color.hex(0xE8A53C))
                Text("\(done)")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.title)
                    .monospacedDigit()
                Text("of \(goal)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Meadow.muted)
            }
        }
        .frame(width: 92, height: 92)
    }

    /// The day's stars, as a figure.
    ///
    /// This row used to draw one star glyph per card finished — despite the name, it was
    /// counting cards, which the ring beside it already shows twice. So it said nothing
    /// new and it said it in a form that had to be counted. It now shows the one number
    /// this screen was missing: how many stars the day has actually earned.
    private var starRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.hex(0xE8A53C))
            Text("\(starsToday)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Meadow.title)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: starsToday)
            Text(starsToday == 1 ? "star today" : "stars today")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Meadow.muted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(starsToday == 1 ? "One star today" : "\(starsToday) stars today")
    }
}
