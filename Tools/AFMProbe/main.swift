//
//  Tools/AFMProbe — how good is Apple's on-device model at judging a round?
//
//  RoundAudit.swift hands a finished round to the model and drops it when the model's
//  answer isn't ours. That is only worth shipping if two numbers are right, and they pull
//  in opposite directions:
//
//    • On a clean round — one plain answer, three plainly wrong — the model must agree
//      with us nearly always. Every disagreement here throws away a perfectly good round.
//    • On an arguable round — two photographs that both answer the question — it must
//      disagree often. Every agreement here ships the round we were trying to catch.
//
//  This measures both, on photographs whose subjects we know, on this Mac, so a verdict
//  doesn't need a device. It is deliberately repetitive: the model samples, and one run
//  of one round says nothing at all.
//
//  Usage: ./run.sh [repeats]
//

import Foundation
import CoreGraphics
import ImageIO
import FoundationModels

@Generable
struct Judgement {
    @Guide(description: "The one photograph that answers the question.")
    var answer: ImageReference
    @Guide(description: "True if two or more of the photographs answer the question equally well, or if none of them clearly does.")
    var arguable: Bool
}

let instructions = """
You are checking a picture puzzle before it is shown to an older player, some of \
whom have memory difficulties. You will be given a question and several labelled \
photographs.

- Choose the one photograph that answers the question.
- Judge only what you can see in the photographs themselves.
- Say it is arguable if two or more of them answer the question equally well, or if \
none of them clearly does. A puzzle with no findable answer is worse than no puzzle.
"""

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                           : FileManager.default.currentDirectoryPath
let repeats = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 3 : 3

func load(_ number: String) -> CGImage? {
    let path = "\(root)/build/remote/packs/travel-landmarks/travel-landmarks-\(number).jpg"
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// subject → the photographs of it, by number in the pack.
let subjects: [(name: String, shots: [String])] = [
    ("the Eiffel Tower", ["001", "002"]),
    ("the Colosseum", ["003", "004"]),
    ("Big Ben", ["006", "007"]),
    ("the Statue of Liberty", ["018", "019"]),
    ("the Golden Gate Bridge", ["020", "021"]),
    ("Christ the Redeemer", ["027", "028"]),
    ("the Taj Mahal", ["036", "037"]),
    ("the Great Pyramid of Giza", ["038", "039"]),
    ("the Sydney Opera House", ["042", "043"]),
    ("Hallgrímskirkja", ["016", "017"]),
]

/// One round put to the model. Returns the label it chose, or "arguable".
func ask(_ question: String, _ photographs: [String]) async -> (said: String, seconds: Double)? {
    var attachments: [Attachment<ImageAttachmentContent>] = []
    for (position, number) in photographs.enumerated() {
        guard let image = load(number) else { return nil }
        attachments.append(Attachment(image).label("photo \(position + 1)"))
    }
    let session = LanguageModelSession(instructions: instructions)
    let started = Date()
    do {
        let reply = try await session.respond(generating: Judgement.self) {
            question
            attachments
        }
        let seconds = Date().timeIntervalSince(started)
        if reply.content.arguable { return ("arguable", seconds) }
        // Same tidying the app does: only a label we handed it counts as an answer.
        let raw = reply.content.answer.attachmentLabel
        let tidied = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'[]().")).lowercased()
        let known = (1...photographs.count).map { "photo \($0)" }
        return (known.contains(tidied) ? tidied : "no answer (\(raw))", seconds)
    } catch {
        return ("error: \(error)", Date().timeIntervalSince(started))
    }
}

switch SystemLanguageModel.default.availability {
case .available: break
default: print("model unavailable"); exit(1)
}

// MARK: - Clean rounds: one answer, three plainly different landmarks.

var cleanAgreed = 0, cleanTotal = 0, cleanArguable = 0, cleanUnjudged = 0
var cleanBothDisagreed = 0, caughtTwice = 0
var slowest = 0.0
for (index, subject) in subjects.enumerated() {
    let answer = subject.shots[0]
    // Three distractors, each a different landmark, taken from further down the list.
    let others = (1...3).map { subjects[(index + $0) % subjects.count].shots[0] }
    for round in 0..<repeats {
        // Move the answer around so a model with a position habit is caught.
        let slot = round % 4
        var photographs = others
        photographs.insert(answer, at: slot)
        guard let result = await ask("Which photo shows \(subject.name)?", photographs),
              let second = await ask("Which photo shows \(subject.name)?", photographs)
        else { continue }
        cleanTotal += 1
        slowest = max(slowest, max(result.seconds, second.seconds))
        let wanted = "photo \(slot + 1)"
        if result.said != wanted && second.said != wanted { cleanBothDisagreed += 1 }
        if result.said == "photo \(slot + 1)" { cleanAgreed += 1 }
        else if result.said == "arguable" { cleanArguable += 1 }
        else if result.said.hasPrefix("no answer") { cleanUnjudged += 1 }
        else { print("  clean miss — \(subject.name): said \(result.said), answer was photo \(slot + 1)") }
    }
}

// MARK: - Arguable rounds: two photographs of the same landmark, both true.

var caught = 0, arguableTotal = 0
for (index, subject) in subjects.enumerated() where subject.shots.count > 1 {
    let answer = subject.shots[0]
    let twin = subject.shots[1]
    let others = (1...2).map { subjects[(index + $0) % subjects.count].shots[0] }
    for round in 0..<repeats {
        var photographs = others + [twin]
        photographs.insert(answer, at: round % 4)
        guard let result = await ask("Which photo shows \(subject.name)?", photographs),
              let second = await ask("Which photo shows \(subject.name)?", photographs)
        else { continue }
        arguableTotal += 1
        let wantedTwice = "photo \((round % 4) + 1)"
        if result.said != wantedTwice && second.said != wantedTwice
            && !result.said.hasPrefix("no answer") && !second.said.hasPrefix("no answer") {
            caughtTwice += 1
        }
        // The app drops the round unless the model names our photograph — so anything
        // else, including "arguable", is a catch.
        // A malformed answer keeps the round in the app, so it is not a catch here.
        if result.said != "photo \((round % 4) + 1)" && !result.said.hasPrefix("no answer") {
            caught += 1
        }
    }
}

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "—" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
}

print("""

clean rounds    \(cleanAgreed)/\(cleanTotal) agreed (\(percent(cleanAgreed, cleanTotal))) \
— every disagreement is a good round thrown away
                \(cleanArguable) called arguable, \(cleanUnjudged) unreadable (those keep the round)
                so \(percent(cleanTotal - cleanAgreed - cleanUnjudged, cleanTotal)) of good rounds would be dropped
arguable rounds \(caught)/\(arguableTotal) caught (\(percent(caught, arguableTotal))) \
— the rounds the audit exists to stop

asking twice and dropping only when both disagree:
clean rounds    \(percent(cleanBothDisagreed, cleanTotal)) of good rounds dropped
arguable rounds \(percent(caughtTwice, arguableTotal)) caught
slowest judgement \(String(format: "%.1fs", slowest)) against an 8s budget
""")
