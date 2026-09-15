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
    /// A real photograph bundled with the app, by resource name.
    var imageResource: String?
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

    var isPlayable: Bool { availability == .bundled && !items.isEmpty }
}

// MARK: - Manifest

/// The on-disk pack format. One manifest plus its images makes a pack, whether it ships
/// in the app or arrives later over OneBucket.
private struct PackManifest: Decodable {
    struct Item: Decodable {
        var id: String
        var file: String
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
    var items: [Item]
}

// MARK: - Library

enum PublicPackLibrary {

    static let packs: [PhotoPack] = {
        let bundled = bundledPacks()
        let bundledIDs = Set(bundled.map(\.id))
        // A real pack supersedes the placeholder one it was built to replace.
        return bundled + proceduralPacks.filter { !bundledIDs.contains($0.id) }
    }()

    static let defaultEnabledPackIDs: Set<String> =
        Set(packs.filter(\.isPlayable).map(\.id))

    static func pack(id: String) -> PhotoPack? { lookup[id] }

    private static let lookup: [String: PhotoPack] =
        Dictionary(packs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

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

    private static func bundledPacks() -> [PhotoPack] {
        // Xcode flattens bundled resources, so manifests are named <pack-id>.pack.json
        // and looked up by that name rather than by folder.
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let manifests = urls.filter { $0.lastPathComponent.hasSuffix(".pack.json") }

        let decoder = JSONDecoder()
        return manifests.compactMap { url -> PhotoPack? in
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(PackManifest.self, from: data),
                  manifest.formatVersion == 1 else { return nil }

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
                    imageResource: (entry.file as NSString).deletingPathExtension,
                    motif: nil,
                    credit: PackCredit(title: entry.title,
                                       creator: entry.credit,
                                       source: entry.source,
                                       sourceURL: entry.sourceURL,
                                       license: entry.license))
            }

            return PhotoPack(id: manifest.id,
                             title: manifest.title,
                             blurb: manifest.blurb,
                             availability: .bundled,
                             items: items,
                             isPhotography: true)
        }
        .sorted { $0.title < $1.title }
    }

    // MARK: Procedural packs

    private static let proceduralPacks: [PhotoPack] = [
        PhotoPack(id: "everyday-life",
                  title: "Everyday Life",
                  blurb: "Kitchens, gardens and front porches. Placeholder artwork.",
                  availability: .bundled,
                  items: build("everyday-life", [
                    ("el1", .kitchen, 1948, 4, "Sheffield, England", 53.3811, -1.4701),
                    ("el2", .garden, 1955, 7, "Cork, Ireland", 51.8985, -8.4756),
                    ("el3", .kitchen, 1962, 11, "Lyon, France", 45.7640, 4.8357),
                    ("el4", .garden, 1969, 5, "Portland, Oregon", 45.5152, -122.6784),
                    ("el5", .portrait, 1974, 9, "Naples, Italy", 40.8518, 14.2681),
                    ("el6", .kitchen, 1981, 2, "Toronto, Canada", 43.6532, -79.3832),
                    ("el7", .garden, 1988, 6, "Bath, England", 51.3811, -2.3590),
                    ("el8", .portrait, 1994, 10, "Seville, Spain", 37.3891, -5.9845),
                    ("el9", .kitchen, 2001, 3, "Austin, Texas", 30.2672, -97.7431),
                    ("el10", .garden, 2009, 8, "Wellington, New Zealand", -41.2866, 174.7756),
                    ("el11", .portrait, 2013, 12, "Chicago, Illinois", 41.8781, -87.6298),
                    ("el12", .kitchen, 2016, 5, "Copenhagen, Denmark", 55.6761, 12.5683),
                  ]),
                  isPhotography: false),

        PhotoPack(id: "classic-holidays",
                  title: "Classic Holidays",
                  blurb: "Birthdays, weddings and long tables of family. Placeholder artwork.",
                  availability: .bundled,
                  items: build("classic-holidays", [
                    ("ch1", .celebration, 1951, 12, "Boston, Massachusetts", 42.3601, -71.0589),
                    ("ch2", .celebration, 1959, 6, "Dublin, Ireland", 53.3498, -6.2603),
                    ("ch3", .portrait, 1966, 12, "Milan, Italy", 45.4642, 9.1900),
                    ("ch4", .celebration, 1972, 8, "Glasgow, Scotland", 55.8642, -4.2518),
                    ("ch5", .celebration, 1979, 12, "Denver, Colorado", 39.7392, -104.9903),
                    ("ch6", .portrait, 1986, 5, "Perth, Australia", -31.9523, 115.8613),
                    ("ch7", .celebration, 1993, 11, "Munich, Germany", 48.1351, 11.5820),
                    ("ch8", .celebration, 1999, 12, "Montréal, Canada", 45.5019, -73.5674),
                    ("ch9", .portrait, 2006, 7, "Valencia, Spain", 39.4699, -0.3763),
                    ("ch10", .celebration, 2011, 12, "Nashville, Tennessee", 36.1627, -86.7816),
                    ("ch11", .celebration, 2015, 4, "Amsterdam, Netherlands", 52.3676, 4.9041),
                    ("ch12", .portrait, 2019, 8, "Oslo, Norway", 59.9139, 10.7522),
                  ]),
                  isPhotography: false),

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
                            motif: motif,
                            credit: nil)
        }
    }
}
