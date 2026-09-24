//
//  Engagement.swift
//  Time Rolls
//
//  Anonymous engagement telemetry (spec §8, §9).
//
//  What a payload may carry: theme, correct/incorrect, attempts, duration, difficulty,
//  set size. What it must never carry: photo identifiers, photo dates, place names,
//  album names, labels, or anything about *which* person or place was recognised —
//  that would cross into decline-detection territory the project deliberately avoids.
//

import Foundation

nonisolated enum DeviceIdentity {
    private static let key = "device-id-v1"

    /// Generated at first launch. This is the whole OneBucket namespace — no login (spec §8).
    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

nonisolated struct EngagementEvent: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case sessionStart
        case sessionEnd
        case levelCompleted
    }

    var id = UUID()
    var deviceID = DeviceIdentity.current
    var timestamp = Date()
    var kind: Kind
    var theme: String?
    var wasCorrect: Bool?
    var attempts: Int?
    var durationMS: Int?
    var difficulty: Double?
    var photoSetSize: Int?
    var blendedPackPhotos: Bool?
    var levelsInSession: Int?
}

/// Where queued events go. The prototype ships the local sink; the OneBucket sink is
/// the slot for the real client once the bucket and event schema are settled (spec §12).
nonisolated protocol EngagementSink: Sendable {
    var name: String { get }
    var isConfigured: Bool { get }
    func send(_ events: [EngagementEvent]) async throws
}

/// Writes newline-delimited JSON to Application Support. Nothing leaves the device.
nonisolated struct LocalFileSink: EngagementSink {
    let name = "On-device log"
    let isConfigured = true

    var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support.appendingPathComponent("engagement-events.jsonl")
    }

    func send(_ events: [EngagementEvent]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var blob = Data()
        for event in events {
            blob.append(try encoder.encode(event))
            blob.append(0x0A)
        }
        let url = fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: blob)
        } else {
            try blob.write(to: url, options: .atomic)
        }
    }
}

/// Not wired up. Bucket namespace and event schema are open decisions (spec §12);
/// AgentMark's upload queue + MCPClient is the intended starting point.
nonisolated struct OneBucketSink: EngagementSink {
    let name = "OneBucket"
    let isConfigured = false

    func send(_ events: [EngagementEvent]) async throws {
        throw NSError(domain: "PhotoChronology", code: 1, userInfo: [
            NSLocalizedDescriptionKey:
                "OneBucket sink not configured: bucket namespace and engagement-event schema are open items."
        ])
    }
}
