//
//  ImageProvider.swift
//  Time Rolls
//
//  The only place image bytes are ever touched, and only to draw them on screen —
//  nothing is analysed, stored or transmitted (spec §9).
//

import UIKit
import Photos

@Observable
@MainActor
final class ImageProvider {

    /// The player's photographs that could not be fetched — in practice, ones that live
    /// in iCloud and are not on this device. Curation drops them from later rounds
    /// rather than dealing the same blank card again.
    private(set) var unavailablePersonalIDs: Set<String> = []

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private let manager = PHImageManager.default()

    init() {
        cache.countLimit = 120
    }

    /// A representative photo for a pack, for the category chooser.
    func preview(for pack: PhotoPack, targetSize: CGSize) async -> UIImage? {
        guard let item = pack.items.first else { return nil }
        let photo = GamePhoto(id: "preview:\(pack.id)",
                              origin: .pack(packID: pack.id, itemID: item.id),
                              creationDate: item.date,
                              coordinate: item.coordinate)
        return await image(for: photo, targetSize: targetSize)
    }

    func image(for photo: GamePhoto, targetSize: CGSize) async -> UIImage? {
        let key = "\(photo.id)-\(Int(targetSize.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image: UIImage?
        switch photo.origin {
        case let .pack(packID, itemID):
            guard let item = PublicPackLibrary.item(packID: packID, itemID: itemID) else { return nil }
            if let url = PublicPackLibrary.imageURL(for: item),
               let photograph = UIImage(contentsOfFile: url.path) {
                image = photograph
            } else if item.remoteURL != nil || item.remoteKey != nil {
                // Carried as metadata only: fetch it from where it lives, once.
                image = await RemoteImageCache.shared.image(for: item)
            } else {
                image = PackArtRenderer.image(for: item, size: targetSize)
            }
        case let .personal(localIdentifier):
            image = await personalImage(localIdentifier: localIdentifier, targetSize: targetSize)
            if image == nil {
                unavailablePersonalIDs.insert(photo.id)
            }
        }

        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private func personalImage(localIdentifier: String, targetSize: CGSize) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let scale = UITraitCollection.current.displayScale
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)

        return await withCheckedContinuation { continuation in
            let state = RequestState()
            // .aspectFit, not .aspectFill: asking PhotoKit to fill a square box can hand
            // back an already-cropped square, and the tile is drawn from the whole
            // photograph now. Cropping, if any, is the view's decision to make.
            let request = manager.requestImage(for: asset,
                                               targetSize: pixelSize,
                                               contentMode: .aspectFit,
                                               options: options) { image, info in
                // Opportunistic delivery calls back more than once: a quick blurry
                // version first, the real one after. Keep the blurry one — if the real
                // one never arrives it is better than an empty card.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    state.remember(image)
                    return
                }
                if state.claim() { continuation.resume(returning: image ?? state.best) }
            }

            // A photograph that lives in iCloud and is not on this device can leave the
            // final callback pending indefinitely — a poor connection, a paused
            // download, a library still syncing. The card was left spinning for ever.
            // After this long, take the blurry version, or give up and say so.
            Task {
                try? await Task.sleep(for: .seconds(12))
                guard state.claim() else { return }
                self.manager.cancelImageRequest(request)
                continuation.resume(returning: state.best)
            }
        }
    }
}

/// One-shot resume guard for a PhotoKit request.
///
/// PhotoKit calls its handler on a queue of its choosing and may call it more than
/// once; a continuation resumed twice is a crash, and one never resumed is a card that
/// spins for ever. Both ends are closed here.
private final class RequestState: @unchecked Sendable {

    private let lock = NSLock()
    private var hasResumed = false
    private var fallback: UIImage?

    /// True exactly once, for whoever gets there first.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasResumed { return false }
        hasResumed = true
        return true
    }

    func remember(_ image: UIImage?) {
        guard let image else { return }
        lock.lock()
        fallback = image
        lock.unlock()
    }

    var best: UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return fallback
    }
}
