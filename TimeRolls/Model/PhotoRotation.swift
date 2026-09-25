//
//  PhotoRotation.swift
//  Time Rolls
//
//  The stable hashing the pack ordering is built on.
//
//  This file used to deal each pack out by the calendar — a slice a day, the same all day,
//  changing at midnight. That was replaced by `SeenPhotos`, which tracks what somebody has
//  actually been shown and brings nothing back until the whole pack has been through. The
//  calendar deal bounded what a day cost to fetch back when the cache held a fraction of
//  the library; the cache now holds all of it, and knowing what day it was was never the
//  point. A photograph shown on Tuesday could come back on Friday while hundreds had never
//  been shown at all.
//
//  What is left is what that replacement still needs: a mixer and a hash that give the
//  same answer on every launch and every device.
//

import Foundation

enum PhotoRotation {

    /// The day a date falls on, as a single number that increases forever. Local
    /// midnight, so anything keyed to it changes overnight rather than at some UTC hour.
    static func dayIndex(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    /// SplitMix64's finaliser: a well-spread 64-bit value from any input, cheaply.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// A stable hash. `hashValue` is salted per launch, which would reshuffle the packs
    /// every time the app started.
    var hashValue64: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
