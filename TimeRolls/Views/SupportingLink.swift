//
//  SupportingLink.swift
//  Time Rolls
//
//  Where "find out how" goes. Kept apart from the timing rules in Supporting.swift, which
//  are plain arithmetic the harness reads and must not drag UIKit in with them.
//

import Foundation
import UIKit

extension Supporting {

    /// Empty until somebody sets it, and the whole feature stays invisible until then —
    /// a button promising a way to give that opens nothing is worse than no button.
    ///
    /// **Read Tools/SUPPORTING.md before setting this.** What may legitimately go here is
    /// an App Store rule rather than a choice, and it turns on whether Mission Peak is a
    /// registered nonprofit.
    @MainActor static var url: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupportURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }

    @MainActor static var isAvailable: Bool { url != nil }

    @MainActor static func open() {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}
