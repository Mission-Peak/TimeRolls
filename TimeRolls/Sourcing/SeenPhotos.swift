//
//  SeenPhotos.swift
//  Time Rolls
//
//  Which pack photographs have already been shown, so none comes round again until the
//  whole pack has been through.
//
//  This replaces a rotation that dealt each pack out by the calendar: a slice per day,
//  the same all day, changing at midnight. That was the right shape when the cache could
//  hold a fraction of the library and the point was to bound what a day cost to fetch.
//  The cache holds all of it now, and the calendar was never what anybody wanted — a
//  photograph seen on Tuesday could come back on Friday while hundreds had never been
//  shown at all, because the deal knew what day it was and not what you had seen.
//
//  Kept on the device and across launches, because "not seen before" is a fact about the
//  person, not about the session. It costs a few kilobytes: a pack of a thousand is a
//  thousand short ids.
//

import Foundation

@MainActor
final class SeenPhotos {

    static let shared = SeenPhotos()

    /// How many of a pack are in play at once.
    ///
    /// This is not how much variety there is. Variety is the seen record: everything a
    /// pack holds comes round once before anything comes round twice, whatever this says.
    /// This is only how many photographs a curator sorts through to build one round — and
    /// that work runs on the main thread, so it is felt as the screen freezing.
    ///
    /// Measured on a Mac, building a Time round took 260 ms with 80 a pack in play and
    /// 739 ms with 200. An older iPad is several times slower than that, and the freeze
    /// lands while the player is looking at the round before. Eighty keeps it where it
    /// has been all along and costs nothing now that repeats are prevented elsewhere.
    static let inPlayEachPack = 80

    private var seen: [String: Set<String>] = [:]
    private let store = UserDefaults.standard
    private let key = "seenPackPhotos"

    private init() {
        if let raw = store.dictionary(forKey: key) as? [String: [String]] {
            seen = raw.mapValues(Set.init)
        }
    }

    /// The photographs of this pack to play with: the ones not yet shown.
    ///
    /// When fewer than a round's worth remain the pack has been through, and the record
    /// is cleared so it can start again — a fresh pass, in a fresh order. Nothing is
    /// deleted from the device when that happens: the pictures are already downloaded and
    /// fetching them a second time would cost the player data to see something they are
    /// about to be shown anyway.
    func inPlay<T>(from items: [T], packID: String, id: (T) -> String) -> [T] {
        let chosen = Self.choose(from: items, packID: packID,
                                 seen: seen[packID] ?? [], id: id)
        if chosen.startedAgain {
            seen[packID] = []
            save()
        }
        return chosen.inPlay
    }

    /// The choosing, with the record passed in rather than read from the device.
    ///
    /// Pure so the harness can play a whole pack through and watch what comes out —
    /// which is the only way to check the thing that matters here, that nothing repeats
    /// before everything has been shown.
    nonisolated static func choose<T>(from items: [T], packID: String,
                                      seen: Set<String>,
                                      id: (T) -> String) -> (inPlay: [T], startedAgain: Bool) {
        var unseen = items.filter { !seen.contains(id($0)) }
        var startedAgain = false
        // Too few left to build a round from: the pack has been through.
        if unseen.count < DifficultyKnob.photoCount * 2 {
            unseen = items
            startedAgain = true
        }
        guard unseen.count > inPlayEachPack else { return (unseen, startedAgain) }
        // Stable while the same photographs are unseen, so the set does not reshuffle
        // under the player between one round and the next.
        let seed = UInt64(truncatingIfNeeded: packID.hashValue64) &+ UInt64(unseen.count)
        let ordered = unseen
            .map { (item: $0,
                    rank: PhotoRotation.mix(seed &+ UInt64(truncatingIfNeeded: id($0).hashValue64))) }
            .sorted { $0.rank < $1.rank }
            .prefix(inPlayEachPack)
            .map(\.item)
        return (Array(ordered), startedAgain)
    }

    /// Note that these were shown. Ids are the pack item ids, not the level's photo ids.
    func markShown(packID: String, itemIDs: [String]) {
        guard !itemIDs.isEmpty else { return }
        seen[packID, default: []].formUnion(itemIDs)
        save()
    }

    /// How far through a pack somebody is, for the caregiver's diagnostics.
    func progress(packID: String, of total: Int) -> (seen: Int, total: Int) {
        (seen[packID]?.count ?? 0, total)
    }

    func forget() {
        seen = [:]
        save()
    }

    private func save() {
        store.set(seen.mapValues(Array.init), forKey: key)
    }
}
