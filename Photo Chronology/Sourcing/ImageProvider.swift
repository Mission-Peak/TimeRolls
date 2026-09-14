//
//  ImageProvider.swift
//  Photo Chronology
//
//  The only place image bytes are ever touched, and only to draw them on screen —
//  nothing is analysed, stored or transmitted (spec §9).
//

import UIKit
import Photos

@MainActor
final class ImageProvider {

    private let cache = NSCache<NSString, UIImage>()
    private let manager = PHImageManager.default()

    init() {
        cache.countLimit = 120
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
            } else {
                image = PackArtRenderer.image(for: item, size: targetSize)
            }
        case let .personal(localIdentifier):
            image = await personalImage(localIdentifier: localIdentifier, targetSize: targetSize)
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
            var resumed = false
            manager.requestImage(for: asset,
                                 targetSize: pixelSize,
                                 contentMode: .aspectFill,
                                 options: options) { image, info in
                // Opportunistic delivery can call back more than once.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !resumed, !isDegraded else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
