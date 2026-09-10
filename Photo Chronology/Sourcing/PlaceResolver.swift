//
//  PlaceResolver.swift
//  Photo Chronology
//
//  Reverse-geocoding for the Places theme (spec §5.2).
//  Only coordinates leave the device — never the photo — and each ~11km location
//  cluster is looked up once, then cached on disk forever.
//

import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class PlaceResolver {

    private(set) var cache: [String: String] = [:]
    private(set) var isResolving = false
    /// Set when geocoding fails (offline, rate limited). Places degrades rather than errors.
    private(set) var lastErrorDescription: String?

    private let geocoder = CLGeocoder()
    private var failedKeys = Set<String>()
    private let storeURL: URL

    /// CLGeocoder throttles aggressively; keep requests slow and bounded per launch.
    private let minimumInterval: TimeInterval = 1.2
    private let maximumLookupsPerLaunch = 40
    private var lookupsThisLaunch = 0
    private var lastRequest: Date = .distantPast

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("place-cache.json")
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = decoded
        }
    }

    /// Cache-only lookup — safe to call from curation, never blocks or hits the network.
    func cachedName(for coordinate: Coordinate) -> String? {
        cache[coordinate.clusterKey]
    }

    func annotate(_ photos: [GamePhoto]) -> [GamePhoto] {
        photos.map { photo in
            var copy = photo
            if copy.placeName == nil, let coordinate = photo.coordinate {
                copy.placeName = cachedName(for: coordinate)
            }
            return copy
        }
    }

    /// Resolve the biggest un-named clusters first, so a few lookups unlock the most photos.
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

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(coordinate.clLocation)
            if let name = placemarks.first.flatMap(Self.displayName) {
                cache[key] = name
                lastErrorDescription = nil
            } else {
                failedKeys.insert(key)
            }
        } catch {
            failedKeys.insert(key)
            lastErrorDescription = error.localizedDescription
        }
    }

    private static func displayName(_ placemark: CLPlacemark) -> String? {
        let locality = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.inlandWater
            ?? placemark.ocean ?? placemark.name
        let region = placemark.country
        switch (locality, region) {
        case let (locality?, region?): return "\(locality), \(region)"
        case let (locality?, nil): return locality
        case let (nil, region?): return region
        default: return nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
