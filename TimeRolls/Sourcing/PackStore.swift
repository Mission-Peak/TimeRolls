//
//  PackStore.swift
//  Time Rolls
//
//  Where downloaded packs live on the device. A pack is a directory of a manifest plus
//  its photographs — the same shape as one bundled in the app — so `PublicPackLibrary`
//  reads both the same way.
//

import Foundation

@MainActor
final class PackStore {

    static let shared = PackStore()

    private let root: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        root = support.appendingPathComponent("Packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Locations

    func directory(for packID: String) -> URL {
        root.appendingPathComponent(packID, isDirectory: true)
    }

    func stagingDirectory(for packID: String) -> URL {
        root.appendingPathComponent("\(packID).downloading", isDirectory: true)
    }

    /// Directories holding a complete, installed pack.
    func installedDirectories() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return contents.filter {
            $0.hasDirectoryPath && !$0.lastPathComponent.hasSuffix(".downloading")
        }
    }

    func isInstalled(_ packID: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: packID).path)
    }

    // MARK: - Lifecycle

    /// Swap a finished download into place.
    func promote(_ packID: String) throws {
        let staging = stagingDirectory(for: packID)
        let destination = directory(for: packID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    func markInstalled(_ packID: String) {
        // Promotion already did the work; this is the hook for anything that needs to
        // happen once a pack becomes playable.
        PublicPackLibrary.reload()
    }

    func discardPartial(_ packID: String) {
        try? FileManager.default.removeItem(at: stagingDirectory(for: packID))
    }

    func remove(_ packID: String) {
        try? FileManager.default.removeItem(at: directory(for: packID))
        PublicPackLibrary.reload()
    }

    func sizeOnDisk(_ packID: String) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory(for: packID), includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
