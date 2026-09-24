//
//  PresignedURL.swift
//  Time Rolls
//
//  Signing a short-lived URL for one object in the pack bucket.
//
//  AWS Signature Version 4, which is what S3-compatible storage expects. The whole of it
//  is a canonical description of the request, hashed, signed with a key derived from the
//  secret, and appended as query parameters — so the URL carries its own authorisation and
//  the app never sends a credential in a header.
//
//  **Read-only, and that is the whole design.** The key this signs with can fetch objects
//  from one bucket of freely-licensed photographs and do nothing else: it is refused on
//  PutObject, on DeleteObject, and on every other bucket in the account. That was verified
//  against the live service rather than assumed from a console label, because a key in an
//  app binary is a key anybody sufficiently motivated can read out of it, and the only
//  honest way to ship one is to make sure it cannot do damage.
//
//  Five minutes, because a URL that leaks should stop working before anybody can use it,
//  and because nothing here takes longer than that to download.
//

import Foundation
import CryptoKit

enum PresignedURL {

    static let lifetime: TimeInterval = 5 * 60

    /// A signed GET for one object, or nil when no credentials are configured.
    static func get(key: String,
                    now: Date = Date(),
                    lifetime: TimeInterval = PresignedURL.lifetime) -> URL? {
        guard let host = Secrets.oneBucketHost,
              let accessKey = Secrets.oneBucketAccessKeyID,
              let secret = Secrets.oneBucketSecretAccessKey,
              !accessKey.isEmpty, !secret.isEmpty
        else { return nil }

        let region = Secrets.oneBucketRegion
        let service = "s3"
        let stamp = Self.stamp(now), day = String(stamp.prefix(8))
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let path = "/\(Secrets.oneBucketName)/\(key)"

        // Ordered by name, as the signature requires.
        var query = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", "\(accessKey)/\(scope)"),
            ("X-Amz-Date", stamp),
            ("X-Amz-Expires", String(Int(lifetime))),
            ("X-Amz-SignedHeaders", "host"),
        ]
        let canonicalQuery = query
            .map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")

        let canonical = [
            "GET",
            path.split(separator: "/").map { escape(String($0)) }
                .joined(separator: "/").prepending("/"),
            canonicalQuery,
            "host:\(host)\n",
            "host",
            "UNSIGNED-PAYLOAD",
        ].joined(separator: "\n")

        let toSign = [
            "AWS4-HMAC-SHA256", stamp, scope, hex(SHA256.hash(data: Data(canonical.utf8))),
        ].joined(separator: "\n")

        var signing = hmac(Data("AWS4\(secret)".utf8), Data(day.utf8))
        for part in [region, service, "aws4_request"] {
            signing = hmac(signing, Data(part.utf8))
        }
        query.append(("X-Amz-Signature", hex(hmac(signing, Data(toSign.utf8)))))

        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = path
        parts.percentEncodedQuery = query
            .map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")
        return parts.url
    }

    // MARK: - The small pieces

    /// Everything but the unreserved set, and `/` is escaped too — a key with a slash in
    /// it is one path segment as far as the signature is concerned.
    private static func escape(_ text: String) -> String {
        let safe = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: safe) ?? text
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func hmac(_ key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private static func hex<T: Sequence>(_ bytes: T) -> String where T.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    func prepending(_ text: String) -> String { text + self }
}
