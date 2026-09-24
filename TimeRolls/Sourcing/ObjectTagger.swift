//
//  ObjectTagger.swift
//  Time Rolls
//
//  On-device Vision classification for the Objects theme (spec §6.3).
//
//  This is the one place in the app that looks at what is *in* a photo. It runs
//  entirely on this device through Apple's built-in classifier — no network call, no
//  generative model, nothing uploaded. What is kept is a handful of category keys per
//  photo ("dog", "cake"); the image itself is never stored, copied or transmitted, and
//  the labels never leave the device or enter a telemetry payload.
//

import Foundation
import Photos
import UIKit
import Vision
import Observation

@Observable
@MainActor
final class ObjectTagger {

    /// Written on the classification task, off the main actor.
    nonisolated struct Tags: Codable, Hashable {
        /// Categories we're confident about — these can be the answer.
        var confident: Set<String> = []
        /// Categories the classifier saw even a hint of. Used only to rule a photo out
        /// as a distractor, so a level never has two defensible answers.
        var possible: Set<String> = []
        /// Whether a face was found. A yes/no, not a count, and no identity: nothing
        /// here can tell one person from another.
        var faces = false
        /// How much of the frame the largest face fills. A group at the Trevi Fountain
        /// scores low; a selfie scores high.
        var faceArea = 0.0
        /// Whether the picture is mostly words: a receipt, a message, a meme, a poster.
        /// PhotoKit's own screenshot flag catches the formal ones; this catches the
        /// photographed and the saved-from-elsewhere.
        var isDocument = false
        /// A compact description of what the photograph looks like, for comparing one
        /// against another. Not an image and not reversible into one — a few hundred
        /// numbers describing texture and shape.
        var featurePrint: Data?
        /// Apple's own rating of the photograph, roughly -1 … 1.
        var aesthetics = 0.0
        /// Apple's own verdict on whether this is a photograph at all, or a receipt, a
        /// screenshot, a document — something kept for its information.
        var isUtility = false
        /// How good the best face in it is: in focus, lit, looking at the camera.
        /// Zero when there is no face.
        var faceQuality = 0.0
        /// Where the eye goes in this photograph.
        var subjectArea: SubjectArea?
        /// What the photograph is of, in the sense a person means it: a birthday, a
        /// beach, the garden. Nil when nothing matched well enough to say.
        var themeID: String?
        var themeTitle: String?
        var themeQuestion: String?
        /// What to ask when this is the only photograph of its kind in the round.
        var themeIdentify: String?
        /// Every theme this photograph is arguably of, generously read, so a round asking
        /// which one shows a wedding never stands a second wedding beside the answer.
        var plausibleThemes: Set<String> = []
        /// What this photograph is most a picture of, among the things the game asks
        /// about, and how strong that reading is.
        var conceptID: String?
        var conceptScore = 0.0
        /// Taken to remember something rather than to keep: the scratch on the floor,
        /// the parking space, the label on the back of a tin.
        var isNote = false
        /// The photograph as 512 numbers, stored so curation can check a classifier's
        /// claim against a second opinion without re-reading the photograph. Half
        /// precision, about a kilobyte.
        var themeEmbedding: Data?
        var catalogVersion: Int = ObjectCatalog.version
    }

    private(set) var tags: [String: Tags] = [:]
    private(set) var isWorking = false
    /// Photos whose image could not be read at all (corrupt, or not on this device).
    private(set) var unreadableCount = 0
    /// Set when the on-device classifier can't be loaded — notably in the iOS Simulator,
    /// whose Core ML runtime cannot load the image classifier. Objects then plays from
    /// the photo packs alone rather than disappearing.
    private(set) var unavailableReason: String?

    private var worker: Task<Void, Never>?
    private let storeURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("object-tags.json")
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([String: Tags].self, from: data) {
            // Drop anything tagged against an older allow-list.
            tags = decoded.filter { $0.value.catalogVersion == ObjectCatalog.version }
        }
    }

    var taggedCount: Int { tags.count }

    /// Decoded feature prints, kept because decoding one per comparison would make
    /// deduplication quadratic in JSON parsing rather than in float maths.
    private var prints: [String: FeaturePrintObservation] = [:]
    private var embeddings: [String: [Float]] = [:]

    /// How much a photograph looks like the thing about to be asked about — CLIP's
    /// opinion, independent of the classifier that produced the tag.
    func conceptScore(_ id: String, concept: String) -> Double? {
        guard let embedding = embedding(for: id) else { return nil }
        return PhotoThemeIndex.shared.score(embedding, concept: concept)
    }

    /// What the themes model thinks this photograph is most a picture of, among the
    /// things the game can ask about.
    func bestConcept(_ id: String) -> String? {
        guard let embedding = embedding(for: id) else { return nil }
        return PhotoThemeIndex.shared.bestConcept(embedding)
    }

    /// Whether a photograph is of somewhere rather than of somebody.
    func showsAPlace(_ id: String) -> Bool? {
        guard let embedding = embedding(for: id) else { return nil }
        return PhotoThemeIndex.shared.showsAPlace(embedding)
    }

    private func embedding(for id: String) -> [Float]? {
        if let cached = embeddings[id] { return cached }
        guard let data = tags[id]?.themeEmbedding,
              let unpacked = PhotoThemeIndex.unpack(data) else { return nil }
        embeddings[id] = unpacked
        return unpacked
    }

    /// How different two photographs look: 0 is the same picture, and larger numbers
    /// mean less alike. Nil when either photograph has not been looked at yet.
    func visualDistance(_ first: String, _ second: String) -> Double? {
        guard let a = featurePrint(for: first),
              let b = featurePrint(for: second) else { return nil }
        return try? a.distance(to: b)
    }

    private func featurePrint(for id: String) -> FeaturePrintObservation? {
        if let cached = prints[id] { return cached }
        guard let data = tags[id]?.featurePrint,
              let decoded = try? JSONDecoder().decode(FeaturePrintObservation.self,
                                                      from: data) else { return nil }
        prints[id] = decoded
        return decoded
    }

    /// Photos are classified once and remembered, so this is only slow the first time.
    func annotate(_ photos: [GamePhoto]) -> [GamePhoto] {
        photos.map { photo in
            var copy = photo
            if let found = tags[photo.id] {
                copy.objectTags = found.confident
                copy.possibleObjectTags = found.possible
                copy.showsPeople = found.faces
                copy.faceProminence = found.faceArea
                copy.wasExamined = true
                // Apple's verdict first, then the text-area heuristic, then the
                // themes model on whether this was a photograph of anything at all.
                copy.looksLikeDocument = found.isUtility || found.isDocument || found.isNote
                copy.aesthetics = found.aesthetics
                copy.shotQuality = max(found.faceQuality, 0)
                copy.subjectArea = found.subjectArea
                copy.themeID = found.themeID
                copy.themeTitle = found.themeTitle
                copy.themeIdentify = found.themeIdentify
                copy.plausibleThemeIDs = found.plausibleThemes
                copy.themeQuestion = found.themeQuestion
                copy.conceptID = found.conceptID
                copy.conceptScore = found.conceptScore
            }
            return copy
        }
    }

    /// A photo can be classified if we can get pixels for it: the player's own photos,
    /// and bundled pack photographs. Procedural pack art keeps its hand-written subjects.
    private func subject(for photo: GamePhoto) -> Subject? {
        switch photo.origin {
        case let .personal(localIdentifier):
            return .asset(localIdentifier)
        case let .pack(packID, itemID):
            guard let item = PublicPackLibrary.item(packID: packID, itemID: itemID),
                  let url = PublicPackLibrary.imageURL(for: item) else {
                return nil
            }
            return .bundledImage(url.path)
        }
    }

    func pendingCount(in photos: [GamePhoto]) -> Int {
        photos.filter { tags[$0.id] == nil && subject(for: $0) != nil }.count
    }

    /// Works through the untagged photos a chunk at a time, calling back after each so
    /// the Objects theme becomes available while the rest is still being looked at.
    /// How many photographs this pass set out to look at, and how many it has done.
    ///
    /// A large library takes real time on an older device, and a game drawing on a
    /// tenth of somebody's photographs looks like a game that has very few photographs
    /// — which is a worse first impression than being told to wait a moment (spec §8).
    private(set) var stillToExamine = 0
    private(set) var examinedThisPass = 0

    /// 0 to 1 while a pass is running, nil when there is nothing to wait for.
    var progress: Double? {
        guard isWorking, stillToExamine > 0 else { return nil }
        return min(Double(examinedThisPass) / Double(stillToExamine), 1)
    }

    func startTagging(_ photos: [GamePhoto],
                      chunkSize: Int = 12,
                      onChunk: @escaping @MainActor () -> Void) {
        let pending: [(String, Subject)] = photos.compactMap { photo in
            guard tags[photo.id] == nil, let subject = subject(for: photo) else { return nil }
            return (photo.id, subject)
        }
        guard !pending.isEmpty else {
            stillToExamine = 0
            examinedThisPass = 0
            return
        }

        worker?.cancel()
        unavailableReason = nil
        isWorking = true
        // How much of the library has not been looked at yet, so the app can say so
        // rather than quietly playing a worse game while it catches up.
        stillToExamine = pending.count
        examinedThisPass = 0
        worker = Task { [weak self] in
            for chunk in stride(from: 0, to: pending.count, by: chunkSize) {
                if Task.isCancelled { break }
                let slice = Array(pending[chunk..<min(chunk + chunkSize, pending.count)])
                let results = await Self.classify(slice)

                guard let self, !Task.isCancelled else { break }
                var classifierGone = false
                for (id, outcome) in results {
                    switch outcome {
                    case let .tagged(result):
                        // An empty result is a real answer: nothing recognised here.
                        tags[id] = result
                    case .unreadable:
                        // Per-photo problem. Remember it so we don't retry forever.
                        tags[id] = Tags()
                        unreadableCount += 1
                    case let .classifierUnavailable(reason):
                        // Systemic. Cache nothing, so a later launch can try again.
                        unavailableReason = reason
                        classifierGone = true
                    }
                }
                examinedThisPass += slice.count
                persist()
                onChunk()
                if classifierGone { break }
            }
            self?.isWorking = false
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        isWorking = false
    }

    /// How each allow-listed category is doing on this library — the tool for the
    /// "which categories are reliable enough" decision in spec §12.
    func coverage(in photos: [GamePhoto]) -> [(category: ObjectCategory, matches: Int)] {
        var counts: [String: Int] = [:]
        for photo in photos {
            for tag in photo.objectTags {
                counts[tag, default: 0] += 1
            }
        }
        return ObjectCatalog.categories
            .map { ($0, counts[$0.id] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Classification

    /// One photo's outcome. Kept separate so a classifier that can't load is never
    /// mistaken for a photo with nothing in it.
    nonisolated enum Outcome {
        case tagged(Tags)
        /// No image could be read for this particular photo.
        case unreadable
        /// The classifier is not available at all on this device.
        case classifierUnavailable(String)
    }

    /// A photograph of words rather than of anything.
    ///
    /// Counted by area rather than by how many words were found: a birthday cake with
    /// "Happy Birthday" piped on it has text in it and is exactly the kind of picture
    /// this game is for, while a receipt is text wall to wall. The threshold is
    /// deliberately high, because throwing away a real photograph is the worse mistake.
    /// Whether the photograph is words. The judgement lives in `TextDensity`, where the
    /// harness can read it; this only hands over the boxes.
    private nonisolated static func isMostlyText(_ observations: [RecognizedTextObservation],
                                                 hasFace: Bool) -> Bool {
        TextDensity.looksLikeADocument(
            TextDensity.reading(from: observations.map(\.boundingBox.cgRect)),
            hasFace: hasFace)
    }

    /// Where a photo's pixels come from.
    nonisolated enum Subject {
        case asset(String)
        case bundledImage(String)
    }

    private nonisolated static func classify(_ subjects: [(String, Subject)]) async -> [(String, Outcome)] {
        var output: [(String, Outcome)] = []
        let request = ClassifyImageRequest()
        // Rectangles only. Not landmarks, not identity — the question this answers is
        // "is this a photograph of people", nothing finer.
        let faces = DetectFaceRectanglesRequest()
        // Fast, not accurate: the question is how much of the frame is text, not what
        // the text says. Nothing read here is kept.
        var text = RecognizeTextRequest()
        text.recognitionLevel = .fast
        let print = GenerateImageFeaturePrintRequest()
        // Apple's own judgement of whether this is a photograph worth looking at, and
        // whether it is a photograph at all. Better than any heuristic here could be.
        let aesthetics = CalculateImageAestheticsScoresRequest()
        // Which of three near-identical shots to keep: the one where the eyes are open.
        let faceQuality = DetectFaceCaptureQualityRequest()
        // Where a person's eye goes in the picture, for when a crop has to choose.
        let saliency = GenerateAttentionBasedSaliencyImageRequest()

        for (id, subject) in subjects {
            if Task.isCancelled { return output }
            guard let image = thumbnail(for: subject) else {
                output.append((id, .unreadable))
                continue
            }
            do {
                let observations = try await request.perform(on: image)
                var found = tags(from: observations)
                // A failure here is not a reason to lose the categories: no face found
                // simply means the round can't rely on this one being a portrait.
                let seen = (try? await faces.perform(on: image)) ?? []
                found.faces = !seen.isEmpty
                found.faceArea = seen
                    .map { Double($0.boundingBox.cgRect.width * $0.boundingBox.cgRect.height) }
                    .max() ?? 0
                // Faces are read just above, so the text test can know whether there is
                // somebody in the picture.
                found.isDocument = Self.isMostlyText(
                    (try? await text.perform(on: image)) ?? [], hasFace: found.faces)
                if let observation = try? await print.perform(on: image) {
                    found.featurePrint = try? JSONEncoder().encode(observation)
                }
                if let scores = try? await aesthetics.perform(on: image) {
                    found.aesthetics = Double(scores.overallScore)
                    found.isUtility = scores.isUtility
                }
                found.faceQuality = ((try? await faceQuality.perform(on: image)) ?? [])
                    .compactMap { $0.captureQuality.map { Double($0.score) } }
                    .max() ?? 0
                // What the occasion is, from the bundled model. A theme is a title
                // and a question, never an answer: the round is still decided by dates.
                if let embedding = PhotoThemeIndex.shared.embedding(for: image) {
                    found.themeEmbedding = PhotoThemeIndex.pack(embedding)
                    // Two more things have to be true before a photograph is called a
                    // note: nobody is in it, and the classifier found nothing in it
                    // worth naming. A room with people in it, or with a dog or a cake,
                    // is somebody's evening rather than a record of the paintwork.
                    if let concept = PhotoThemeIndex.shared.strongestConcept(embedding) {
                        found.conceptID = concept.id
                        found.conceptScore = concept.score
                    }
                    found.isNote = (PhotoThemeIndex.shared.looksLikeANote(embedding) ?? false)
                        && !found.faces
                        && found.confident.isEmpty
                    if let match = PhotoThemeIndex.shared.theme(for: embedding) {
                        found.themeID = match.theme.id
                        found.themeTitle = match.theme.title
                        found.themeQuestion = match.theme.question
                        found.themeIdentify = match.theme.identify
                    }
                    // Read once here, where the embedding already is, rather than in the
                    // curator: the curators are compiled without the model so the harness
                    // can check them, and this has to be plain data by the time they see it.
                    found.plausibleThemes = PhotoThemeIndex.shared.plausibleThemes(for: embedding)
                }
                if let salient = try? await saliency.perform(on: image),
                   let best = salient.salientObjects.max(by: { $0.confidence < $1.confidence }) {
                    let box = best.boundingBox.cgRect
                    // Vision measures from the bottom-left; everything drawn measures
                    // from the top-left.
                    found.subjectArea = SubjectArea(x: Double(box.minX),
                                                    y: 1 - Double(box.maxY),
                                                    width: Double(box.width),
                                                    height: Double(box.height))
                }
                output.append((id, .tagged(found)))
            } catch {
                // The classifier itself is unavailable — one photo's worth of evidence is
                // enough to stop, because it will fail for every photo.
                output.append((id, .classifierUnavailable(error.localizedDescription)))
                return output
            }
        }
        return output
    }

    private nonisolated static func tags(from observations: [ClassificationObservation]) -> Tags {
        var result = Tags()
        for observation in observations {
            guard let categories = ObjectCatalog.byIdentifier[observation.identifier] else {
                continue
            }
            // Apple's own precision/recall filter first, then our per-category floor.
            let trustworthy = observation.hasMinimumRecall(0.4, forPrecision: 0.7)
            for category in categories {
                if observation.confidence >= ObjectCatalog.possibleConfidence {
                    result.possible.insert(category.id)
                }
                if trustworthy, observation.confidence >= category.confidence {
                    result.confident.insert(category.id)
                }
            }
        }
        // Anything confident is also possible.
        result.possible.formUnion(result.confident)
        return result
    }

    /// A small thumbnail is all the classifier needs, and it keeps this cheap.
    private nonisolated static func thumbnail(for subject: Subject) -> CGImage? {
        switch subject {
        case let .asset(localIdentifier):
            return assetThumbnail(localIdentifier)
        case let .bundledImage(path):
            // Pack photographs are already small and local.
            return UIImage(contentsOfFile: path)?.cgImage
        }
    }

    private nonisolated static func assetThumbnail(_ assetID: String) -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = true
        // The user's own iCloud library, same as the display path. Nothing is sent out.
        options.isNetworkAccessAllowed = true

        var image: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 320, height: 320),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            image = result?.cgImage
        }
        return image
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func reset() {
        stop()
        tags = [:]
        unreadableCount = 0
        unavailableReason = nil
        try? FileManager.default.removeItem(at: storeURL)
    }
}
