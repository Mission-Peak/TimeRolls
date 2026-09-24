//
//  Tools/IntakeProbe — would the on-device model catch a note-to-self?
//
//  `DescribedPhotos` reads a description and decides whether a photograph is a memory.
//  The rules are tested; what was never tested is whether the model produces the sort of
//  description they read. This puts a real photograph through the real prompt.
//
//  Usage: ./run.sh <image> [<image> …]
//

import Foundation
import CoreGraphics
import ImageIO
import FoundationModels

@Generable
struct Description {
    @Guide(description: "One plain sentence saying what this photograph shows.")
    var sentence: String
}

func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

@main
struct Probe {
    static func main() async {
        switch SystemLanguageModel.default.availability {
        case .available: break
        default: print("model unavailable"); return
        }
        for path in CommandLine.arguments.dropFirst() {
            guard let picture = load(path) else { print("\(path): unreadable"); continue }
            let session = LanguageModelSession(instructions:
                "You describe photographs plainly, in one sentence, for a photo game that "
              + "shows people their own pictures. Say what the photograph is of.")
            var sentence = "—"
            let started = Date()
            do {
                let reply = try await session.respond(generating: Description.self) {
                    "Describe this photograph."
                    Attachment(picture).label("the photograph")
                }
                sentence = reply.content.sentence
            } catch {
                sentence = "error: \(error)"
            }
            let verdict = DescribedPhotosCopy.read(sentence)
            print("\((path as NSString).lastPathComponent)")
            print("   said: \u{201C}\(sentence)\u{201D}")
            print("   verdict: \(verdict)"
                + String(format: "   (%.1fs)", Date().timeIntervalSince(started)))
        }
    }
}

/// The app's rules, copied so this tool needs nothing from the app target.
enum DescribedPhotosCopy {
    static func read(_ description: String) -> String {
        let text = description.lowercased()
        for sign in ["a man", "a woman", "a person", "a child", "a boy", "a girl",
                     "a baby", "people", "a group of", "a couple", "a family",
                     "smiling", "posing", "holding", "a dog", "a cat", "a bird",
                     "a horse", "a puppy", "a kitten", "an animal"] where text.contains(sign) {
            return "a memory (somebody or something alive in it)"
        }
        let notMemories = [("screenshot", "a screenshot"), ("a receipt", "a receipt"),
            ("an invoice", "a document"), ("a document", "a document"),
            ("a page of text", "a page of text"), ("a handwritten note", "a note"),
            ("a price tag", "a label"), ("a barcode", "a label"),
            ("close-up of a floor", "a surface"), ("a plain wall", "a surface"),
            ("a scratch", "damage"), ("a menu", "a reminder")]
        for (phrase, because) in notMemories where text.contains(phrase) {
            return "NOT a memory — \(because)"
        }
        return "a memory"
    }
}
