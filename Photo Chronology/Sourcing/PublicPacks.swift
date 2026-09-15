//
//  PublicPacks.swift
//  Photo Chronology
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
    /// Placeholder art, drawn on demand when there is no photograph.
    var motif: PackMotif?
    var credit: PackCredit?

    var objectTags: Set<String> { motif?.objectTags ?? [] }
}

struct PhotoPack: Identifiable, Hashable {
    enum Availability: Hashable {
        case bundled
        /// Downloadable on demand from OneBucket — not implemented in the prototype.
        case remote
    }

    var id: String
    var title: String
    var blurb: String
    var availability: Availability
    var items: [PackItem]
    /// True when the pack is real photography rather than placeholder art.
    var isPhotography: Bool
    /// Which games this pack can actually carry. A pack of modern photographs cannot
    /// answer "which of these is older" — nothing in a 2019 kitchen tells you it isn't
    /// a 2022 one — so a pack says what it is good for rather than being used for
    /// everything it technically has metadata for.
    var themes: Set<GameTheme> = Set(GameTheme.allCases)

    var isPlayable: Bool { availability == .bundled && !items.isEmpty }
}

// MARK: - Manifest

/// The on-disk pack format. One manifest plus its images makes a pack, whether it ships
/// in the app or arrives later over OneBucket.
private struct PackManifest: Decodable {
    struct Item: Decodable {
        var id: String
        var file: String?
        var remoteURL: String?
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
    }

    var formatVersion: Int
    var id: String
    var title: String
    var blurb: String
    var license: String
    var themes: [String]?
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
        // A downloaded pack wins over a bundled one of the same id, and a real pack of
        // either kind supersedes the placeholder art it was built to replace.
        let downloaded = downloadedPacks()
        let downloadedIDs = Set(downloaded.map(\.id))
        let bundled = bundledPacks().filter { !downloadedIDs.contains($0.id) }
        let realIDs = downloadedIDs.union(bundled.map(\.id))
        return (downloaded + bundled).sorted { $0.title < $1.title }
            + proceduralPacks.filter { !realIDs.contains($0.id) }
    }

    static var defaultEnabledPackIDs: Set<String> {
        Set(packs.filter(\.isPlayable).map(\.id))
    }

    static func pack(id: String) -> PhotoPack? { lookup[id] }

    /// Which packs are willing to carry each game.
    static func packThemeSupport() -> [String: Set<GameTheme>] {
        Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0.themes) })
    }

    /// Metadata-only `GamePhoto` values for the enabled, playable packs.
    static func photos(enabledPackIDs: Set<String>) -> [GamePhoto] {
        packs
            .filter { $0.isPlayable && enabledPackIDs.contains($0.id) }
            .flatMap { pack in
                pack.items.map { item in
                    GamePhoto(id: "pack:\(pack.id):\(item.id)",
                              origin: .pack(packID: pack.id, itemID: item.id),
                              creationDate: item.date,
                              coordinate: item.coordinate,
                              caregiverLabel: nil,
                              placeName: item.placeName,
                              objectTags: item.objectTags,
                              possibleObjectTags: item.objectTags)
                }
            }
    }

    static func item(packID: String, itemID: String) -> PackItem? {
        pack(id: packID)?.items.first { $0.id == itemID }
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
                    placeName: entry.place,
                    coordinate: coordinate,
                    imageResource: entry.file.map { ($0 as NSString).deletingPathExtension },
                    imageDirectory: entry.file == nil ? nil : imageDirectory,
                    remoteURL: entry.remoteURL.flatMap(URL.init(string:)),
                    motif: nil,
                    credit: PackCredit(title: entry.title,
                                       creator: entry.credit,
                                       source: entry.source,
                                       sourceURL: entry.sourceURL,
                                       license: entry.license))
            }

            let themes = manifest.themes.map { names in
                Set(names.compactMap(GameTheme.init(rawValue:)))
            } ?? Set(GameTheme.allCases)

            return PhotoPack(id: manifest.id,
                             title: manifest.title,
                             blurb: manifest.blurb,
                             availability: .bundled,
                             items: items,
                             isPhotography: true,
                             themes: themes.isEmpty ? Set(GameTheme.allCases) : themes)
    }

    // MARK: Procedural packs

    // The placeholder-art packs are gone. They existed because there was no licensed
    // photography to show; there are now 452 CC0 photographs, and the drawn art was
    // starting to hurt — two motifs of the same kind look nearly identical, so a round
    // could offer two indistinguishable cakes. PackArtRenderer stays as the fallback for
    // any item with no photograph of its own.
    private static let proceduralPacks: [PhotoPack] = [
        PhotoPack(id: "americana-1970s",
                  title: "1970s Americana",
                  blurb: "Downloadable on demand. Pack delivery is not wired up in this prototype.",
                  availability: .remote,
                  items: [],
                  isPhotography: true),
    ]

    private static func build(
        _ packID: String,
        _ rows: [(String, PackMotif, Int, Int, String, Double, Double)]
    ) -> [PackItem] {
        rows.map { id, motif, year, month, place, lat, lon in
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 12
            components.hour = 14
            let date = Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
            return PackItem(id: id,
                            packID: packID,
                            date: date,
                            placeName: place,
                            coordinate: Coordinate(latitude: lat, longitude: lon),
                            imageResource: nil,
                            imageDirectory: nil,
                            remoteURL: nil,
                            motif: motif,
                            credit: nil)
        }
    }
}
