//
//  RoundAudit.swift
//  Time Rolls
//
//  A second pair of eyes on a round that curation has already finished building.
//
//  Everything in Curators.swift decides a round from what it can measure: where a
//  photograph was taken, when, how alike two of them look, what the embedding says is
//  in them. That is enough to be sure the answer is *true* and not enough to be sure it
//  is *findable*. Three anonymous streets beside the one that is really Shibuya is a
//  correct round and an unplayable one, and no amount of metadata notices that.
//
//  So this asks the on-device model to play the round. It sees the same photographs the
//  player will see and the same question, and it picks one. If it picks ours, the round
//  ships. If it picks another, or says more than one would do, the round is dropped and
//  curation builds a different one — which costs nothing, because the next round is
//  being prepared while the player is still looking at this one.
//
//  Three boundaries, all deliberate:
//
//  1. It can only ever take a round away. It never chooses photographs, never writes a
//     question, never changes an answer, and never overrules the filters that decided a
//     receipt is not a memory. Everything it sees has already passed all of that.
//  2. It never runs on Chronology. "Which of these is older" is settled by the date in
//     the file; a model looking at the grain of a photograph would be guessing, and a
//     confident guess is exactly what this is here to prevent.
//  3. Silence means yes. No model, no Apple Intelligence, no answer inside the budget —
//     the round ships as it would have before any of this existed, which is what every
//     device below iOS 27 does all the time.
//

import Foundation
import FoundationModels
import UIKit

@available(iOS 27.0, *)
@Generable
private struct Judgement {
    @Guide(description: "The one photograph that answers the question.")
    var answer: ImageReference
    @Guide(description: "True if two or more of the photographs answer the question equally well, or if none of them clearly does.")
    var arguable: Bool
}

@Observable
@MainActor
final class RoundAudit {

    /// One judgement, kept so a caregiver can see what the model is actually rejecting.
    struct Sample: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let outcome: String
        let kept: Bool
    }

    /// Why round-checking is or is not running, in words a caregiver can read.
    private(set) var status: String = "Not started"
    private(set) var isAvailable = false
    private(set) var samples: [Sample] = []
    private(set) var kept = 0
    private(set) var dropped = 0

    /// One line for the row that leads to the diagnostics screen.
    var summary: String {
        guard isAvailable else { return status }
        guard kept + dropped > 0 else { return "Nothing checked yet" }
        return dropped == 0
            ? "\(kept) checked, none turned down"
            : "\(dropped) of \(kept + dropped) turned down"
    }

    @ObservationIgnored private var session: LanguageModelSession?
    /// Rounds already judged. Curation can rebuild the same set from the same pool, and
    /// a verdict that cost four photographs and several seconds is worth keeping.
    @ObservationIgnored private var remembered: [String: Bool] = [:]

    /// How long a round may wait to be checked. Generous, because this runs while the
    /// player is still on the round before it — but bounded, because a round that is
    /// never judged has to ship, and shipping late is worse than shipping unchecked.
    private let budget: Duration = .seconds(8)

    /// What the model is shown. Large enough to read a scene, small enough to be quick.
    private let thumbnail = CGSize(width: 512, height: 512)

    init() {
        guard #available(iOS 27.0, *) else {
            status = "Needs iOS 27 — rounds ship unchecked"
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
            status = "Ready"
        case let .unavailable(reason):
            status = switch reason {
            case .deviceNotEligible: "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled: "Apple Intelligence is switched off in Settings"
            case .modelNotReady: "Apple Intelligence is still downloading"
            @unknown default: "Apple Intelligence is unavailable"
            }
        @unknown default:
            status = "Apple Intelligence is unavailable"
        }
    }

    /// Whether this round is fit to be played. False only when the model actively
    /// disagreed with it; every other outcome — including every failure — is true.
    func approves(_ level: Level, using provider: ImageProvider) async -> Bool {
        guard isAvailable,
              RoundAuditRules.judges(theme: level.theme,
                                     usesPersonalPhotos: level.photos.contains { $0.isPersonal })
        else { return true }
        let signature = Self.signature(of: level)
        if let verdict = remembered[signature] { return verdict }
        guard #available(iOS 27.0, *) else { return true }

        let outcome = await withTimeout(budget) { [weak self] in
            await self?.judge(level, using: provider)
        }
        let verdict = outcome ?? .unjudged("no answer in time")
        record(level, verdict)
        remembered[signature] = verdict.keepsRound
        return verdict.keepsRound
    }

    // MARK: - Asking

    private typealias Outcome = RoundAuditRules.Outcome

    private func attachmentLabels(count: Int) -> [String] {
        (1...max(count, 1)).map { "photo \($0)" }
    }

    private static func signature(of level: Level) -> String {
        level.prompt + "|" + level.photos.map(\.id).sorted().joined(separator: ",")
    }

    @available(iOS 27.0, *)
    private func judge(_ level: Level, using provider: ImageProvider) async -> Outcome {
        var attachments: [Attachment<ImageAttachmentContent>] = []
        var labelOfAnswer: String?

        for (index, photo) in level.photos.enumerated() {
            guard let image = await provider.image(for: photo, targetSize: thumbnail),
                  let cgImage = image.cgImage else {
                return .unjudged("a photograph couldn't be fetched")
            }
            let label = "photo \(index + 1)"
            if photo.id == level.correctPhotoID { labelOfAnswer = label }
            attachments.append(Attachment(cgImage, orientation: image.cgImageOrientation).label(label))
        }
        guard let labelOfAnswer else { return .unjudged("no answer in the set") }

        let session = session ?? LanguageModelSession(instructions: Self.instructions)
        self.session = session

        let question = level.hint.map { "\(level.prompt) (\($0))" } ?? level.prompt
        do {
            let reply = try await session.respond(generating: Judgement.self) {
                question
                attachments
            }
            let judgement = reply.content
            if judgement.arguable { return .arguable }
            let labels = attachmentLabels(count: level.photos.count)
            guard let said = RoundAuditRules.labelSaid(judgement.answer.attachmentLabel,
                                                       amongst: labels) else {
                return .unjudged("answered with “\(judgement.answer.attachmentLabel)”")
            }
            return said == labelOfAnswer ? .agreed : .chose(said)
        } catch {
            // A refusal, a context overflow, a guardrail — none of it is evidence
            // against the round, so none of it takes the round away.
            return .unjudged(String(describing: error).prefix(60).description)
        }
    }

    private static let instructions = """
    You are checking a picture puzzle before it is shown to an older player, some of \
    whom have memory difficulties. You will be given a question and several labelled \
    photographs.

    - Choose the one photograph that answers the question.
    - Judge only what you can see in the photographs themselves.
    - Say it is arguable if two or more of them answer the question equally well, or if \
    none of them clearly does. A puzzle with no findable answer is worse than no puzzle.
    """

    // MARK: - Diagnostics

    private func record(_ level: Level, _ outcome: Outcome) {
        let note = switch outcome {
        case .agreed: "agreed"
        case let .chose(label): "picked \(label) instead"
        case .arguable: "more than one would do"
        case let .unjudged(why): "not judged — \(why)"
        }
        if outcome.keepsRound { kept += 1 } else { dropped += 1 }
        samples.insert(Sample(question: level.prompt, outcome: note, kept: outcome.keepsRound),
                       at: 0)
        if samples.count > 12 { samples.removeLast() }
    }

    private func withTimeout(_ duration: Duration,
                             operation: @escaping () async -> Outcome?) async -> Outcome? {
        await withTaskGroup(of: Outcome?.self) { group in
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

private extension UIImage {
    /// The model is handed a CGImage, which has no idea which way up it is.
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
