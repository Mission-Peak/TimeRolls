//
//  Secrets.swift
//  Time Rolls
//
//  **A placeholder, and it is in version control on purpose.**
//
//  The real one is git-ignored and sits beside it. This exists so the project still builds
//  for anybody who clones it without credentials — they get an app that reads pack photos
//  from their original source, which is exactly what it did before the bucket existed.
//
//  Nothing here is secret. If you are reading this file expecting a key, you want
//  Secrets.local.swift, which is not in the repository and should never be.
//

import Foundation

enum Secrets {

    /// Where the pack bucket answers, and what it is called.
    static let oneBucketHost: String? = value("OneBucketHost")
    static let oneBucketName = value("OneBucketName") ?? "timerolls-readonly"
    static let oneBucketRegion = value("OneBucketRegion") ?? "us-east-1"

    /// The read-only pair. Nil in a clone without credentials, and the app then reads pack
    /// photographs from where they came from instead — which is what it did all along.
    static let oneBucketAccessKeyID: String? = value("OneBucketAccessKeyID")
    static let oneBucketSecretAccessKey: String? = value("OneBucketSecretAccessKey")

    /// Read from the bundle rather than written here, so the values live in a plist the
    /// build writes and never in a source file somebody might commit by habit.
    ///
    /// `OneBucket.plist` first, then the Info dictionary. These used to be declared as
    /// `INFOPLIST_KEY_OneBucketAccessKeyID` and friends, which resolved correctly in the
    /// build settings and then never appeared in the built app: Xcode's `INFOPLIST_KEY_`
    /// mechanism only injects keys it recognises, and a custom name is dropped silently.
    /// Nothing failed loudly — the app simply read nil, could not sign a URL, and fetched
    /// every pack photograph from its original source instead of from the bucket. The
    /// Info dictionary is still consulted second, so a build configured the old way keeps
    /// working.
    private static func value(_ name: String) -> String? {
        if let raw = settingsFile?[name] as? String, !raw.isEmpty, !raw.hasPrefix("$(") {
            return raw
        }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: name) as? String,
              !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    /// Written into the bundle by the "Embed OneBucket settings" build phase. Absent in a
    /// clone with no credentials, which is the case this whole file exists to survive.
    private static let settingsFile: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "OneBucket", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }()
}
