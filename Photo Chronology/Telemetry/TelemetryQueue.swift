//
//  TelemetryQueue.swift
//  Photo Chronology
//
//  Buffers engagement events and flushes them to a sink (spec §8).
//

import Foundation
import Observation

@Observable
@MainActor
final class TelemetryQueue {

    private(set) var pending: [EngagementEvent] = []
    private(set) var sentCount = 0
    private(set) var lastFlush: Date?
    private(set) var lastError: String?

    /// Swapped for `OneBucketSink` once the bucket and schema are settled.
    let sink: EngagementSink

    private let flushThreshold = 5
    private let queueURL: URL

    init(sink: EngagementSink = LocalFileSink()) {
        self.sink = sink
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        queueURL = support.appendingPathComponent("engagement-queue.json")
        if let data = try? Data(contentsOf: queueURL) {
            let decoder = JSONDecoder()
            pending = (try? decoder.decode([EngagementEvent].self, from: data)) ?? []
        }
    }

    func record(_ event: EngagementEvent) {
        pending.append(event)
        persistQueue()
        if pending.count >= flushThreshold {
            Task { await flush() }
        }
    }

    func flush() async {
        guard !pending.isEmpty, sink.isConfigured else { return }
        let batch = pending
        do {
            try await sink.send(batch)
            pending.removeAll { event in batch.contains { $0.id == event.id } }
            sentCount += batch.count
            lastFlush = Date()
            lastError = nil
            persistQueue()
        } catch {
            // Keep the batch queued; engagement data is never worth interrupting play for.
            lastError = error.localizedDescription
        }
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }
}
