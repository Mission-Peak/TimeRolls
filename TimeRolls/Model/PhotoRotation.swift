//
//  PhotoRotation.swift
//  Time Rolls
//
//  Each pack holds more photographs than it shows. Every day a different slice is in play,
//  so somebody who plays every morning is not shown the same photographs each time.
//
//  A day's slice is at most half the pack, so there is always another day's worth left to
//  deal and consecutive days never overlap — whether the pack holds two hundred or two
//  thousand. The slice was once a flat hundred and fifty, which worked for the large packs
//  and failed quietly for the small ones: Famous Faces holds 192, so 150 a day left only
//  42 unseen and most of a morning's photographs came back the next day.
//
//  Deterministic, not random: the slice is a function of the day number and the pack id,
//  so it is the same all day, changes at midnight, and can be checked rather than watched.
//  A shuffled-and-remembered list would drift between devices and would need storing; a
//  seeded one needs nothing and is the same on the iPad and the phone.
//

import Foundation

enum PhotoRotation {

    /// What share of a pack is in play on any given day.
    ///
    /// Only used for packs too small to deal out. Two thirds of a small pack keeps a theme
    /// playable; two thirds of a pack of four thousand is not a rotation, it is everything.
    static let share = 0.66

    /// How many photographs from one pack are in play on a day, once a pack is big enough
    /// to deal out rather than sample.
    ///
    /// A session is eight or so rounds of four or five photographs, so forty is plenty to
    /// play from and a hundred and fifty gives the curators room to be fussy — Places
    /// needs locations far apart, Things needs a subject with clean distractors. Much
    /// larger and the days stop being distinguishable; much smaller and a curator runs out
    /// of material and declines to build a round at all.
    /// Eighty, not a hundred and fifty.
    ///
    /// Five packs dealing a hundred and fifty each put three hundred megabytes of
    /// photographs in play on a single day, against a cache that held far less — so
    /// pictures still in the rotation were evicted and fetched again, felt as the game
    /// pausing between rounds. Eighty a pack is a hundred and fifty-seven megabytes,
    /// which a cache can actually hold.
    ///
    /// It costs variety, and the trade is worth naming: eighty is still twice what a long
    /// session uses, and a pack of a thousand takes twelve days to come round rather than
    /// six. Nobody notices a slower cycle. Everybody notices waiting for a photograph.
    static let inPlayEachDay = 80

    /// The fewest a day, however small the pack. Below about forty a curator runs out of
    /// material and starts declining to build rounds, which is worse than a repeat.
    static let fewestEachDay = 40

    /// How many of this pack are in play today.
    ///
    /// Never more than half of it, so there is always a second day's worth left to deal —
    /// which is what makes consecutive days disjoint. A flat hundred and fifty did not do
    /// that: Famous Faces holds 192, so a fixed slice left only 42 unseen and about four
    /// in five photographs came round again the next morning. Proportional costs the large
    /// packs nothing, because half of a thousand is past the cap anyway.
    static func inPlay(from count: Int) -> Int {
        max(fewestEachDay, min(inPlayEachDay, count / 2))
    }

    /// Small packs rotate proportionally less, or a lean pack would stop being playable —
    /// Places needs distinct locations and chronology needs a fifty-year spread, and both
    /// get harder as the pool shrinks.
    static let floor = 24

    /// The day a date falls on, as a single number that increases forever. Local
    /// midnight, so the photographs change overnight rather than at some UTC hour.
    static func dayIndex(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    /// Today's slice of a pack, in the pack's own order.
    ///
    /// Dealt, not sampled. The old version hashed every photograph against the day and
    /// kept the lowest two thirds, which means a photograph had a two-in-three chance of
    /// being in play on any given day — so most of them turned up again tomorrow, and the
    /// day after. That is a reshuffle rather than a rotation, and with a pack of four
    /// thousand it wastes almost all of it.
    ///
    /// Now the pack is shuffled once per cycle and dealt out a day at a time. Within a
    /// cycle nothing comes round again until everything else has been shown — a thousand
    /// photographs is six days of daily play with no repeat between any two of them. The
    /// shuffle is reseeded each cycle, so the order is different next time round rather
    /// than a loop somebody could learn.
    ///
    /// The guarantee holds because a day's slice is never more than half the pack, so a
    /// cycle is always at least two days and there is always something else to deal before
    /// anything repeats. Famous Faces, at 192, shows 96 a day over two days rather than
    /// 150 a day with four in five coming back.
    static func selection<T>(from items: [T], packID: String, day: Int) -> [T] {
        guard items.count > fewestEachDay * 2 else {
            return sample(from: items, packID: packID, day: day)
        }
        let perDay = inPlay(from: items.count)
        let daysInCycle = max(items.count / perDay, 1)
        let cycle = day / daysInCycle
        let position = day % daysInCycle

        // Shuffled by cycle, not by day — that is what makes the days disjoint.
        let seed = UInt64(bitPattern: Int64(cycle)) &* 0x9E37_79B9_7F4A_7C15
            &+ UInt64(truncatingIfNeeded: packID.hashValue64)
        let order = items.indices
            .map { (index: $0, rank: mix(seed &+ UInt64($0) &* 0xBF58_476D_1CE4_E5B9)) }
            .sorted { $0.rank < $1.rank }
            .map(\.index)
        let start = position * perDay
        guard start < order.count else { return [] }
        let slice = order[start..<min(start + perDay, order.count)].sorted()
        return slice.map { items[$0] }
    }

    /// The old behaviour, kept for packs too small to deal from: take a share of them,
    /// reshuffled daily. A pack of thirty cannot be dealt a hundred and fifty a day.
    private static func sample<T>(from items: [T], packID: String, day: Int) -> [T] {
        let wanted = max(min(items.count, floor), Int(Double(items.count) * share))
        guard items.count > wanted else { return items }
        let seed = UInt64(bitPattern: Int64(day)) &* 0x9E37_79B9_7F4A_7C15
            &+ UInt64(truncatingIfNeeded: packID.hashValue64)
        let ranked = items.indices
            .map { (index: $0, rank: mix(seed &+ UInt64($0) &* 0xBF58_476D_1CE4_E5B9)) }
            .sorted { $0.rank < $1.rank }
            .prefix(wanted)
            .map(\.index)
            .sorted()
        return ranked.map { items[$0] }
    }

    /// SplitMix64's finaliser: cheap, and it scatters neighbouring seeds properly, which
    /// matters because consecutive days and consecutive indices are exactly what goes in.
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// A stable hash. `hashValue` is salted per launch, which would reshuffle the packs
    /// every time the app started rather than every day.
    var hashValue64: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
