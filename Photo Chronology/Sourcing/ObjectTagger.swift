//
//  ObjectTagger.swift
//  Photo Chronology
//
//  On-device Vision classification for the Objects theme (spec §6.3).
//
//  This is the one place in the app that looks at what is *in* a photo. It runs
//  entirely on this device through Apple's built-in classifier — no network call, no
//  generative model, nothing uploaded. What is kept is a handful of category keys per
//  photo ("dog", "cake"); the image itself is never stored, copied or transmitted, and
//  the labels never leave the device or enter a telemetry payload.
//

import Foundation
import Photos
import UIKit
import Vision
import Observation

@Observable
@MainActor
final class ObjectTagger {

    /// Written on the classification task, off the main actor.
    nonisolated struct Tags: Codable, Hashable {
        /// Categories we're confident about — these can be the answer.
        var confident: Set<String> = []
        /// Categories the classifier saw even a hint of. Used only to rule a photo out
        /// as a distractor, so a level never has two defensible answers.
        var possible: Set<String> = []
        var catalogVersion: Int = ObjectCatalog.version
    }

    private(set) var tags: [String: Tags] = [:]
    private(set) var isWorking = false
    /// Photos whose image could not be read at all (corrupt, or not on this device).
    private(set) var unreadableCount = 0
    /// Set when the on-device classifier can't be loaded — notably in the iOS Simulator,
    /// whose Core ML runtime cannot load the image classifier. Objects then plays from
    /// the photo packs alone rather than disappearing.
    private(set) var unavailableReason: String?

    private var worker: Task<Void, Never>?
    private let storeURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("object-tags.json")
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([String: Tags].self, from: data) {
            // Drop anything tagged against an older allow-list.
            tags = decoded.filter { $0.value.catalogVersion == ObjectCatalog.version }
        }
    }

    var taggedCount: Int { tags.count }

    /// Photos are classified once and remembered, so this is only slow the first time.
    func annotate(_ photos: [GamePhoto]) -> [GamePhoto] {
        photos.map { photo in
            var copy = photo
            if let found = tags[photo.id] {
                copy.objectTags = found.confident
                copy.possibleObjectTags = found.possible
            }
            return copy
        }
    }

    /// A photo can be classified if we can get pixels for it: the player's own photos,
    /// and bundled pack photographs. Procedural pack art keeps its hand-written subjects.
    private func subject(for photo: GamePhoto) -> Subject? {
        switch photo.origin {
        case let .personal(localIdentifier):
            return .asset(localIdentifier)
        case let .pack(packID, itemID):
            guard let item = PublicPackLibrary.item(packID: packID, itemID: itemID),
                  let url = PublicPackLibrary.imageURL(for: item) else {
                return nil
            }
            return .bundledImage(url.path)
        }
    }

    func pendingCount(in photos: [GamePhoto]) -> Int {
        photos.filter { tags[$0.id] == nil && subject(for: $0) != nil }.count
    }

    /// Works through the untagged photos a chunk at a time, calling back after each so
    /// the Objects theme becomes available while the rest is still being looked at.
    func startTagging(_ photos: [GamePhoto],
                      chunkSize: Int = 12,
                      onChunk: @escaping @MainActor () -> Void) {
        let pending: [(String, Subject)] = photos.compactMap { photo in
            guard tags[photo.id] == nil, let subject = subject(for: photo) else { return nil }
            return (photo.id, subject)
        }
        guard !pending.isEmpty else { return }

        worker?.cancel()
        unavailableReason = nil
        isWorking = true
        worker = Task { [weak self] in
            for chunk in stride(from: 0, to: pending.count, by: chunkSize) {
                if Task.isCancelled { break }
                let slice = Array(pending[chunk..<min(chunk + chunkSize, pending.count)])
                let results = await Self.classify(slice)

                guard let self, !Task.isCancelled else { break }
                var classifierGone = false
                for (id, outcome) in results {
                    switch outcome {
                    case let .tagged(result):
                        // An empty result is a real answer: nothing recognised here.
                        tags[id] = result
                    case .unreadable:
                        // Per-photo problem. Remember it so we don't retry forever.
                        tags[id] = Tags()
                        unreadableCount += 1
                    case let .classifierUnavailable(reason):
                        // Systemic. Cache nothing, so a later launch can try again.
                        unavailableReason = reason
                        classifierGone = true
                    }
                }
                persist()
                onChunk()
                if classifierGone { break }
            }
            self?.isWorking = false
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        isWorking = false
    }

    /// How each allow-listed category is doing on this library — the tool for the
    /// "which categories are reliable enough" decision in spec §12.
    func coverage(in photos: [GamePhoto]) -> [(category: ObjectCategory, matches: Int)] {
        var counts: [String: Int] = [:]
        for photo in photos {
            for tag in photo.objectTags {
                counts[tag, default: 0] += 1
            }
        }
        return ObjectCatalog.categories
            .map { ($0, counts[$0.id] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Classification

    /// One photo's outcome. Kept separate so a classifier that can't load is never
    /// mistaken for a photo with nothing in it.
    nonisolated enum Outcome {
        case tagged(Tags)
        /// No image could be read for this particular photo.
        case unreadable
        /// The classifier is not available at all on this device.
        case classifierUnavailable(String)
    }

    /// Where a photo's pixels come from.
    nonisolated enum Subject {
        case asset(String)
        case bundledImage(String)
    }

    private nonisolated static func classify(_ subjects: [(String, Subject)]) async -> [(String, Outcome)] {
        var output: [(String, Outcome)] = []
        let request = ClassifyImageRequest()

        for (id, subject) in subjects {
            if Task.isCancelled { return output }
            guard let image = thumbnail(for: subject) else {
                output.append((id, .unreadable))
                continue
            }
            do {
                let observations = try await request.perform(on: image)
                output.append((id, .tagged(tags(from: observations))))
            } catch {
                // The classifier itself is unavailable — one photo's worth of evidence is
                // enough to stop, because it will fail for every photo.
                output.append((id, .classifierUnavailable(error.localizedDescription)))
                return output
            }
        }
        return output
    }

    private nonisolated static func tags(from observations: [ClassificationObservation]) -> Tags {
        var result = Tags()
        for observation in observations {
            guard let categories = ObjectCatalog.byIdentifier[observation.identifier] else {
                continue
            }
            // Apple's own precision/recall filter first, then our per-category floor.
            let trustworthy = observation.hasMinimumRecall(0.4, forPrecision: 0.7)
            for category in categories {
                if observation.confidence >= ObjectCatalog.possibleConfidence {
                    result.possible.insert(category.id)
                }
                if trustworthy, observation.confidence >= category.confidence {
                    result.confident.insert(category.id)
                }
            }
        }
        // Anything confident is also possible.
        result.possible.formUnion(result.confident)
        return result
    }

    /// A small thumbnail is all the classifier needs, and it keeps this cheap.
    private nonisolated static func thumbnail(for subject: Subject) -> CGImage? {
        switch subject {
        case let .asset(localIdentifier):
            return assetThumbnail(localIdentifier)
        case let .bundledImage(path):
            // Pack photographs are already small and local.
            return UIImage(contentsOfFile: path)?.cgImage
        }
    }

    private nonisolated static func assetThumbnail(_ assetID: String) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = true
        // The user's own iCloud library, same as the display path. Nothing is sent out.
        options.isNetworkAccessAllowed = true

        var image: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 320, height: 320),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            image = result?.cgImage
        }
        return image
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func reset() {
        stop()
        tags = [:]
        unreadableCount = 0
        unavailableReason = nil
        try? FileManager.default.removeItem(at: storeURL)
    }
}
