//
//  ImageProvider.swift
//  Time Rolls
//
//  The only place image bytes are ever touched, and only to draw them on screen —
//  nothing is analysed, stored or transmitted (spec §9).
//

import UIKit
import Photos
import ImageIO

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
        // By size, not by count. A count of 120 held up to 120 full-size pack photographs
        // — about nine megabytes each once decoded — and memory climbed past 700 MB within
        // a minute of steady play, which is how an iPhone ends a game for you.
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    /// The most pixels along the longer side a photograph is ever decoded at. The zoom
    /// view asks for 1400 points, which on a 3x phone was 4200 pixels — seventy megabytes
    /// for one picture, far more than the screen can show.
    private static let largestSide: CGFloat = 2400

    private func pixels(for targetSize: CGSize) -> CGFloat {
        min(max(targetSize.width, targetSize.height) * UITraitCollection.current.displayScale,
            Self.largestSide)
    }

    /// A photograph file read at the size it will be shown, never in full. Decoding a
    /// 1280×1700 pack photograph to put it in a 200-point tile cost nine megabytes; read
    /// this way it costs what the tile needs.
    private nonisolated static func downsampled(_ url: URL, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
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
            let maxPixels = pixels(for: targetSize)
            if let url = PublicPackLibrary.imageURL(for: item),
               let photograph = await Task.detached(priority: .userInitiated, operation: {
                   Self.downsampled(url, maxPixels: maxPixels)
               }).value {
                image = photograph
            } else if item.remoteURL != nil || item.remoteKey != nil {
                // Carried as metadata only: fetch it from where it lives, once, then read
                // the saved file at the size it is shown.
                let fetched = RemoteImageCache.shared.cachedFile(for: item) == nil
                    ? await RemoteImageCache.shared.image(for: item) : nil
                if let file = RemoteImageCache.shared.cachedFile(for: item),
                   let small = await Task.detached(priority: .userInitiated, operation: {
                       Self.downsampled(file, maxPixels: maxPixels)
                   }).value {
                    image = small
                } else {
                    image = fetched
                }
            } else {
                image = PackArtRenderer.image(for: item, size: targetSize)
            }
        case let .personal(localIdentifier):
            image = await personalImage(localIdentifier: localIdentifier, targetSize: targetSize)
            if image == nil {
                unavailablePersonalIDs.insert(photo.id)
            }
        }

        if let image { cache.setObject(image, forKey: key, cost: Self.cost(of: image)) }
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

        let side = pixels(for: targetSize)
        let pixelSize = CGSize(width: side, height: side)

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
