//
//  OneBucket.swift
//  Time Rolls
//
//  Where a pack photograph is read from (spec §10).
//
//  OneBucket sits between the app and Wasabi: the bucket stays private, OneBucket holds
//  the credentials, and the app asks it for a photograph by key. The player never has a
//  key, never downloads a pack, and never owns the pictures — they are read to the device,
//  cached while they are in play, and rotate out again.
//
//  The app therefore carries **no secret of any kind**. Anything in an app binary can be
//  pulled out of it by anybody who downloads the app, so a credential shipped here is a
//  credential published. The only thing configured below is an address.
//
//  Until that address is set, packs keep reading from where they always have — the
//  original source recorded in the manifest. That fallback is deliberate: it means the
//  manifests can be switched over to keys before the endpoint exists without every pack
//  photograph turning into a blank card on somebody's iPad in the meantime.
//

import Foundation

enum OneBucket {

    /// Where OneBucket answers, or nil while it does not.
    ///
    /// Read from `Info.plist` rather than written here, so it can differ between a debug
    /// build and the App Store one without a code change — and so that it is obvious at a
    /// glance that the only thing the app is told is an address.
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "OneBucketBaseURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }

    static var isConfigured: Bool { baseURL != nil }

    /// The request that fetches one pack object.
    ///
    /// A plain GET on a path. No signing, no token, nothing to leak: whatever
    /// authentication OneBucket needs is between it and Wasabi, on its side of the wire.
    static func request(forKey key: String) -> URLRequest? {
        // A signed URL when credentials are configured, and the plain address otherwise.
        // The bucket is private, so unsigned requests are refused — but falling back to
        // the plain form keeps a build without credentials honest rather than silently
        // broken, and the manifest's original source is tried after this in either case.
        if let signed = PresignedURL.get(key: key) {
            var request = URLRequest(url: signed)
            request.httpMethod = "GET"
            request.setValue("TimeRolls/\(Self.appVersion) (pack delivery)",
                             forHTTPHeaderField: "User-Agent")
            // Never cache a signed URL by its address: the signature changes every time,
            // so the cache would fill with entries that can never be hit again.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            return request
        }
        guard let baseURL else { return nil }
        let url = baseURL.appending(path: key)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // So a pack fetch is recognisable in OneBucket's logs, and so that a future
        // version of the app can be served different bytes without guessing.
        request.setValue("TimeRolls/\(Self.appVersion) (pack delivery)",
                         forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad
        return request
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Where to read a pack item from: OneBucket when it is configured and the manifest
    /// says where the object lives, and otherwise wherever the photograph came from.
    static func source(key: String?, original: URL?) -> URLRequest? {
        if let key, let request = request(forKey: key) { return request }
        guard let original else { return nil }
        return URLRequest(url: original)
    }
}
