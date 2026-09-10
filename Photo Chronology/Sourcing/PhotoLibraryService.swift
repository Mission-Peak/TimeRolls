//
//  PhotoLibraryService.swift
//  Photo Chronology
//
//  PhotoKit access. v1 reads metadata only — creationDate and location.
//  No image bytes are read here (spec §6.1, §9).
//

import Foundation
import Photos
import Observation

struct AlbumInfo: Identifiable, Hashable {
    var id: String
    var title: String
    var estimatedCount: Int
    var isSmartAlbum: Bool
}

@Observable
@MainActor
final class PhotoLibraryService {

    enum Access: Equatable {
        case notDetermined
        case granted
        case limited
        case denied

        var canRead: Bool { self == .granted || self == .limited }
    }

    private(set) var access: Access = .notDetermined
    private(set) var albums: [AlbumInfo] = []
    /// Metadata-only view of the player's library, newest first.
    private(set) var photos: [GamePhoto] = []
    private(set) var isLoading = false

    /// Screenshots are excluded by default — they are rarely reminiscence material (spec §6.1).
    private(set) var screenshotIdentifiers: Set<String> = []

    init() {
        access = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func map(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .authorized: .granted
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.map(status)
    }

    /// Reload the metadata index. Cheap enough to re-run whenever caregiver settings change.
    func reload(settings: CaregiverSettings) async {
        guard access.canRead else {
            photos = []
            albums = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        let scan = await Task.detached(priority: .userInitiated) {
            Self.scanLibrary(albumSelection: settings.albumSelection,
                             useAllPhotos: settings.useAllPhotos,
                             labels: settings.labels)
        }.value

        albums = scan.albums
        screenshotIdentifiers = scan.screenshots
        photos = scan.photos
    }

    nonisolated private struct ScanResult {
        var albums: [AlbumInfo] = []
        var photos: [GamePhoto] = []
        var screenshots: Set<String> = []
    }

    /// Runs off the main actor: PhotoKit fetches are synchronous and can be slow on big libraries.
    private nonisolated static func scanLibrary(albumSelection: [String: Bool],
                                               useAllPhotos: Bool,
                                               labels: [String: String]) -> ScanResult {
        var result = ScanResult()
        // Album-level caregiver labels are pushed down onto their photos.
        var inheritedLabels: [String: String] = [:]

        // --- Albums the caregiver can include/exclude.
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album,
                                                                subtype: .any,
                                                                options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: Self.imageOnlyOptions()).count
            guard count > 0 else { return }
            result.albums.append(AlbumInfo(id: collection.localIdentifier,
                                           title: collection.localizedTitle ?? "Album",
                                           estimatedCount: count,
                                           isSmartAlbum: false))
            if let label = labels[collection.localIdentifier] {
                PHAsset.fetchAssets(in: collection, options: Self.imageOnlyOptions())
                    .enumerateObjects { asset, _, _ in
                        inheritedLabels[asset.localIdentifier] = label
                    }
            }
        }

        for subtype in [PHAssetCollectionSubtype.smartAlbumScreenshots,
                        .smartAlbumSelfPortraits,
                        .smartAlbumFavorites] {
            let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                               subtype: subtype,
                                                               options: nil)
            smart.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: Self.imageOnlyOptions())
                guard assets.count > 0 else { return }
                result.albums.append(AlbumInfo(id: collection.localIdentifier,
                                               title: collection.localizedTitle ?? "Album",
                                               estimatedCount: assets.count,
                                               isSmartAlbum: true))
                if subtype == .smartAlbumScreenshots {
                    assets.enumerateObjects { asset, _, _ in
                        result.screenshots.insert(asset.localIdentifier)
                    }
                }
            }
        }
        result.albums.sort { $0.estimatedCount > $1.estimatedCount }

        // --- The photos themselves.
        var collected: [GamePhoto] = []
        var seen = Set<String>()

        func absorb(_ assets: PHFetchResult<PHAsset>) {
            assets.enumerateObjects { asset, _, _ in
                guard !seen.contains(asset.localIdentifier) else { return }
                seen.insert(asset.localIdentifier)
                collected.append(GamePhoto(
                    id: asset.localIdentifier,
                    origin: .personal(localIdentifier: asset.localIdentifier),
                    creationDate: asset.creationDate,
                    coordinate: asset.location.map {
                        Coordinate(latitude: $0.coordinate.latitude,
                                   longitude: $0.coordinate.longitude)
                    }
                ))
            }
        }

        if useAllPhotos {
            absorb(PHAsset.fetchAssets(with: .image, options: Self.imageOnlyOptions()))
        } else {
            let included = albumSelection.filter(\.value).map(\.key)
            for identifier in included {
                let fetched = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [identifier], options: nil)
                fetched.enumerateObjects { collection, _, _ in
                    absorb(PHAsset.fetchAssets(in: collection, options: Self.imageOnlyOptions()))
                }
            }
        }

        // Explicit exclusions win over inclusion.
        let excluded = Set(albumSelection.filter { !$0.value }.map(\.key))
        var excludedAssetIDs = Set<String>()
        for identifier in excluded {
            let fetched = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [identifier], options: nil)
            fetched.enumerateObjects { collection, _, _ in
                PHAsset.fetchAssets(in: collection, options: Self.imageOnlyOptions())
                    .enumerateObjects { asset, _, _ in
                        excludedAssetIDs.insert(asset.localIdentifier)
                    }
            }
        }
        if !excludedAssetIDs.isEmpty {
            collected.removeAll { excludedAssetIDs.contains($0.id) }
        }

        for index in collected.indices {
            collected[index].caregiverLabel =
                labels[collected[index].id] ?? inheritedLabels[collected[index].id]
        }

        result.photos = collected
        return result
    }

    private nonisolated static func imageOnlyOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }
}
