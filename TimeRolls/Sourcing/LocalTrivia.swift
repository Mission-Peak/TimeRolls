//
//  LocalTrivia.swift
//  Time Rolls
//
//  Notable places near the player, looked up when they ask for them.
//
//  Every other pack is compiled months before anybody plays it. This one cannot be: its
//  content is wherever the iPad happens to be. So it is built at runtime from Wikipedia's
//  geosearch, kept on the device, and refreshed only when the player has plainly moved.
//
//  What leaves the device, and nothing else: a rounded coordinate, to ask what is nearby.
//  It is rounded to about a kilometre before it is sent — enough to find the right town,
//  not enough to find a house — and the answer is cached so the question is asked once
//  rather than every session. No identifier goes with it. This is the same shape as the
//  reverse-geocoding call the Places theme already makes, and the privacy screen says so.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class LocalTrivia: NSObject, CLLocationManagerDelegate {

    enum State: Equatable {
        case idle
        case needsPermission
        case denied
        case looking
        case ready(placeCount: Int)
        case nothingNearby
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var pack: PhotoPack?

    private let manager = CLLocationManager()
    private var lookup: Task<Void, Never>?

    /// Ten kilometres, which is the most Wikipedia's geosearch allows — it rejects
    /// anything larger outright, and the first version asked for twenty-five, so every
    /// lookup failed before it began.
    private static let radiusMetres = 10_000
    /// Ask for far more than are needed, because they are ranked before they are used.
    private static let candidates = 200
    private static let wanted = 30

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Asking

    func begin() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .needsPermission
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            startLookup()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .notDetermined: state = .needsPermission
            case .denied, .restricted: state = .denied
            default: startLookup()
            }
        }
    }

    private func startLookup() {
        guard lookup == nil, pack == nil else { return }
        state = .looking
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let here = locations.last else { return }
        Task { @MainActor in
            lookup?.cancel()
            lookup = Task { await self.build(around: here.coordinate) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: any Error) {
        Task { @MainActor in
            state = .failed("Couldn't work out where you are.")
        }
    }

    // MARK: - Building the pack

    private func build(around coordinate: CLLocationCoordinate2D) async {
        defer { lookup = nil }
        do {
            // Rounded before it is sent. Three decimal places is about 100 m; two is
            // about a kilometre, which is the right grain for "what town is this".
            let latitude = (coordinate.latitude * 100).rounded() / 100
            let longitude = (coordinate.longitude * 100).rounded() / 100

            let nearby = try await geosearch(latitude: latitude, longitude: longitude)
            guard !nearby.isEmpty else {
                state = .nothingNearby
                return
            }
            let items = try await illustrate(nearby)
            guard items.count >= 4 else {
                state = .nothingNearby
                return
            }
            let assembled = PhotoPack(id: "local-trivia",
                                      title: "Near You",
                                      blurb: "Notable places close to you.",
                                      items: items,
                                      chronologyPrompt: nil,
                                      themes: [.places])
            PublicPackLibrary.register(runtime: assembled)
            pack = assembled
            state = .ready(placeCount: items.count)
        } catch {
            state = .failed("Couldn't reach Wikipedia to look up nearby places.")
        }
    }

    private struct Nearby {
        var title: String
        var latitude: Double
        var longitude: Double
    }

    private func geosearch(latitude: Double, longitude: Double) async throws -> [Nearby] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "list", value: "geosearch"),
            .init(name: "gscoord", value: "\(latitude)|\(longitude)"),
            .init(name: "gsradius", value: "\(Self.radiusMetres)"),
            .init(name: "gslimit", value: "\(Self.candidates)"),
        ]
        let payload = try await json(from: components.url!)
        let results = ((payload["query"] as? [String: Any])?["geosearch"] as? [[String: Any]]) ?? []
        return results.compactMap { row in
            guard let title = row["title"] as? String,
                  let lat = row["lat"] as? Double,
                  let lon = row["lon"] as? Double else { return nil }
            return Nearby(title: title, latitude: lat, longitude: lon)
        }
    }

    /// Lead image and opening sentence for each place, then the image's licence, in two
    /// batched calls rather than one per place.
    private func illustrate(_ places: [Nearby]) async throws -> [PackItem] {

        // Ranked by readership, not by distance. Geosearch answers "what is nearest",
        // and in central London the nearest fifty articles are statues, plaques, a
        // bookplate and a charity collecting box. How many people read an article each
        // month is a decent proxy for whether anybody would recognise the place, and it
        // puts Big Ben at the top where proximity buried it.
        var ranked: [(views: Int, title: String, file: String, fact: String?)] = []
        for chunk in stride(from: 0, to: places.count, by: 50).map({
            Array(places[$0 ..< min($0 + 50, places.count)])
        }) {
            var page = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
            page.queryItems = [
                .init(name: "action", value: "query"), .init(name: "format", value: "json"),
                .init(name: "titles", value: chunk.map(\.title).joined(separator: "|")),
                .init(name: "redirects", value: "1"),
                .init(name: "prop", value: "pageimages|extracts|pageviews"),
                .init(name: "piprop", value: "name"),
                .init(name: "exintro", value: "1"), .init(name: "explaintext", value: "1"),
                .init(name: "exsentences", value: "2"),
            ]
            let payload = try await json(from: page.url!)
            let pages = ((payload["query"] as? [String: Any])?["pages"] as? [String: Any]) ?? [:]
            for value in pages.values {
                guard let row = value as? [String: Any],
                      let title = row["title"] as? String,
                      let file = row["pageimage"] as? String,
                      !Self.isDistressing(title) else { continue }
                let views = ((row["pageviews"] as? [String: Any]) ?? [:])
                    .values.reduce(0) { $0 + (($1 as? Int) ?? 0) }
                ranked.append((views, title,
                               file.replacingOccurrences(of: "_", with: " "),
                               (row["extract"] as? String).map(Self.tidy)))
            }
        }
        ranked.sort { $0.views > $1.views }
        let best = Array(ranked.prefix(Self.wanted))

        var byFile: [String: (title: String, fact: String?)] = [:]
        for entry in best { byFile[entry.file] = (entry.title, entry.fact) }
        guard !byFile.isEmpty else { return [] }

        let licensed = try await commonsImages(Array(byFile.keys))
        let coordinates = Dictionary(places.map { ($0.title, $0) },
                                     uniquingKeysWith: { first, _ in first })

        return licensed.compactMap { file, image in
            guard let meta = byFile[file], let place = coordinates[meta.title] else { return nil }
            return PackItem(
                id: "local-\(meta.title.replacingOccurrences(of: " ", with: "-"))",
                packID: "local-trivia",
                date: .distantPast,
                placeName: meta.title,
                coordinate: Coordinate(latitude: place.latitude, longitude: place.longitude),
                imageResource: nil,
                imageDirectory: nil,
                remoteURL: image.url,
                motif: nil,
                credit: PackCredit(title: meta.title, creator: image.credit,
                                   source: "Wikimedia Commons", sourceURL: image.page,
                                   license: image.licence),
                declaredTags: [],
                subject: nil,
                fact: meta.fact)
        }
    }

    private struct RemoteImage {
        var url: URL
        var credit: String
        var page: String
        var licence: String
    }

    private func commonsImages(_ files: [String]) async throws -> [String: RemoteImage] {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "titles", value: files.map { "File:\($0)" }.joined(separator: "|")),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|extmetadata|size|mime"),
            .init(name: "iiurlwidth", value: "1200"),
        ]
        let payload = try await json(from: components.url!)
        let pages = ((payload["query"] as? [String: Any])?["pages"] as? [String: Any]) ?? [:]

        var result: [String: RemoteImage] = [:]
        for value in pages.values {
            guard let row = value as? [String: Any],
                  let name = (row["title"] as? String)?.replacingOccurrences(of: "File:", with: ""),
                  let info = (row["imageinfo"] as? [[String: Any]])?.first,
                  let width = info["width"] as? Int, width >= 500,
                  let mime = info["mime"] as? String, mime == "image/jpeg" || mime == "image/png",
                  let thumb = info["thumburl"] as? String, let url = URL(string: thumb)
            else { continue }
            let extra = info["extmetadata"] as? [String: Any] ?? [:]
            let licence = Self.field(extra, "LicenseShortName") ?? ""
            guard Self.licenceAllowed(licence) else { continue }
            result[name] = RemoteImage(url: url,
                                       credit: Self.field(extra, "Artist") ?? "Unknown",
                                       page: info["descriptionurl"] as? String ?? "",
                                       licence: licence)
        }
        return result
    }

    // MARK: - Small helpers

    private func json(from url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("TimeRolls/1.0 (photo reminiscence prototype; hanna@attimis.co)",
                         forHTTPHeaderField: "User-Agent")
        // Follows the same choice as the photo sets: a few kilobytes of place names is
        // not what anybody's data plan is worried about, but it would be odd for the game
        // to reach out over mobile data after being told not to.
        request.allowsCellularAccess = RemoteImageCache.shared.allowsCellular
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The same families the Landmarks pack accepts, and for the same reason: the photo
    /// of a place that still stands is modern, and on Commons that is mostly share-alike.
    private nonisolated static func licenceAllowed(_ licence: String) -> Bool {
        let family = licence.lowercased()
            .replacingOccurrences(of: #"\s+\d+(\.\d+)?.*$"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return ["cc0", "public domain", "no restrictions", "cc by", "cc by-sa"].contains(family)
    }

    private nonisolated static func field(_ extra: [String: Any], _ key: String) -> String? {
        guard let entry = extra[key] as? [String: Any],
              let value = entry["value"] as? String else { return nil }
        return value.replacingOccurrences(of: "<[^>]+>", with: "",
                                          options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same guard the packs use. Geosearch around a city centre turns up attacks,
    /// bombings and funerals, and this is not an app that shows somebody those.
    private nonisolated static func isDistressing(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return ["attack", "bombing", "massacre", "murder", "disaster", "funeral",
                "shooting", "riot", "siege", "fire of", "burning of", "crash",
                "prison", "gallows", "execution", "cemetery", "grave", "memorial",
                "war ", "battle"].contains { lowered.contains($0) }
    }

    private nonisolated static func tidy(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"\s*\([^()]*\)"#, with: "",
                                            options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
