//
//  PublicPacks.swift
//  Time Rolls
//
//  The public photo library (spec §6.2), used two ways: as standalone content for a
//  sparse or GPS-poor personal library, and blended alongside personal photos for variety.
//
//  Packs come in two kinds:
//
//  * Bundled photo packs — real CC0 photographs with a manifest, built by
//    Tools/PackBuilder/build_pack.py. CC0 is the whole licensing story: a worldwide
//    waiver, so unlike "public domain" it doesn't vary by country, and it carries no
//    attribution duty. Provenance is recorded anyway and shown under Photo credits.
//  * Procedural packs — the original placeholder art, still used for motifs a real pack
//    doesn't cover yet, and as the fallback for any item with no image file.
//
//  The manifest format here is the same one a downloaded pack would use, which is the
//  pack file format left open in spec §12.
//

import Foundation

/// Placeholder-art subjects, used by packs that have no photography of their own.
enum PackMotif: String, Hashable {
    case mountains, seaside, cityscape, celebration, portrait, roadTrip, kitchen, garden
}

struct PackCredit: Hashable, Codable {
    var title: String
    var creator: String
    var source: String
    var sourceURL: String
    var license: String
}

struct PackItem: Identifiable, Hashable {
    var id: String
    var packID: String
    var date: Date
    var placeName: String?
    var coordinate: Coordinate?
    /// A real photograph, by resource name.
    var imageResource: String?
    /// Where that photograph lives. nil means it ships inside the app bundle.
    var imageDirectory: URL?
    /// Where the photograph can be fetched from, for packs that carry metadata only.
    var remoteURL: URL?
    /// Where this photograph lives in OneBucket — "packs/animals/animals-a-lion.jpg".
    /// Nil for packs that have not been mirrored yet.
    var remoteKey: String?
    /// Placeholder art, drawn on demand when there is no photograph.
    var motif: PackMotif?
    var credit: PackCredit?
    /// Subjects recorded when the pack was built, for packs found by searching for them.
    var declaredTags: Set<String> = []
    /// What the photograph is *of*, in one noun: "president", "boxer", "film star".
    /// A level whose photographs all share one lets the question name it.
    var subject: String?
    /// A sentence about the subject, shown once the answer is open. Taken from the
    /// subject's own Wikipedia article at build time, never written here.
    var fact: String?
    /// The country this photograph was taken in.
    ///
    /// Written into the pack when it is built, because nothing on the device will ever
    /// work it out: reverse geocoding runs on the player's own photographs and never on
    /// pack ones. Without it every pack photograph read as "country unknown", the rule
    /// that stops a round asking about a country two of its photographs share could not
    /// see them, and a round asked which photograph was from the United States while
    /// holding three American landmarks.
    var countryName: String?
    /// What this photograph is of, as a theme id — "wedding", "beach", "graduation".
    ///
    /// Worked out when the pack was built rather than on the phone. The classification is
    /// the same either way, but doing it once here beats doing it ten thousand times on
    /// everybody's device, and it means a photograph can be checked before it ships.
    var themeID: String?
    /// Every theme this photograph could arguably be called, generously read, so an
    /// identify round never stands a second wedding beside the wedding.
    var plausibleThemeIDs: Set<String> = []
    /// What this photograph shows, where a pack holds several photographs of each thing.
    var subjectID: String?
    /// What kind of thing this is, in the words a hint would use: "a mammal", "a bird".
    var kind: String?
    /// What this is called in English, where the title is Latin. See `PackManifest.Item`.
    var commonName: String?
    /// The Latin, for the back of the card. Nil where it is the common name again.
    var scientificName: String?

    var objectTags: Set<String> { declaredTags.union(motif?.objectTags ?? []) }
}

struct PhotoPack: Identifiable, Hashable {
    var id: String
    var title: String
    var blurb: String
    var items: [PackItem]
    /// How to ask "which came first" about this pack's subject. Asking "which photo is
    /// older" about a row of presidents is the wrong question — nobody is judging the
    /// photograph, they are placing the person.
    var chronologyPrompt: String?
    /// Whether this pack's dates are birthdays rather than the dates the photographs
    /// were taken. Famous Faces is ordered by when the person was born, because "who
    /// came first" over four portraits is a question about the people, and a 1900 print
    /// of somebody born in 1873 sits in the wrong place on a photograph's timeline.
    var datesAreBirths = false
    /// Whether this pack's years are facts about its subjects — when somebody was born,
    /// when a painting was made, when an event happened — rather than when a photograph
    /// was taken or uploaded.
    var datesAreAboutSubjects = false
    /// Whether to name each photograph while the round is still open.
    ///
    /// Off for people and places, where reading the name *is* the game. On for events:
    /// nobody recognises a 1903 photograph of a wooden aeroplane on a beach, so "which
    /// happened first" over four unlabelled photographs is not a hard question, it is an
    /// unanswerable one. Naming them turns it into what it was meant to be — putting
    /// things you know in order.
    var labelsWhilePlaying = false
    /// How this pack phrases "which one is the X?" when its photographs carry names.
    ///
    /// "Which photo has a lion in it?" is right for animals and wrong for paintings — the
    /// Mona Lisa is not *in* a photograph, it is what the photograph shows. `{name}` is
    /// replaced by the photograph's own title.
    var namedSubjectPrompt: String?
    /// Whether an item's title names what the photograph shows, or is just the file's name.
    var titlesAreNames = true
    /// Which games this pack can actually carry. A pack of modern photographs cannot
    /// answer "which of these is older" — nothing in a 2019 kitchen tells you it isn't
    /// a 2022 one — so a pack says what it is good for rather than being used for
    /// everything it technically has metadata for.
    var themes: Set<GameTheme> = Set(GameTheme.allCases)

    var isPlayable: Bool { !items.isEmpty }
}

// MARK: - Manifest

/// The on-disk pack format. One manifest plus its images makes a pack, whether it ships
/// in the app or arrives later over OneBucket.
private struct PackManifest: Decodable {
    struct Item: Decodable {
        var id: String
        var file: String?
        var remoteURL: String?
        var remoteKey: String?
        var objectTags: [String]?
        var title: String
        var year: Int
        var month: Int
        var place: String?
        var latitude: Double?
        var longitude: Double?
        var credit: String
        var source: String
        var sourceURL: String
        var license: String
        var subject: String?
        var fact: String?
        var themeID: String?
        var themes: [String]?
        var country: String?
        /// What this photograph shows. Several items share it — a pack holds more than one
        /// picture of each subject — and a round must never hold two that do.
        var subjectID: String?
        /// Written by the pack builder as the taxonomic group a creature belongs to.
        var group: String?
        /// What the thing is called in English.
        ///
        /// A plant or an animal is titled with whatever Wikidata calls it, and for a
        /// taxon that is usually the Latin: 500 of the 540 plants arrived as binomials.
        /// "Which photo has Aesculus hippocastanum in it?" is not a question — it is a
        /// spelling test. The question asks by this name, and a subject that has none is
        /// left out of the asking rather than asked about in Latin.
        var commonName: String?
        /// The Latin, for the back of the card, where it is a fact about the thing rather
        /// than the thing's name. Nil where it is simply the common name again.
        var scientificName: String?
    }

    var formatVersion: Int
    var id: String
    var title: String
    var blurb: String
    var license: String
    var themes: [String]?
    var chronologyPrompt: String?
    var chronologyBasis: String?
    var labelWhilePlaying: Bool?
    var namedSubjectPrompt: String?
    /// Whether an item's title is the name of what the photograph shows.
    ///
    /// True everywhere except Moments, whose titles are Wikimedia file names — things like
    /// "131003-D-BW835-2054 (10068243254)". Those belong on the credits screen, because
    /// that is the file's real name and attribution needs it, but they are not names for
    /// anything and curation must never treat them as one. A round that read them as names
    /// asked which photograph showed "president reagan blowing out candles … - dpla -
    /// f34ce5e1e7a2", and the confusability rules, which compare subjects, compared prose.
    var titlesAreNames: Bool?
    var items: [Item]
}

// MARK: - Library

enum PublicPackLibrary {

    private(set) static var packs: [PhotoPack] = assemble()
    private static var lookup: [String: PhotoPack] = Dictionary(
        packs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Call after a pack is downloaded or removed.
    static func reload() {
        packs = assemble()
        lookup = Dictionary(packs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func assemble() -> [PhotoPack] {
        // A downloaded pack wins over a bundled one of the same id.
        let downloaded = downloadedPacks()
        let downloadedIDs = Set(downloaded.map(\.id))
        let bundled = bundledPacks().filter { !downloadedIDs.contains($0.id) }
        return (downloaded + bundled).sorted { $0.title < $1.title }
    }

    static var defaultEnabledPackIDs: Set<String> {
        Set(packs.filter(\.isPlayable).map(\.id))
    }

    static func pack(id: String) -> PhotoPack? { lookup[id] }

    /// Which packs are willing to carry each game.
    static func packThemeSupport() -> [String: Set<GameTheme>] {
        Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0.themes) })
    }

    static func chronologyPrompts() -> [String: String] {
        Dictionary(uniqueKeysWithValues: packs.compactMap { pack in
            pack.chronologyPrompt.map { (pack.id, $0) }
        })
    }

    /// The packs whose dates are birthdays.
    static func birthDatedPackIDs() -> Set<String> {
        Set(packs.filter(\.datesAreBirths).map(\.id))
    }

    /// Metadata-only `GamePhoto` values for the enabled, playable packs.
    static func photos(enabledPackIDs: Set<String>,
                       day: Int = PhotoRotation.dayIndex()) -> [GamePhoto] {
        packs
            .filter { $0.isPlayable && enabledPackIDs.contains($0.id) }
            .flatMap { pack in
                // Only today's slice of each pack reaches the game.
                PhotoRotation.selection(from: pack.items, packID: pack.id, day: day)
                    .map { item in
                    GamePhoto(id: "pack:\(pack.id):\(item.id)",
                              origin: .pack(packID: pack.id, itemID: item.id),
                              creationDate: item.date,
                              coordinate: item.coordinate,
                              caregiverLabel: nil,
                              placeName: item.placeName,
                              objectTags: item.objectTags,
                              possibleObjectTags: item.objectTags,
                              countryName: item.countryName,
                              dateIsBirth: pack.datesAreBirths,
                              dateIsAboutTheSubject: pack.datesAreAboutSubjects,
                              subjectKind: item.kind,
                              subject: item.subject,
                              // A file name is not a name. Moments carries Wikimedia
                              // file names for the credits screen, and letting one
                              // through here would have curation asking which photograph
                              // shows "131003-D-BW835-2054".
                              // The English name wins over the title where the pack has
                              // one, so the question, the card and the voice all say the
                              // same word — "horse chestnut", not "Aesculus
                              // hippocastanum".
                              title: pack.titlesAreNames
                                  ? (item.commonName ?? item.credit?.title) : nil,
                              fact: item.fact,
                              namedSubjectPrompt: pack.namedSubjectPrompt,
                              scientificName: item.scientificName,
                              showsTitleWhilePlaying: pack.labelsWhilePlaying)
                        .carrying(themeID: item.themeID,
                                  plausible: item.plausibleThemeIDs,
                                  subjectID: item.subjectID)
                }
            }
    }

    /// Packs assembled while the app is running rather than shipped with it — Local
    /// Trivia is the only one. They are kept apart from `packs` so they never appear in
    /// the caregiver's pack list or in the default enabled set, but photo lookup and the
    /// credits screen still have to be able to find them.
    private(set) static var runtimePacks: [String: PhotoPack] = [:]

    static func register(runtime pack: PhotoPack) {
        runtimePacks[pack.id] = pack
    }

    static func item(packID: String, itemID: String) -> PackItem? {
        if let item = pack(id: packID)?.items.first(where: { $0.id == itemID }) {
            return item
        }
        return runtimePacks[packID]?.items.first { $0.id == itemID }
    }

    /// Pack photographs ship as loose files in the bundle, not in an asset catalog, so
    /// they have to be resolved by URL — `UIImage(named:)` does not reliably find them,
    /// and silently falling back to placeholder art hides the problem.
    static func imageURL(for item: PackItem) -> URL? {
        guard let resource = item.imageResource else { return nil }
        if let directory = item.imageDirectory {
            return directory.appendingPathComponent("\(resource).jpg")
        }
        return Bundle.main.url(forResource: resource, withExtension: "jpg")
    }

    /// Everything with a recorded source, for the credits screen.
    static var creditedPacks: [(pack: PhotoPack, credits: [PackCredit])] {
        packs.compactMap { pack in
            let credits = pack.items.compactMap(\.credit)
            return credits.isEmpty ? nil : (pack, credits)
        }
    }

    // MARK: Bundled manifests

    private static func downloadedPacks() -> [PhotoPack] {
        PackStore.shared.installedDirectories().compactMap { directory in
            let manifest = directory.appendingPathComponent(
                "\(directory.lastPathComponent).pack.json")
            return decodePack(at: manifest, imageDirectory: directory)
        }
    }

    private static func bundledPacks() -> [PhotoPack] {
        // Xcode flattens bundled resources, so manifests are named <pack-id>.pack.json
        // and looked up by that name rather than by folder.
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let manifests = urls.filter { $0.lastPathComponent.hasSuffix(".pack.json") }

        return manifests.compactMap { decodePack(at: $0, imageDirectory: nil) }
            .sorted { $0.title < $1.title }
    }

    /// `imageDirectory` is nil for a pack that ships inside the app, where the
    /// photographs are flattened into the bundle rather than kept in a folder.
    private static func decodePack(at url: URL, imageDirectory: URL?) -> PhotoPack? {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(PackManifest.self, from: data),
                  (1...2).contains(manifest.formatVersion) else { return nil }

            let items = manifest.items.map { entry -> PackItem in
                var components = DateComponents()
                components.year = entry.year
                components.month = min(max(entry.month, 1), 12)
                components.day = 12
                components.hour = 14
                let date = Calendar(identifier: .gregorian).date(from: components) ?? .distantPast

                let coordinate: Coordinate? = {
                    guard let latitude = entry.latitude, let longitude = entry.longitude else {
                        return nil
                    }
                    return Coordinate(latitude: latitude, longitude: longitude)
                }()

                return PackItem(
                    id: entry.id,
                    packID: manifest.id,
                    date: date,
                    // A pack entry with no place is written as null, but one written as
                    // "" is not nil and would reach a question as a blank. 595 of the
                    // landmark entries have no place at all; none of them may become one.
                    placeName: entry.place?.nilIfBlank,
                    coordinate: coordinate,
                    imageResource: entry.file.map { ($0 as NSString).deletingPathExtension },
                    imageDirectory: entry.file == nil ? nil : imageDirectory,
                    remoteURL: entry.remoteURL.flatMap(URL.init(string:)),
                    remoteKey: entry.remoteKey,
                    motif: nil,
                    credit: PackCredit(title: entry.title,
                                       creator: entry.credit,
                                       source: entry.source,
                                       sourceURL: entry.sourceURL,
                                       license: entry.license),
                    declaredTags: Set(entry.objectTags ?? []),
                    subject: entry.subject,
                    fact: entry.fact,
                    countryName: entry.country,
                    themeID: entry.themeID,
                    plausibleThemeIDs: Set(entry.themes ?? []),
                    subjectID: entry.subjectID,
                    kind: entry.group,
                    commonName: entry.commonName?.nilIfBlank,
                    scientificName: entry.scientificName?.nilIfBlank)
            }

            let themes = manifest.themes.map { names in
                Set(names.compactMap(GameTheme.init(rawValue:)))
            } ?? Set(GameTheme.allCases)

            return PhotoPack(id: manifest.id,
                             title: manifest.title,
                             blurb: manifest.blurb,
                             items: items,
                             chronologyPrompt: manifest.chronologyPrompt,
                             datesAreBirths: manifest.chronologyBasis == "birth",
                             datesAreAboutSubjects:
                                ["birth", "created", "event"]
                                    .contains(manifest.chronologyBasis ?? ""),
                             labelsWhilePlaying: manifest.labelWhilePlaying ?? false,
                             namedSubjectPrompt: manifest.namedSubjectPrompt,
                             titlesAreNames: manifest.titlesAreNames ?? true,
                             themes: themes.isEmpty ? Set(GameTheme.allCases) : themes)
    }
}
