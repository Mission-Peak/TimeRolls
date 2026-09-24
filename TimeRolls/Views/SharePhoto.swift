//
//  SharePhoto.swift
//  Time Rolls
//
//  Sharing a photograph from the round somebody is looking at (spec §7).
//
//  The reason this exists is the app's own doing: it puts a photograph in front of
//  somebody that they had forgotten they owned, and the natural next thought is to send it
//  to whoever else is in it. Making them close the game, open Photos and find it again is
//  the point at which the thought is lost.
//
//  Two things go out, not one. Sharing hands the picture to whatever the person picks —
//  Messages, Mail, WhatsApp — and saving puts a copy in their own library, which is what
//  somebody means when they say "I want that one".
//
//  **Attribution travels with a pack photograph.** Most of them are CC BY or CC BY-SA,
//  which permit sharing precisely on the condition that the photographer is credited. A
//  picture sent on without that is a licence breach committed by the app rather than by
//  the person, so the credit, the licence and the page it came from go into the share
//  alongside the image. Nothing is attached to somebody's own photograph — it is theirs,
//  and the app has nothing to say about it.
//

import SwiftUI
import Photos

enum SharePhoto {

    /// The line that travels with a pack photograph, or nil for the player's own.
    ///
    /// Read from the pack rather than from the photograph, because `GamePhoto` is the
    /// curation layer's type and deliberately knows nothing about licences.
    /// Licences that ask for nothing: the photograph may be sent on bare.
    ///
    /// Attaching a credit anyway is not harmless. It puts a line of licence text on a
    /// photograph somebody is sending to their daughter, and it implies a condition the
    /// licence does not impose. About a fifth of the pack photographs are in this
    /// position — public domain or CC0 — and they should travel as plainly as one of the
    /// player's own.
    private static let asksForNothing = ["public domain", "cc0", "no restrictions", "pd-"]

    @MainActor
    static func credit(for photo: GamePhoto) -> String? {
        guard case let .pack(packID, itemID) = photo.origin,
              let item = PublicPackLibrary.item(packID: packID, itemID: itemID),
              let credit = item.credit
        else { return nil }
        let licence = credit.license.lowercased()
        if asksForNothing.contains(where: { licence.contains($0) }) { return nil }
        var parts = [credit.title, credit.creator, credit.license, credit.sourceURL]
        parts = parts.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Put a copy in the player's own library.
    ///
    /// Asks for permission to *add* rather than to read everything, which is the narrower
    /// of the two and the only one this needs.
    static func save(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { finished in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { saved, _ in
                finished.resume(returning: saved)
            }
        }
    }
}

