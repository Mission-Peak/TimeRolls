//
//  Tools/CurationHarness/packs.swift — the real packs, checked before they ship.
//
//  Spec §3 asks that every new pack go through the harness rather than only the
//  round-building logic, so the guarantees cover hand-curated content too. Everything
//  else in this harness plays against synthetic libraries built to be awkward on purpose;
//  this plays against the photographs that will actually be on somebody's iPad.
//
//  It reads the manifests off disk rather than out of a bundle, because a command-line
//  harness has no bundle — and reading the shipped files is the point: these are the exact
//  bytes that go into the app.
//

import Foundation

struct PackOnDisk {
    let id: String
    let title: String
    let themes: [String]
    /// Whether an item's title names what the photograph shows, or is only the file's name.
    let titlesAreNames: Bool
    let namedSubjectPrompt: String?
    /// "birth", "created" or "event" when the years are facts about the subjects.
    let chronologyBasis: String?
    /// Quiz packs only: the fact questions the pack can ask.
    let questions: [QuizQuestion]
    let items: [[String: Any]]
}

func loadPacks(from root: String) -> [PackOnDisk] {
    let folder = "\(root)/TimeRolls/Packs"
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
        return []
    }
    return names.sorted().compactMap { name in
        let path = "\(folder)/\(name)/\(name).pack.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return nil }
        return PackOnDisk(id: json["id"] as? String ?? name,
                          title: json["title"] as? String ?? name,
                          themes: json["themes"] as? [String] ?? [],
                          titlesAreNames: json["titlesAreNames"] as? Bool ?? true,
                          namedSubjectPrompt: json["namedSubjectPrompt"] as? String,
                          chronologyBasis: json["chronologyBasis"] as? String,
                          questions: (json["questions"] as? [[String: Any]] ?? []).compactMap { q in
                              guard let id = q["id"] as? String, let ask = q["ask"] as? String,
                                    let exclude = q["exclude"] as? String,
                                    let prompt = q["prompt"] as? String else { return nil }
                              return QuizQuestion(id: id, ask: ask, exclude: exclude,
                                                  prompt: prompt,
                                                  sameCluster: q["sameCluster"] as? Bool ?? false)
                          },
                          items: items)
    }
}

/// Turn a manifest into the photographs the game would see.
func photos(from pack: PackOnDisk) -> [GamePhoto] {
    pack.items.map { item in
        let id = item["id"] as? String ?? UUID().uuidString
        var photo = GamePhoto(id: "pack:\(pack.id):\(id)",
                              origin: .pack(packID: pack.id, itemID: id))
        if let year = item["year"] as? Int {
            var parts = DateComponents()
            parts.year = year
            parts.month = item["month"] as? Int ?? 6
            parts.day = 15
            photo.creationDate = Calendar(identifier: .gregorian).date(from: parts)
        }
        if let latitude = item["latitude"] as? Double,
           let longitude = item["longitude"] as? Double {
            photo.coordinate = Coordinate(latitude: latitude, longitude: longitude)
        }
        photo.placeName = item["place"] as? String
        // Same rule the app applies: a pack whose titles are file names has none, and
        // the English name wins over the title where the pack carries one.
        if pack.titlesAreNames {
            photo.title = (item["commonName"] as? String) ?? (item["title"] as? String)
        }
        photo.scientificName = item["scientificName"] as? String
        photo.fact = item["fact"] as? String
        photo.creator = item["creator"] as? String
        photo.objectTags = Set(item["objectTags"] as? [String] ?? [])
        photo.possibleObjectTags = photo.objectTags
        photo.conceptID = photo.objectTags.first
        // The annotation a pack now carries: worked out when the pack was built rather
        // than on the phone, which is what lets an identify round use a pack photograph.
        photo.themeID = item["themeID"] as? String
        photo.plausibleThemeIDs = Set(item["themes"] as? [String] ?? [])
        if let theme = photo.themeID {
            if photo.plausibleThemeIDs.isEmpty { photo.plausibleThemeIDs = [theme] }
            // The harness has no themes table, so any non-empty wording will do: what is
            // being checked here is which photographs a round is built from, never the
            // words it puts on the screen.
            photo.themeIdentify = "Which one shows \(theme)?"
        }
        // A pack says so in its manifest; anything else is dated by when the photograph
        // was taken, and the spacing rule does not apply to it.
        photo.subjectID = item["subjectID"] as? String
        photo.subjectKind = item["group"] as? String
        // Same rule as the app: a pack dated by birth names each person's role.
        if pack.chronologyBasis == "birth" {
            photo.subject = PersonRole.role(from: photo.subjectKind)
        }
        photo.dateIsAboutTheSubject = ["birth", "created", "event"].contains(pack.chronologyBasis ?? "")
        photo.wasExamined = true
        // Quiz packs: the same fields the app reads in `carryingQuiz(from:)`.
        photo.facts = item["facts"] as? [String: [String]] ?? [:]
        photo.cluster = item["cluster"] as? String
        photo.family = item["family"] as? String
        photo.askYear = item["askYear"] as? Int
        if let years = item["years"] as? [Int], years.count == 2, years[0] <= years[1] {
            photo.generationYears = years[0]...years[1]
        }
        photo.keepApartFrom = Set(item["keepApartFrom"] as? [String] ?? [])
        photo.namedSubjectPrompt = pack.namedSubjectPrompt
        return photo
    }
}
