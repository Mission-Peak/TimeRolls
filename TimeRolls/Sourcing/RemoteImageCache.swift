//
//  RemoteImageCache.swift
//  Time Rolls
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

import CryptoKit
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
            "User-Agent": "TimeRolls/1.0 (photo reminiscence prototype; hanna@attimis.co)"
        ]
        session = URLSession(configuration: configuration)

        discardSlotNamedFiles()
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
        // Read through OneBucket where it is configured, and from the original source
        // until it is. The app never holds a credential either way (spec §10).
        guard !unavailable.contains(item.id),
              let request = OneBucket.source(key: item.remoteKey, original: item.remoteURL)
        else { return nil }

        if let existing = inFlight[item.id] { return await existing.value }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            defer { inFlight[item.id] = nil }
            do {
                let (data, response) = try await session.data(for: request)
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

    /// Named after the photograph, not after its slot in the pack.
    ///
    /// This used to be "\(packID)-\(itemID).jpg", and item ids are handed out by position
    /// when a pack is built. Rebuilding a pack renumbers everything after the first entry
    /// that moved, so every device holding the old cache began serving the Golden Gate
    /// Bridge under Angkor Wat's caption — the pictures were right and the captions were
    /// right, and they had come apart. A name derived from the URL cannot come apart:
    /// a photograph that changed is simply a cache miss.
    private func localFile(for item: PackItem) -> URL? {
        // Named after the object's key where there is one, so moving the packs into
        // OneBucket does not invalidate every cache on every device — and, more
        // importantly, so the name still cannot come apart from the picture.
        guard let name = item.remoteKey ?? item.remoteURL?.absoluteString else { return nil }
        let digest = SHA256.hash(data: Data(name.utf8))
        return directory.appendingPathComponent(
            digest.map { String(format: "%02x", $0) }.joined() + ".jpg")
    }

    /// Drop anything named the old way. Those files are unreachable now, but they are
    /// also somebody's storage, and a cache that can never be read again is just litter.
    private func discardSlotNamedFiles() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            let stem = (name as NSString).deletingPathExtension
            guard stem.count != 64 || !stem.allSatisfy(\.isHexDigit) else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    var cachedCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    var bytesOnDisk: Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// How much of somebody's device the packs may occupy.
    ///
    /// The packs are read to the device, not given to it: a photograph is here because it
    /// is in play today, and once it rotates out it has no claim on the storage. Without
    /// a ceiling the cache grows towards the whole corpus — a third of a gigabyte of
    /// pictures nobody asked to keep, on an iPad that may not have it to spare.
    ///
    /// Generous enough that a day's rotation never evicts itself mid-session.
    static let budget = 120 * 1024 * 1024

    /// Drop the least recently used photographs until the cache is inside its budget.
    ///
    /// By last use rather than by age, so the pictures in play today survive and the ones
    /// that rotated out a week ago go first. Nothing here is precious: an evicted
    /// photograph is one fetch away from being back.
    func pruneToBudget() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return }

        let described = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0,
                    values.contentAccessDate ?? .distantPast)
        }
        var total = described.reduce(0) { $0 + $1.1 }
        guard total > Self.budget else { return }

        for (url, size, _) in described.sorted(by: { $0.2 < $1.2 }) {
            guard total > Self.budget else { break }
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }

    func empty() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        unavailable = []
    }
}
