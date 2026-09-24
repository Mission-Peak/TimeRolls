//
//  QuestionPhrasing.swift
//  Time Rolls
//
//  Apple's on-device model, used for one job and one job only: saying the same question
//  in different words.
//
//  Nothing about the round is the model's to decide. The photographs, the answer, the
//  difficulty and the facts are all settled by curation before this is asked anything,
//  and the only thing it may return is a rewording of a question that already exists.
//  Everything it returns is checked before it is shown, and anything that fails a check
//  is dropped in favour of the written question. A rejected rewording costs nothing; a
//  bad one that reached an eighty-year-old would cost a great deal.
//

import Foundation
import FoundationModels

@Observable
@MainActor
final class QuestionPhrasing {

    /// One attempt, kept so the caregiver can see what the model is actually producing.
    struct Sample: Identifiable, Equatable {
        let id = UUID()
        let original: String
        let candidate: String
        let verdict: String?
        var accepted: Bool { verdict == nil }
    }

    /// Why livelier questions are or are not running, in words a caregiver can read.
    private(set) var status: String = "Not started"
    private(set) var isAvailable = false
    private(set) var samples: [Sample] = []

    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var cache: [String: String] = [:]

    /// How long a round will wait for a rewording. The written question is already on
    /// screen-ready; this is a garnish and must never hold up a round.
    private let budget: Duration = .seconds(2)

    init() {
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
            status = "Ready"
        case let .unavailable(reason):
            isAvailable = false
            status = switch reason {
            case .deviceNotEligible: "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled: "Apple Intelligence is switched off in Settings"
            case .modelNotReady: "Apple Intelligence is still downloading"
            @unknown default: "Apple Intelligence is unavailable"
            }
        @unknown default:
            isAvailable = false
            status = "Apple Intelligence is unavailable"
        }
    }

    /// A rewording of this round's question, or nil to use the written one.
    func phrasing(for level: Level) async -> String? {
        guard isAvailable else { return nil }
        if let remembered = cache[level.prompt] { return remembered }

        let candidate = await withTimeout(budget) { [weak self] in
            await self?.ask(level.prompt)
        }
        guard let candidate else {
            record(Sample(original: level.prompt, candidate: "—", verdict: "no answer in time"))
            return nil
        }

        let verdict = QuestionGuardrail.reject(candidate, rewordingOf: level.prompt, in: level)
        record(Sample(original: level.prompt, candidate: candidate, verdict: verdict))
        guard verdict == nil else { return nil }
        cache[level.prompt] = candidate
        return candidate
    }

    /// Ten reworded questions for the caregiver to read before turning this on.
    func sampleRun(for prompt: String, level: Level) async {
        for _ in 0..<5 {
            guard let candidate = await withTimeout(budget, operation: { [weak self] in
                await self?.ask(prompt)
            }) else {
                record(Sample(original: prompt, candidate: "—", verdict: "no answer in time"))
                continue
            }
            record(Sample(original: prompt,
                          candidate: candidate,
                          verdict: QuestionGuardrail.reject(candidate, rewordingOf: prompt, in: level)))
        }
    }

    func clearSamples() { samples = [] }

    // MARK: - The model

    private func ask(_ prompt: String) async -> String? {
        let session = session ?? LanguageModelSession(instructions: Self.instructions)
        self.session = session
        do {
            let response = try await session.respond(
                to: "Rewrite this question: \(prompt)",
                options: GenerationOptions(temperature: 1.0))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            status = "Stopped: \(error.localizedDescription)"
            return nil
        }
    }

    private func record(_ sample: Sample) {
        samples.insert(sample, at: 0)
        samples = Array(samples.prefix(12))
    }

    private nonisolated static let instructions = """
    You reword one short question for a gentle photo game played by older adults.

    Rules, all of them absolute:
    - Keep the meaning exactly. Never change what is being asked.
    - Keep every name, place and word for a thing exactly as given. Never add one.
    - One sentence, a question, at most twelve words.
    - Warm and plain. No exclamation marks, no emoji, no quotation marks.
    - Never mention where a photo sits on the screen, and never say how many there are.
    - Never say which photo is correct, and never add a fact of your own.
    - Reply with the question only.
    """

    private func withTimeout(_ duration: Duration,
                             operation: @escaping () async -> String?) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: duration)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
