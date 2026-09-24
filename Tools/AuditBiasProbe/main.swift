//
//  Tools/AuditBiasProbe — does the round audit throw away the rounds it least understands?
//
//  The audit drops a round when the model's answer isn't ours. The justification was that
//  a round the model can't answer is one the player can't answer either. Pack vetting put
//  that in doubt: the model named only 195 of 388 landmarks, and the ones it missed were
//  not bad photographs — Victoria Falls, Ben Nevis, Multnomah Falls, described correctly
//  and generically. A player who has been to Fort William knows Ben Nevis on sight.
//
//  If agreement is much worse on landmarks the model cannot name, then the audit is not
//  removing unfair rounds. It is removing rounds about anywhere less than world-famous,
//  and the game quietly shrinks to the twenty places everybody already knows.
//
//  So: build rounds from landmarks it named, and rounds from landmarks it didn't, and
//  compare how often it agrees with the answer we know to be right.
//

import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import FoundationModels

@Generable
struct Judgement {
    @Guide(description: "The one photograph that answers the question.")
    var answer: ImageReference
    @Guide(description: "True if two or more of the photographs answer the question equally well, or if none of them clearly does.")
    var arguable: Bool
}

struct Verdict: Codable { let id: String; let title: String; let standing: String }
struct Item: Codable { let id: String; let title: String?; let remoteURL: String? }
struct Pack: Codable { let items: [Item] }

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                           : FileManager.default.currentDirectoryPath

let instructions = """
You are checking a picture puzzle before it is shown to an older player, some of \
whom have memory difficulties. You will be given a question and several labelled \
photographs.

- Choose the one photograph that answers the question.
- Judge only what you can see in the photographs themselves.
- Say it is arguable if two or more of them answer the question equally well, or if \
none of them clearly does. A puzzle with no findable answer is worse than no puzzle.
"""

func cachePath(for url: String) -> String {
    let digest = SHA256.hash(data: Data(url.utf8))
    let name = digest.map { String(format: "%02x", $0) }.joined().prefix(20)
    return "\(root)/build/vet-cache/\(name).jpg"
}

func load(_ item: Item) -> CGImage? {
    guard let remote = item.remoteURL else { return nil }
    let path = cachePath(for: remote)
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

guard let packData = FileManager.default.contents(
        atPath: "\(root)/TimeRolls/Packs/travel-landmarks/travel-landmarks.pack.json"),
      let pack = try? JSONDecoder().decode(Pack.self, from: packData),
      let vetData = FileManager.default.contents(atPath: "\(root)/build/vet-travel-landmarks.json"),
      let verdicts = try? JSONDecoder().decode([Verdict].self, from: vetData) else {
    print("need the pack and its vetting report"); exit(1)
}

let standing = Dictionary(verdicts.map { ($0.id, $0.standing) }, uniquingKeysWith: { a, _ in a })
let byID = Dictionary(pack.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
let named = pack.items.filter { standing[$0.id] == "named" && load($0) != nil }
let unnamed = pack.items.filter { standing[$0.id] == "wrong" && load($0) != nil }

print("\(named.count) landmarks the model named, \(unnamed.count) it could not\n")

switch SystemLanguageModel.default.availability {
case .available: break
default: print("model unavailable"); exit(1)
}

/// Build a round with `answer` and three others, and ask the model to play it.
func agrees(answer: Item, others: [Item], slot: Int) async -> Bool? {
    var photographs = others
    photographs.insert(answer, at: slot)
    var attachments: [Attachment<ImageAttachmentContent>] = []
    for (position, item) in photographs.enumerated() {
        guard let picture = load(item) else { return nil }
        attachments.append(Attachment(picture).label("photo \(position + 1)"))
    }
    let session = LanguageModelSession(instructions: instructions)
    do {
        let reply = try await session.respond(generating: Judgement.self) {
            "Which photo shows \(answer.title ?? "it")?"
            attachments
        }
        if reply.content.arguable { return false }
        let raw = reply.content.answer.attachmentLabel
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\"'[]().")).lowercased()
        let known = (1...photographs.count).map { "photo \($0)" }
        guard known.contains(raw) else { return nil }   // unreadable keeps the round
        return raw == "photo \(slot + 1)"
    } catch { return nil }
}

func measure(_ group: [Item], _ label: String, rounds: Int) async {
    var agreed = 0, asked = 0
    for index in 0..<rounds {
        let answer = group[index % group.count]
        // Three distractors from the same group, so only the naming changes between runs.
        var others: [Item] = []
        var step = 1
        while others.count < 3 && step < group.count {
            let candidate = group[(index + step) % group.count]
            if candidate.id != answer.id { others.append(candidate) }
            step += 1
        }
        guard others.count == 3 else { continue }
        guard let verdict = await agrees(answer: answer, others: others, slot: index % 4)
        else { continue }
        asked += 1
        if verdict { agreed += 1 }
    }
    let share = asked == 0 ? 0 : Int((Double(agreed) / Double(asked) * 100).rounded())
    print("\(label): agreed on \(agreed) of \(asked) rounds (\(share)%)")
}

await measure(named, "landmarks the model can name   ", rounds: 40)
await measure(unnamed, "landmarks the model cannot name", rounds: 40)
print("""

Every round above has a correct, unarguable answer — the pack knows what each photograph
is. Disagreement here is the audit throwing away a good round.
""")
