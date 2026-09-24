//
//  Tools/DescribeProbe — can the on-device model vet a photograph against its own caption?
//
//  Pack vetting needs one question answered: does this photograph actually show what the
//  pack says it shows? There are two ways to ask, and they are not equally good — an
//  earlier probe found that asking "is the Eiffel Tower in this photograph?" about a
//  single image came back "no" for a photograph of the Eiffel Tower, in under half a
//  second, which is the shape of a model answering the form of the question rather than
//  looking. So this measures both ways before anything is built on either.
//
//    A. yes/no      — "Is X visible in this photograph?"  → Bool
//    B. description — "Describe this photograph."         → does the text name X?
//
//  Ground truth is the pack's own titles, which name the landmark.
//

import Foundation
import CoreGraphics
import ImageIO
import FoundationModels

@Generable
struct Sighting {
    @Guide(description: "True only if the thing asked about is plainly visible in this photograph.")
    var present: Bool
}

@Generable
struct Description {
    @Guide(description: "One plain sentence saying what this photograph shows, naming any landmark or place you recognise.")
    var sentence: String
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                           : FileManager.default.currentDirectoryPath

func load(_ number: String) -> CGImage? {
    let path = "\(root)/build/remote/packs/travel-landmarks/travel-landmarks-\(number).jpg"
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// number → (the subject as a pack title names it, the words that would prove it)
let truth: [(String, String, [String])] = [
    ("001", "the Eiffel Tower", ["eiffel"]),
    ("003", "the Colosseum", ["colosseum", "coliseum"]),
    ("006", "Big Ben", ["big ben", "elizabeth tower", "westminster"]),
    ("012", "Nyhavn in Copenhagen", ["nyhavn", "copenhagen"]),
    ("016", "Hallgrímskirkja", ["hallgrím", "hallgrim", "reykjav"]),
    ("019", "the Statue of Liberty", ["liberty"]),
    ("020", "the Golden Gate Bridge", ["golden gate"]),
    ("027", "Christ the Redeemer", ["redeemer", "christ"]),
    ("036", "the Taj Mahal", ["taj mahal"]),
    ("038", "the Great Pyramid of Giza", ["pyramid", "giza"]),
    ("042", "the Sydney Opera House", ["opera house", "sydney"]),
    ("031", "Sensō-ji temple in Tokyo", ["sens", "tokyo", "asakusa", "temple"]),
]

switch SystemLanguageModel.default.availability {
case .available: break
default: print("model unavailable"); exit(1)
}

var yesRight = 0, describeRight = 0, total = 0
var yesSeconds = 0.0, describeSeconds = 0.0

for (number, subject, words) in truth {
    guard let image = load(number) else { print("missing \(number)"); continue }
    total += 1

    // A — the direct question.
    var saidYes: Bool?
    let startedA = Date()
    do {
        let session = LanguageModelSession(instructions:
            "You are looking at one photograph and answering one question about it. "
          + "Answer about this photograph only, from what is plainly visible in it.")
        let reply = try await session.respond(generating: Sighting.self) {
            "Is \(subject) visible in this photograph?"
            Attachment(image).label("the photograph")
        }
        saidYes = reply.content.present
    } catch { saidYes = nil }
    yesSeconds += Date().timeIntervalSince(startedA)
    if saidYes == true { yesRight += 1 }

    // B — let it talk, then read what it said.
    var sentence = ""
    let startedB = Date()
    do {
        let session = LanguageModelSession(instructions:
            "You describe photographs plainly and briefly for a picture archive. "
          + "Name any landmark, city or country you recognise.")
        let reply = try await session.respond(generating: Description.self) {
            "Describe this photograph."
            Attachment(image).label("the photograph")
        }
        sentence = reply.content.sentence
    } catch { sentence = "error: \(error)" }
    describeSeconds += Date().timeIntervalSince(startedB)
    let named = words.contains { sentence.lowercased().contains($0) }
    if named { describeRight += 1 }

    print("\(subject)")
    print("   A yes/no      \(saidYes == true ? "✅" : "❌") \(saidYes.map(String.init(describing:)) ?? "error")")
    print("   B description \(named ? "✅" : "❌") “\(sentence.prefix(110))”")
}

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "—" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
}
print("""

A  asking "is X in this photograph?"   \(yesRight)/\(total) (\(percent(yesRight, total))) \
avg \(String(format: "%.1fs", yesSeconds / Double(max(total, 1))))
B  asking it to describe, then reading \(describeRight)/\(total) (\(percent(describeRight, total))) \
avg \(String(format: "%.1fs", describeSeconds / Double(max(total, 1))))
""")
