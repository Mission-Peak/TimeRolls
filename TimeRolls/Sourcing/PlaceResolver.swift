//
//  PlaceResolver.swift
//  Time Rolls
//
//  Reverse-geocoding for the Places theme (spec §5.2).
//  Only coordinates leave the device — never the photo — and each ~11km location
//  cluster is looked up once, then cached on disk forever.
//

import Foundation
import CoreLocation
import MapKit
import Observation

@Observable
@MainActor
final class PlaceResolver {

    /// What a cluster of coordinates turned out to be. The country is kept beside the
    /// name because a question about a photograph taken abroad should ask about the
    /// country — "which photo is from Iceland" — and nobody can place the towns.
    struct Place: Codable, Hashable {
        var name: String
        var countryName: String?
        var countryCode: String?
    }

    private(set) var cache: [String: Place] = [:]
    private(set) var isResolving = false
    /// Set when geocoding fails (offline, rate limited). Places degrades rather than errors.
    private(set) var lastErrorDescription: String?

    private var failedKeys = Set<String>()
    private let storeURL: URL

    /// MapKit throttles aggressively; keep requests slow and bounded per launch.
    private let minimumInterval: TimeInterval = 1.2
    private let maximumLookupsPerLaunch = 250
    private var lookupsThisLaunch = 0
    private var lastRequest: Date = .distantPast

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("place-cache.json")
        if let data = try? Data(contentsOf: storeURL) {
            if let decoded = try? JSONDecoder().decode([String: Place].self, from: data) {
                // Drop anything whose name is just its own country. Those were written by
                // the old fallback, they are why a round asked which photograph was from
                // the United States, and a cache is exactly where a fixed bug goes on
                // living: the name was wrong once and would be read back for ever. Each
                // one costs a single reverse-geocoding call to put right.
                cache = decoded.filter { $0.value.name != $0.value.countryName }
            } else if let old = try? JSONDecoder().decode([String: String].self, from: data) {
                // The cache used to hold names alone. Keep them — they cost a network
                // round trip each — and let the country fill in as places are re-asked.
                cache = old.mapValues { Place(name: $0) }
            }
        }
    }

    /// Cache-only lookup — safe to call from curation, never blocks or hits the network.
    func cachedName(for coordinate: Coordinate) -> String? {
        cache[coordinate.clusterKey]?.name
    }

    func cachedPlace(for coordinate: Coordinate) -> Place? {
        cache[coordinate.clusterKey]
    }

    func annotate(_ photos: [GamePhoto]) -> [GamePhoto] {
        photos.map { photo in
            var copy = photo
            if copy.placeName == nil, let coordinate = photo.coordinate,
               let place = cachedPlace(for: coordinate) {
                copy.placeName = place.name
                copy.countryName = place.countryName
                copy.countryCode = place.countryCode
            }
            return copy
        }
    }

    /// Resolve the biggest un-named clusters first, so a few lookups unlock the most photos.
    /// True while there are still un-named clusters worth asking about.
    func hasUnresolvedClusters(in photos: [GamePhoto]) -> Bool {
        guard lookupsThisLaunch < maximumLookupsPerLaunch else { return false }
        return photos.contains { photo in
            guard let coordinate = photo.coordinate else { return false }
            let key = coordinate.clusterKey
            return cache[key] == nil && !failedKeys.contains(key)
        }
    }

    func resolveClusters(in photos: [GamePhoto], limit: Int = 8) async {
        var counts: [String: (Coordinate, Int)] = [:]
        for photo in photos {
            guard let coordinate = photo.coordinate else { continue }
            let key = coordinate.clusterKey
            guard cache[key] == nil, !failedKeys.contains(key) else { continue }
            counts[key, default: (coordinate, 0)].1 += 1
        }
        guard !counts.isEmpty else { return }

        let targets = counts.values
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)

        isResolving = true
        defer { isResolving = false }

        for coordinate in targets {
            guard lookupsThisLaunch < maximumLookupsPerLaunch else { break }
            await lookUp(coordinate)
        }
        persist()
    }

    private func lookUp(_ coordinate: Coordinate) async {
        let key = coordinate.clusterKey
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            try? await Task.sleep(nanoseconds: UInt64((minimumInterval - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()
        lookupsThisLaunch += 1

        guard let request = MKReverseGeocodingRequest(location: coordinate.clLocation) else {
            failedKeys.insert(key)
            return
        }
        do {
            let items = try await request.mapItems
            // `cityWithContext` is already the phrasing we want a question to use —
            // "Rome, Italy", "San Francisco, CA" — localised to the place itself.
            let address = items.first?.addressRepresentations
            // `.short` always omits the country, so an American photograph comes back as
            // "Charlotte, NC" and the question can ask about the state. The plain
            // `cityWithContext` property is `.automatic`, which omits the country only for
            // a device already set to it — and where that returned nothing at all, the old
            // code fell back to `regionName`, which *is* the country. That is how a photo
            // taken in North Carolina ended up named "United States", and how a round came
            // to ask which photograph was from the United States while holding three more
            // American ones.
            //
            // A country is never a place name here. Where nothing finer is known, the
            // photograph has no place, which keeps it out of Places rounds entirely — the
            // right answer, because "somewhere in America" cannot carry a question.
            let name = address?.cityWithContext(.short) ?? address?.cityName
            if let name, !name.isEmpty, name != address?.regionName {
                // `regionName` is the country — "Iceland", "United States" — and the
                // code beside it is what tells home from abroad without guessing.
                cache[key] = Place(name: name,
                                   countryName: address?.regionName,
                                   countryCode: address?.region?.identifier)
                lastErrorDescription = nil
            } else {
                failedKeys.insert(key)
            }
        } catch {
            failedKeys.insert(key)
            lastErrorDescription = error.localizedDescription
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
