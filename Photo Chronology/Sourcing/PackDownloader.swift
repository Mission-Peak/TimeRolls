//
//  PackDownloader.swift
//  Photo Chronology
//
//  Downloadable photo packs (spec §6.2, §8): a starter pack ships in the app and the
//  rest arrive from OneBucket on demand. This is what keeps the app small while the
//  library of photos can be as large as we like — bundling everything is what drove the
//  binary to 38 MB.
//
//  A downloaded pack lands in Application Support in exactly the shape a bundled pack
//  has, so nothing downstream knows or cares where a pack came from.
//

import Foundation
import Observation

/// Where packs are served from. Swap `baseURL` for the OneBucket bucket once it exists;
/// a file:// URL works too, which is how the download path is exercised in testing.
enum PackSource {
    static let defaultsKey = "pack-source-base-url"

    static var baseURL: URL? {
        // An environment override makes the download path testable against a local
        // server without touching the build.
        if let override = ProcessInfo.processInfo.environment["PACK_SOURCE_URL"],
           let url = URL(string: override) {
            return url
        }
        if let override = UserDefaults.standard.string(forKey: defaultsKey),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://s3.wasabisys.com/irecollect")
    }

    static var catalogURL: URL? {
        baseURL?.appendingPathComponent("packs/catalog.json")
    }
}

/// One pack offered by the catalog.
struct CatalogPack: Identifiable, Decodable, Hashable {
    var id: String
    var title: String
    var blurb: String
    var license: String
    var photoCount: Int
    var bytes: Int
    var earliestYear: Int?
    var latestYear: Int?
    var manifest: String

    var sizeDescription: String {
        String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }

    var yearsDescription: String? {
        guard let earliestYear, let latestYear else { return nil }
        return earliestYear == latestYear ? "\(earliestYear)" : "\(earliestYear)–\(latestYear)"
    }
}

private struct Catalog: Decodable {
    var formatVersion: Int
    var packs: [CatalogPack]
}

@Observable
@MainActor
final class PackDownloader {

    enum State: Equatable {
        case idle
        case loadingCatalog
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var available: [CatalogPack] = []
    /// pack id → fraction complete, while a download is in flight.
    private(set) var progress: [String: Double] = [:]
    private(set) var lastError: String?

    private var tasks: [String: Task<Void, Never>] = [:]

    // MARK: - Catalog

    func loadCatalog() async {
        guard let url = PackSource.catalogURL else {
            state = .failed("No pack source is configured.")
            return
        }
        state = .loadingCatalog
        do {
            let data = try await Self.fetchData(from: url)
            let catalog = try JSONDecoder().decode(Catalog.self, from: data)
            guard catalog.formatVersion == 1 else {
                state = .failed("This pack catalogue is newer than the app.")
                return
            }
            available = catalog.packs
            state = .ready
            lastError = nil
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    // MARK: - Downloading

    func isDownloading(_ pack: CatalogPack) -> Bool {
        tasks[pack.id] != nil
    }

    func download(_ pack: CatalogPack, onFinished: @escaping @MainActor () -> Void) {
        guard tasks[pack.id] == nil, let base = PackSource.baseURL else { return }
        progress[pack.id] = 0
        tasks[pack.id] = Task { [weak self] in
            defer {
                self?.tasks[pack.id] = nil
                self?.progress[pack.id] = nil
            }
            do {
                try await Self.fetch(pack, from: base) { [weak self] fraction in
                    self?.progress[pack.id] = fraction
                }
                guard !Task.isCancelled else { return }
                PackStore.shared.markInstalled(pack.id)
                onFinished()
            } catch {
                guard !Task.isCancelled else { return }
                self?.lastError = "Couldn't finish \(pack.title): \(error.localizedDescription)"
                PackStore.shared.discardPartial(pack.id)
            }
        }
    }

    func cancel(_ pack: CatalogPack) {
        tasks[pack.id]?.cancel()
        tasks[pack.id] = nil
        progress[pack.id] = nil
        PackStore.shared.discardPartial(pack.id)
    }

    /// A failed request should say so plainly. Without this an error page comes back as
    /// a body and surfaces as "the data isn't in the correct format", which sends you
    /// looking in entirely the wrong place.
    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "PhotoChronology", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey:
                    "The photo pack server answered \(http.statusCode) for \(url.lastPathComponent)."
            ])
        }
        return data
    }

    /// Manifest first, then its photographs, into a staging directory that is only
    /// promoted once every file has arrived — a half-downloaded pack is never playable.
    private static func fetch(_ pack: CatalogPack,
                              from base: URL,
                              onProgress: @escaping @MainActor (Double) -> Void) async throws {
        let staging = PackStore.shared.stagingDirectory(for: pack.id)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let manifestURL = base.appendingPathComponent(pack.manifest)
        let manifestData = try await fetchData(from: manifestURL)
        let manifestName = (pack.manifest as NSString).lastPathComponent
        try manifestData.write(to: staging.appendingPathComponent(manifestName))

        struct FileList: Decodable {
            struct Item: Decodable { var file: String }
            var items: [Item]
        }
        let files = try JSONDecoder().decode(FileList.self, from: manifestData).items.map(\.file)
        let remoteDirectory = manifestURL.deletingLastPathComponent()

        var completed = 0
        for file in files {
            try Task.checkCancellation()
            let data = try await fetchData(from: remoteDirectory.appendingPathComponent(file))
            try data.write(to: staging.appendingPathComponent(file))
            completed += 1
            let fraction = Double(completed) / Double(max(files.count, 1))
            await MainActor.run { onProgress(fraction) }
        }

        try PackStore.shared.promote(pack.id)
    }
}
