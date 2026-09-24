//
//  Tools/PhotoSieve — put a candidate photograph through the app's own curation.
//
//  A pack builder can tell whether a photograph exists and whether its licence allows it,
//  and nothing else. Everything the app checks — is this a photograph of words, is it a
//  utility image, is it worth looking at, how much of the frame is somebody's face — used
//  to run only later, on the phone, against the player's own pictures. So a pack could
//  ship photographs the app would quietly refuse at the point of use, which is the worst
//  place to find out.
//
//  This runs the real Vision requests the app runs, and the app's own `TextDensity` is
//  compiled in rather than copied, so the receipt rule here is the receipt rule that ships.
//
//  Reads one image path per line on stdin, writes one JSON object per line to stdout.
//
//  Usage: ./run.sh [--aesthetics-floor 0.25] < paths.txt
//

import Foundation
import CoreGraphics
import ImageIO
import Vision

struct Verdict: Encodable {
    var path: String
    var passes: Bool
    var reason: String
    /// The largest face as a fraction of the frame. `GamePhoto` calls anything over 0.22 a
    /// portrait and anything over 0.08 a photograph whose surroundings are hidden. Reported
    /// rather than judged here: a wedding wants faces and a landscape does not, so the
    /// caller decides with the subject in hand.
    var faceArea: Double
    var hasFace: Bool
    var aesthetics: Double
    var isUtility: Bool
    var textLines: Int
    var textCovered: Double
    var textEnclosed: Double
}

func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

@main
struct Sieve {

    static func main() async {
        var floor = 0.0
        var arguments = Array(CommandLine.arguments.dropFirst())
        while let index = arguments.firstIndex(of: "--aesthetics-floor") {
            if index + 1 < arguments.count { floor = Double(arguments[index + 1]) ?? 0 }
            arguments.removeSubrange(index...min(index + 1, arguments.count - 1))
        }

        let faces = DetectFaceRectanglesRequest()
        var text = RecognizeTextRequest()
        // Fast, not accurate: the question is how much of the frame is text, never what it
        // says. Nothing read here is kept.
        text.recognitionLevel = .fast
        let aesthetics = CalculateImageAestheticsScoresRequest()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        while let line = readLine(strippingNewline: true) {
            let path = line.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            var verdict = Verdict(path: path, passes: false, reason: "unreadable",
                                  faceArea: 0, hasFace: false, aesthetics: 0,
                                  isUtility: false, textLines: 0, textCovered: 0,
                                  textEnclosed: 0)
            if let picture = load(path) {
                let seen = (try? await faces.perform(on: picture)) ?? []
                verdict.hasFace = !seen.isEmpty
                verdict.faceArea = seen
                    .map { Double($0.boundingBox.cgRect.width * $0.boundingBox.cgRect.height) }
                    .max() ?? 0

                let boxes = ((try? await text.perform(on: picture)) ?? [])
                    .map(\.boundingBox.cgRect)
                let reading = TextDensity.reading(from: boxes)
                verdict.textLines = reading.lines
                verdict.textCovered = reading.covered
                verdict.textEnclosed = reading.enclosed

                if let scores = try? await aesthetics.perform(on: picture) {
                    verdict.aesthetics = Double(scores.overallScore)
                    verdict.isUtility = scores.isUtility
                }

                if TextDensity.looksLikeADocument(reading, hasFace: verdict.hasFace) {
                    verdict.reason = "a photograph of words"
                } else if verdict.isUtility {
                    // Apple's own call that this is a screenshot, a receipt, a document —
                    // something kept for what it says rather than looked at.
                    verdict.reason = "a utility image, not a photograph"
                } else if verdict.aesthetics < floor {
                    verdict.reason = String(format: "aesthetics %.3f below %.3f",
                                            verdict.aesthetics, floor)
                } else {
                    verdict.passes = true
                    verdict.reason = "ok"
                }
            }
            if let data = try? encoder.encode(verdict),
               let json = String(data: data, encoding: .utf8) {
                print(json)
                fflush(stdout)
            }
        }
    }
}
