//
//  Tools/PackVet — does each pack photograph show what the pack says it shows?
//
//  A separate curation routine, run here rather than on anybody's device, over the public
//  photographs before they ship. The app's own curation judges *rounds*; this judges the
//  material, once, so a photograph that was never going to make a fair round is gone
//  before it can be chosen for one.
//
//  It asks Apple's on-device model to describe each photograph and then reads the answer,
//  rather than asking whether the photograph shows X. That is not a stylistic choice —
//  Tools/DescribeProbe measured both, and the direct question scores 17% against the
//  description's 67%, answering "no" for a photograph of Big Ben whose own description
//  named Big Ben. A model will describe what it sees more honestly than it will agree
//  with you about it.
//
//  Nothing is deleted. 67% is a good way to find suspects and a terrible way to convict
//  them: a third of what it flags will be the model's mistake, not the pack's, and the
//  only way to tell is to look. So this writes a list for a person to go through.
//
//  Usage: ./run.sh <pack-id> [limit]
//

import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import FoundationModels

@Generable
struct Description {
    @Guide(description: "One plain sentence saying what this photograph shows, naming any landmark, city or country you recognise.")
    var sentence: String
}

struct Item: Codable {
    let id: String
    let title: String?
    let remoteURL: String?
    let place: String?
}

struct Pack: Codable { let items: [Item] }

struct Verdict: Codable {
    enum Standing: String, Codable {
        /// The description names the thing. Nothing to do.
        case named
        /// It doesn't name it, but it puts the photograph in the right place — "a geyser
        /// in Yellowstone" for Old Faithful. Almost always a model that saw the picture
        /// perfectly well and wouldn't commit to the name, so it goes in a second, much
        /// quieter list rather than being dressed up as a problem.
        case unnamedButPlausible
        /// Neither the thing nor the place. This is the list worth a person's time.
        case wrong
    }
    let id: String
    let title: String
    let description: String
    let standing: Standing
    let looked: [String]
}

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    print("usage: packvet <repo-root> <pack-id> [limit]"); exit(1)
}
let root = arguments[1]
let packID = arguments[2]
let limit = arguments.count > 3 ? Int(arguments[3]) ?? .max : .max

let packPath = "\(root)/TimeRolls/Packs/\(packID)/\(packID).pack.json"
guard let data = FileManager.default.contents(atPath: packPath),
      let pack = try? JSONDecoder().decode(Pack.self, from: data) else {
    print("could not read \(packPath)"); exit(1)
}

// Images are cached by a hash of their URL, never by their position in the pack. A cache
// keyed by index once rejected 273 perfectly good animals, because the pack grew and every
// photograph was then judged against somebody else's answer.
let cacheDirectory = "\(root)/build/vet-cache"
try? FileManager.default.createDirectory(atPath: cacheDirectory,
                                         withIntermediateDirectories: true)

func cachePath(for url: String) -> String {
    let digest = SHA256.hash(data: Data(url.utf8))
    let name = digest.map { String(format: "%02x", $0) }.joined().prefix(20)
    return "\(cacheDirectory)/\(name).jpg"
}

func image(for item: Item) async -> CGImage? {
    guard let remote = item.remoteURL else { return nil }
    let path = cachePath(for: remote)
    if !FileManager.default.fileExists(atPath: path) {
        guard let url = URL(string: remote) else { return nil }
        var request = URLRequest(url: url)
        // Wikimedia asks that tools identify themselves.
        request.setValue("TimeRolls-PackVet/1.0 (pack vetting; contact via Attimis)",
                         forHTTPHeaderField: "User-Agent")
        guard let (downloaded, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        try? downloaded.write(to: URL(fileURLWithPath: path))
    }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// The words that would show the description is about the same thing as the title.
///
/// The subject decides it, not the place. An early version accepted "Big Ben" on the word
/// *London* alone — because "Big" and "Ben" were too short to survive the filter — which
/// would have passed any photograph of any London street. A pack photograph's whole job
/// is to be the thing it is named after, so the name is what has to appear; the town it
/// stands in is supporting evidence at best.
let ignored: Set<String> = ["the", "of", "and", "at", "in", "on", "a", "an", "from",
                            "great", "national", "old", "new", "saint", "mount", "city",
                            "big", "little", "north", "south", "east", "west"]

/// Accents are the enemy of a naive match: "Chichén Itzá" failed against a description
/// that said "Chichen Itza", and the photograph was perfectly good.
func folded(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
}

func words(in text: String?, shorterThan minimum: Int = 3) -> [String] {
    folded(text ?? "")
        .split(whereSeparator: { !$0.isLetter })
        .map(String.init)
        .filter { $0.count >= minimum && !ignored.contains($0) }
}

/// The name it has to live up to, falling back to where it was taken when it has no name
/// of its own — a pack of street scenes is judged on its city, having nothing else.
func keyWords(for item: Item) -> [String] {
    let named = words(in: item.title)
    return named.isEmpty ? words(in: item.place, shorterThan: 4) : named
}

switch SystemLanguageModel.default.availability {
case .available: break
default: print("model unavailable — needs macOS 27 and Apple Intelligence on"); exit(1)
}

var verdicts: [Verdict] = []
var missing = 0

for item in pack.items.prefix(limit) {
    let expected = keyWords(for: item)
    guard !expected.isEmpty else { continue }
    guard let picture = await image(for: item) else {
        missing += 1
        continue
    }
    var sentence = ""
    do {
        let session = LanguageModelSession(instructions:
            "You describe photographs plainly and briefly for a picture archive. "
          + "Name any landmark, city or country you recognise.")
        let reply = try await session.respond(generating: Description.self) {
            "Describe this photograph."
            Attachment(picture).label("the photograph")
        }
        sentence = reply.content.sentence
    } catch {
        // A model that would not answer is not evidence against the photograph.
        continue
    }
    let lowered = folded(sentence)
    let named = expected.contains { lowered.contains($0) }
    let placed = words(in: item.place, shorterThan: 4).contains { lowered.contains($0) }
    let standing: Verdict.Standing = named ? .named : (placed ? .unnamedButPlausible : .wrong)
    verdicts.append(Verdict(id: item.id, title: item.title ?? item.id,
                            description: sentence, standing: standing, looked: expected))
    if standing == .wrong { print("✗ \(item.title ?? item.id)\n    “\(sentence)”") }
}

let flagged = verdicts.filter { $0.standing == .wrong }
let quiet = verdicts.filter { $0.standing == .unnamedButPlausible }
let reportPath = "\(root)/build/vet-\(packID).json"
if let encoded = try? JSONEncoder().encode(verdicts) {
    try? encoded.write(to: URL(fileURLWithPath: reportPath))
}

print("""

\(packID): \(verdicts.count) photographs described, \(missing) could not be fetched
\(verdicts.count - flagged.count - quiet.count) named the thing they are called after
\(quiet.count) described the right place without naming it — probably fine
\(flagged.count) matched neither the name nor the place — worth looking at
   \(reportPath)

Suspects, not convictions. The probe that sized this check got two in three right, so
some of the list above will be the model's mistake rather than the pack's. Look before
removing anything.
""")
