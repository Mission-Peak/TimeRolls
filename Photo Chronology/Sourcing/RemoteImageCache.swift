//
//  RemoteImageCache.swift
//  Photo Chronology
//
//  Pack photographs that are not carried in the app: fetched from where they already
//  live — Wikimedia Commons, Smithsonian Open Access — and kept on the device from then
//  on. A photograph is fetched once, ever.
//
//  This is what lets the catalogue be large. 350 photographs cost 171 KB as metadata;
//  the same photographs bundled would be about 80 MB.
//
//  Wi-Fi only, deliberately. Commons allows this kind of linking but asks that reusers
//  cache rather than re-fetch, and nobody's mobile data should go on a photo game.
//

import Foundation
import UIKit
import Observation

@Observable
@MainActor
final class RemoteImageCache {

    static let shared = RemoteImageCache()

    private let directory: URL
    private let session: URLSession
    /// Photographs that could not be fetched — a renamed or deleted source. Remembered
    /// for the session so curation can route around them instead of retrying forever.
    private(set) var unavailable: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("PackPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            // Commons asks that tools identify themselves.
            "User-Agent": "iRecollect/1.0 (photo reminiscence prototype; hanna@attimis.co)"
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Reading

    func cachedImage(for item: PackItem) -> UIImage? {
        guard let file = localFile(for: item),
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return UIImage(contentsOfFile: file.path)
    }

    func isAvailableOffline(_ item: PackItem) -> Bool {
        cachedImage(for: item) != nil
    }

    /// Fetch if we don't already have it. Returns nil when the photograph can't be had,
    /// which the caller should treat as "use a different photograph".
    func image(for item: PackItem) async -> UIImage? {
        if let cached = cachedImage(for: item) { return cached }
        guard let remote = item.remoteURL, !unavailable.contains(item.id) else { return nil }

        if let existing = inFlight[item.id] { return await existing.value }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            defer { inFlight[item.id] = nil }
            do {
                let (data, response) = try await session.data(from: remote)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    unavailable.insert(item.id)
                    return nil
                }
                guard let image = UIImage(data: data) else {
                    unavailable.insert(item.id)
                    return nil
                }
                if let file = localFile(for: item) {
                    try? data.write(to: file, options: .atomic)
                }
                return image
            } catch {
                // Offline, or the source moved. Either way, not this photograph.
                unavailable.insert(item.id)
                return nil
            }
        }
        inFlight[item.id] = task
        return await task.value
    }

    /// Warm a set of photographs, so a level is ready before anyone looks at it.
    @discardableResult
    func prefetch(_ items: [PackItem]) async -> Int {
        var fetched = 0
        await withTaskGroup(of: Bool.self) { group in
            for item in items where !isAvailableOffline(item) {
                group.addTask { @MainActor in
                    await self.image(for: item) != nil
                }
            }
            for await ok in group where ok { fetched += 1 }
        }
        return fetched
    }

    // MARK: - Housekeeping

    private func localFile(for item: PackItem) -> URL? {
        guard item.remoteURL != nil else { return nil }
        return directory.appendingPathComponent("\(item.packID)-\(item.id).jpg")
    }

    var cachedCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    var bytesOnDisk: Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func empty() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        unavailable = []
    }
}
