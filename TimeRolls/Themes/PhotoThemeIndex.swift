//
//  PhotoThemeIndex.swift
//  Time Rolls
//
//  What a photograph is *of*, in the sense a person means it: a birthday, a beach, the
//  garden, the dog.
//
//  Vision's classifier names things in a picture ("cake", "sand"). This names the
//  occasion, by comparing the photograph against a written list of themes. The list is
//  in `Tools/Themes/themes.json` and is ordinary English — curating by writing sentences
//  rather than by tagging thousands of photographs.
//
//  Everything happens on this device. The model is OpenAI's CLIP image encoder (MIT),
//  bundled at 84 MB; the themes were turned into vectors once on a Mac, so the text half
//  of the model never ships. No photograph and no label leaves the phone.
//

import CoreML
import CoreVideo
import Foundation
import UIKit

struct PhotoTheme: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// What a round asks when every photograph in it shares this theme.
    let question: String
    /// What a round asks when only one photograph in it shares this theme.
    ///
    /// Every theme's own question is a chronology one — "which birthday came first?" —
    /// which works between a player's own photographs, where they were there for both.
    /// Between four strangers' photographs it is unanswerable: nobody can date somebody
    /// else's birthday party, and two photographs taken a year apart have no tell at all.
    /// So a theme carries a second question that asks what a photograph *shows* rather
    /// than when it happened, and that one can be asked of anybody's pictures.
    let identify: String
    let vector: [Float]
}

/// Predictions are thread-safe and this holds nothing else that changes, so it runs
/// wherever the tagging pass happens to be rather than hopping to the main actor for
/// every photograph.
nonisolated final class PhotoThemeIndex: @unchecked Sendable {

    static let shared = PhotoThemeIndex()

    private(set) var themes: [PhotoTheme] = []
    /// One per thing the Things game can ask about, used to check the classifier's work.
    private(set) var concepts: [String: PhotoTheme] = [:]
    /// Whether a photograph shows a place at all, rather than somebody's face.
    private(set) var scenes: [String: PhotoTheme] = [:]
    private(set) var unavailableReason: String?

    private let model: PhotoThemes?

    private init() {
        themes = Self.loadThemes("theme-vectors")
        concepts = Dictionary(uniqueKeysWithValues:
            Self.loadThemes("concept-vectors").map { ($0.id, $0) })
        scenes = Dictionary(uniqueKeysWithValues:
            Self.loadThemes("scene-vectors").map { ($0.id, $0) })
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try? PhotoThemes(configuration: configuration)
        if model == nil { unavailableReason = "The themes model could not be loaded" }
    }

    var isReady: Bool { model != nil && !themes.isEmpty }

    /// The photograph as 512 numbers. Comparable to any other photograph's, and to the
    /// themes; not an image, and nothing that can be turned back into one.
    func embedding(for image: CGImage) -> [Float]? {
        guard let model, let buffer = Self.pixels(from: image) else { return nil }
        guard let output = try? model.prediction(image: buffer) else { return nil }
        let raw = output.embedding
        var values = [Float](repeating: 0, count: raw.count)
        for index in 0 ..< raw.count {
            values[index] = raw[index].floatValue
        }
        return Self.normalised(values)
    }

    /// The closest theme, and how close it is. Nil when nothing comes near enough to be
    /// worth saying out loud.
    /// Every theme this photograph is arguably of.
    ///
    /// `theme(for:)` answers "what is this, confidently" and returns nothing at all when
    /// two themes are close. This answers the opposite question — "what might somebody
    /// call this" — and is deliberately looser: no margin against the runner-up, and a
    /// lower bar than a confident match needs.
    ///
    /// It is used to keep distractors out of an identify round, where being generous is
    /// the safe mistake. A photograph that is arguably a wedding must not stand next to
    /// the wedding in "which one shows a wedding?", and losing it as a distractor costs
    /// nothing, because there are always more photographs that are plainly something else.
    func plausibleThemes(for embedding: [Float]) -> Set<String> {
        guard !embedding.isEmpty else { return [] }
        let floor = Self.threshold - Self.margin
        return Set(themes.filter { Double(Self.dot(embedding, $0.vector)) >= floor }
                         .map(\.id))
    }

    func theme(for embedding: [Float]) -> (theme: PhotoTheme, score: Double)? {
        guard !embedding.isEmpty else { return nil }
        let scored = themes
            .map { ($0, Double(Self.dot(embedding, $0.vector))) }
            .sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= Self.threshold else { return nil }
        // And clear of the next theme down. Without this a photograph of a lawn is
        // "a graduation" because that was the best of twenty-six weak matches, and a
        // round of four such photographs asks about a graduation that never happened.
        let runnerUp = scored.dropFirst().first?.1 ?? -1
        guard best.1 - runnerUp >= Self.margin else { return nil }
        // The same null test as the concepts. A graduation party is not a graduation,
        // and neither is a lawn: both lose to "a photograph".
        guard best.1 - nothingInParticular(embedding) >= Self.nullMargin else { return nil }
        return (best.0, best.1)
    }

    /// How much this photograph looks like the thing the Things game is about to ask
    /// about. Nil when that thing has no prompt, or the photograph was never embedded.
    func score(_ embedding: [Float], concept: String) -> Double? {
        guard let concept = concepts[concept], !embedding.isEmpty else { return nil }
        return Double(Self.dot(embedding, concept.vector))
    }

    /// Which of the things the game can ask about this photograph looks most like.
    ///
    /// The check that matters: a round may ask "which one has a dog in it" only when
    /// this agrees that the answer is a dog. A classifier that mistakes a cat for a dog
    /// produces a photograph whose best match here is plainly the cat.
    func bestConcept(_ embedding: [Float]) -> String? {
        strongestConcept(embedding)?.id
    }

    /// The best match and how good it is, with the runner-up taken into account.
    ///
    /// A question is only worth asking when the photograph is plainly of the thing:
    /// both above a floor, and clear of whatever came second. Everything else gets no
    /// concept at all and is used only as a distractor.
    func strongestConcept(_ embedding: [Float]) -> (id: String, score: Double)? {
        guard !embedding.isEmpty, !concepts.isEmpty else { return nil }
        let scored = concepts.values
            .map { ($0.id, Double(Self.dot(embedding, $0.vector))) }
            .sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= Self.conceptFloor else { return nil }
        let runnerUp = scored.dropFirst().first?.1 ?? -1
        guard best.1 - runnerUp >= Self.conceptMargin else { return nil }
        // And better than nothing in particular. Thirty prompts and no way to say "none
        // of these" means the best of thirty always wins, however badly — which is how a
        // photograph with no snow in it came to be the answer to "which one has snow".
        guard best.1 - nothingInParticular(embedding) >= Self.nullMargin else { return nil }
        return (best.0, best.1)
    }

    /// How much this photograph looks like "a photograph" — the null class.
    ///
    /// Measured: where the thing really is in the picture, the winning concept beats
    /// this by 0.008 or more nine times in ten; where it is not, every portrait tested
    /// lost to it by at least 0.035.
    private func nothingInParticular(_ embedding: [Float]) -> Double {
        let nulls = scenes.values.filter { $0.id.hasPrefix("null-") }
        guard !nulls.isEmpty else { return -.infinity }
        return nulls.map { Double(Self.dot(embedding, $0.vector)) }.max() ?? -.infinity
    }

    // The numbers below are measured, not guessed, and they belong to this model.
    //
    // SigLIP scores on a different scale from CLIP — a good match here is about 0.08
    // where CLIP's was about 0.28 — so every threshold was re-read from the
    // distribution over a labelled set of our own pack photographs
    // (`Tools/Themes/README.md`). Swapping the model without re-measuring these would
    // leave every gate either wide open or shut.

    /// Below this the photograph is not really of anything the game asks about.
    private static let conceptFloor = 0.040
    /// And this far clear of the next thing, so a cat is never nearly a dog.
    private static let conceptMargin = 0.005
    /// And this far clear of "a photograph", so a thing that is not there is not named.
    private static let nullMargin = 0.004

    /// Whether the photograph is of somewhere rather than of somebody.
    ///
    /// Compared rather than thresholded: CLIP's absolute similarities sit in a narrow
    /// band that shifts with the prompt, so "is this more like a street than like a
    /// face" is answerable where "is this above 0.27" is not.
    func showsAPlace(_ embedding: [Float]) -> Bool? {
        guard !embedding.isEmpty,
              let outdoors = scenes["place-outdoor"], let indoors = scenes["place-indoor"],
              let closeUp = scenes["people-closeup"], let group = scenes["people-group"]
        else { return nil }
        // Outdoors, and not merely more room than face.
        //
        // A photograph taken inside a house says nothing about where the house is. The
        // only reason anybody could place "me holding a baby in my living room" in North
        // Carolina is that they live there — which is not a question, it is a fact they
        // already had. Streets, hills, buildings from outside and weather are what carry
        // a place; four walls do not, however well lit.
        let outside = Self.dot(embedding, outdoors.vector)
        let anythingElse = max(Self.dot(embedding, indoors.vector),
                               Self.dot(embedding, closeUp.vector),
                               Self.dot(embedding, group.vector))
        // Measured: over forty landmark photographs the smallest margin was +0.017,
        // and over forty portraits the largest was -0.015. Anything in between is a
        // photograph nobody could place.
        return outside > anythingElse + 0.012
    }

    /// Whether this photograph was taken to remember something rather than to keep.
    ///
    /// The scratch on the floor, the parking space, the serial number on the back of the
    /// boiler. They are photographs of nothing anybody wants to be asked about, and no
    /// metadata marks them: only what is in the frame says so. Compared against the
    /// occasions rather than thresholded, so a garden path or a beach close-up — which
    /// are also flat expanses of texture — stay on the right side of it.
    func looksLikeANote(_ embedding: [Float]) -> Bool? {
        guard !embedding.isEmpty, !themes.isEmpty else { return nil }
        let notes = scenes.values.filter { $0.id.hasPrefix("note-") }
        guard !notes.isEmpty else { return nil }
        let asNote = notes.map { Self.dot(embedding, $0.vector) }.max() ?? -1
        let asOccasion = themes.map { Self.dot(embedding, $0.vector) }.max() ?? -1
        // Compared against the occasions only, not against "the inside of a building".
        // A photograph of a scratched floorboard *is* the inside of a building, and
        // counting that as a point in its favour is why the floor kept coming back.
        // The margin keeps a merely ambiguous photograph — a close-up of a flowerbed —
        // out of the bin.
        return asNote > asOccasion + 0.004
    }

    /// CLIP similarities between an image and a sentence sit in a narrow band; this is
    /// the point above which the match says something rather than nothing. Tuned to be
    /// forgiving — a theme that is wrong is only a title, while a theme that is missing
    /// costs a round its shape.
    private static let threshold = 0.035

    /// How far ahead of the next theme the winner has to be.
    private static let margin = 0.004

    /// 512 floats as half precision: a kilobyte per photograph rather than two, and
    /// nothing is lost that a cosine similarity would notice.
    static func pack(_ values: [Float]) -> Data {
        var halves = values.map { Float16($0) }
        return halves.withUnsafeMutableBufferPointer { Data(buffer: $0) }
    }

    static func unpack(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float16>.size == 0 else { return nil }
        let halves = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float16.self))
        }
        return halves.map { Float($0) }
    }

    // MARK: - Plumbing

    private nonisolated static func loadThemes(_ resource: String) -> [PhotoTheme] {
        struct Entry: Decodable {
            let title: String
            let question: String?
            let identify: String?
            let vector: [Float]
        }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return []
        }
        return decoded
            .map { PhotoTheme(id: $0.key, title: $0.value.title,
                              question: $0.value.question ?? "",
                              identify: $0.value.identify ?? "",
                              vector: normalised($0.value.vector)) }
            .sorted { $0.id < $1.id }
    }

    private nonisolated static func normalised(_ values: [Float]) -> [Float] {
        let length = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard length > 0 else { return values }
        return values.map { $0 / length }
    }

    private nonisolated static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return -1 }
        var total: Float = 0
        for index in a.indices { total += a[index] * b[index] }
        return total
    }

    /// The encoder wants 224×224 RGB. Anything else is a crash rather than a bad answer,
    /// so the resize happens here rather than being assumed.
    private nonisolated static func pixels(from image: CGImage) -> CVPixelBuffer? {
        let side = 224
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32ARGB,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }
}
