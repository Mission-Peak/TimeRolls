//
//  PhotoIntake.swift
//  Time Rolls
//
//  Asking the on-device model what a personal photograph is, once, before it is ever
//  shown (spec §3, the filtering half).
//
//  The rules in `DescribedPhotos` were written before anything produced descriptions for
//  them to read, so they sat idle while a receipt reached a round asking which photograph
//  was older. The model could name it — measured, on that exact photograph: "a receipt
//  from a store with a barcode and text" in 2.1 seconds — but nothing had asked. The only
//  thing between the receipt and the round was a text-area heuristic that under-measured
//  it, because a receipt's lines are slivers and most of the paper lies between them.
//
//  Three boundaries, all deliberate, and the first two are Fraidun's:
//
//  1. **Downstream of the rules, never instead of them.** A photograph the rule-based
//     filters have already rejected is never described; a photograph they accepted can
//     only be set aside here for being a note to self, never re-admitted.
//  2. **It only ever takes photographs away**, and only on the strength of what the model
//     said it *saw*. It never decides a round, an answer, or what a photograph is of.
//  3. **Silence keeps the photograph.** No iOS 27, no Apple Intelligence, model busy, an
//     error, a description nothing in the rules recognises — all of it means the library
//     plays exactly as it would have before this existed, which is what every device below
//     iOS 27 does permanently.
//

import Foundation
import Observation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
@MainActor
final class PhotoIntake {

    /// What the model made of a photograph. Stored by asset id.
    struct Verdict: Codable, Hashable {
        /// Nil when it is a memory; the reason when it is not ("a receipt", "a surface").
        var setAsideBecause: String?
        /// Kept so a caregiver can see what the model actually said rather than trusting it.
        var described: String
        var version: Int
    }

    /// Bump when the rules change, so old verdicts are re-derived rather than trusted.
    static let version = 1

    private(set) var verdicts: [String: Verdict] = [:]
    private(set) var isWorking = false
    private(set) var setAsideCount = 0
    /// Why it is not running, in words a caregiver can read.
    private(set) var status = "Not started"

    private var worker: Task<Void, Never>?
    private let storeURL: URL

    /// How many photographs to look at in one sweep before yielding.
    ///
    /// About a second and a half each, so a large library takes several sessions. That is
    /// deliberate: this runs behind the game rather than in front of it, and a photograph
    /// nobody has described yet is simply a photograph nobody has described yet.
    private let chunk = 8

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        storeURL = support.appendingPathComponent("photo-intake.json")
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([String: Verdict].self, from: data) {
            verdicts = decoded.filter { $0.value.version == Self.version }
        }
        setAsideCount = verdicts.values.count { $0.setAsideBecause != nil }
    }

    /// Whether this photograph has been ruled a note to self. Unknown means keep.
    func isANoteToSelf(_ id: String) -> Bool {
        verdicts[id]?.setAsideBecause != nil
    }

    /// Look at the photographs nothing has described yet, newest first.
    func start(on photos: [GamePhoto], using provider: ImageProvider) {
        guard #available(iOS 27.0, *) else {
            status = "Needs iOS 27 — photographs are filtered by the rules alone"
            return
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: break
        case let .unavailable(reason):
            status = switch reason {
            case .deviceNotEligible: "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled: "Apple Intelligence is switched off in Settings"
            case .modelNotReady: "Apple Intelligence is still downloading"
            @unknown default: "Apple Intelligence is unavailable"
            }
            return
        @unknown default:
            status = "Apple Intelligence is unavailable"
            return
        }

        let pending = photos
            .filter { $0.isPersonal && verdicts[$0.id] == nil }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        guard !pending.isEmpty else {
            status = "All \(verdicts.count) looked at"
            return
        }

        worker?.cancel()
        isWorking = true
        status = "Looking at \(pending.count) photographs"
        worker = Task { [weak self] in
            guard let self else { return }
            for photo in pending.prefix(chunk) {
                if Task.isCancelled { break }
                await look(at: photo, using: provider)
            }
            isWorking = false
            persist()
            status = verdicts.count >= photos.count(where: \.isPersonal)
                ? "All \(verdicts.count) looked at"
                : "\(verdicts.count) looked at so far"
        }
        #else
        status = "Not available in this build"
        #endif
    }

    func stop() {
        worker?.cancel()
        worker = nil
        isWorking = false
    }

    #if canImport(FoundationModels)
    @available(iOS 27.0, *)
    private func look(at photo: GamePhoto, using provider: ImageProvider) async {
        // Small: this is a judgement about what kind of thing the picture is, not about
        // anything fine-grained in it.
        guard let image = await provider.image(for: photo,
                                               targetSize: CGSize(width: 448, height: 448)),
              let cgImage = image.cgImage else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let reply = try await session.respond(generating: PhotoDescription.self) {
                "Describe this photograph."
                Attachment(cgImage).label("the photograph")
            }
            let said = reply.content.sentence
            let verdict = DescribedPhotos.read(said)
            let because: String? = switch verdict {
            case let .notAMemory(reason): reason
            case .aMemory, .unknown: nil
            }
            verdicts[photo.id] = Verdict(setAsideBecause: because, described: said,
                                         version: Self.version)
            if because != nil { setAsideCount += 1 }
        } catch {
            // A refusal or an error is not evidence against the photograph, and it is not
            // recorded either — so a later sweep can try again.
        }
    }

    private static let instructions = """
    You describe photographs plainly, in one sentence, for a game that shows people their \
    own pictures. Say what the photograph is of.
    """
    #endif

    private func persist() {
        guard let data = try? JSONEncoder().encode(verdicts) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func reset() {
        stop()
        verdicts = [:]
        setAsideCount = 0
        try? FileManager.default.removeItem(at: storeURL)
    }
}

#if canImport(FoundationModels)
@available(iOS 27.0, *)
@Generable
struct PhotoDescription {
    @Guide(description: "One plain sentence saying what this photograph shows.")
    var sentence: String
}
#endif
