//
//  PublicPacks.swift
//  Photo Chronology
//
//  The public / historical photo library (spec §6.2). Used two ways:
//  (a) standalone content for a sparse or GPS-poor personal library,
//  (b) blended alongside personal photos inside a level.
//
//  PROTOTYPE NOTE — licensing and pack file format are open items (spec §12), so no
//  third-party imagery is bundled here. The bundled packs carry real dates and real
//  coordinates and render placeholder era artwork via `PackArtRenderer`, which exercises
//  every code path a licensed pack will use. `remote` packs show the OneBucket delivery
//  slot that is not wired up yet.
//

import Foundation

struct PackItem: Identifiable, Hashable {
    var id: String
    var motif: PackMotif
    var date: Date
    var placeName: String
    var coordinate: Coordinate
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

    var isPlayable: Bool { availability == .bundled && !items.isEmpty }
}

enum PackMotif: String, Hashable {
    case mountains, seaside, cityscape, celebration, portrait, roadTrip, kitchen, garden
}

enum PublicPackLibrary {

    static let packs: [PhotoPack] = [
        PhotoPack(id: "everyday-life",
                  title: "Everyday Life",
                  blurb: "Kitchens, gardens and front porches, 1948–2016.",
                  availability: .bundled,
                  items: build([
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
                  ])),

        PhotoPack(id: "travel-landmarks",
                  title: "Travel Landmarks",
                  blurb: "Coastlines, cities and mountain passes from six decades of travel.",
                  availability: .bundled,
                  items: build([
                    ("tl1", .seaside, 1953, 8, "Brighton, England", 50.8225, -0.1372),
                    ("tl2", .mountains, 1958, 7, "Interlaken, Switzerland", 46.6863, 7.8632),
                    ("tl3", .cityscape, 1964, 6, "Rome, Italy", 41.9028, 12.4964),
                    ("tl4", .seaside, 1971, 7, "Nice, France", 43.7102, 7.2620),
                    ("tl5", .roadTrip, 1977, 5, "Flagstaff, Arizona", 35.1983, -111.6513),
                    ("tl6", .mountains, 1983, 9, "Banff, Canada", 51.1784, -115.5708),
                    ("tl7", .cityscape, 1990, 4, "Lisbon, Portugal", 38.7223, -9.1393),
                    ("tl8", .seaside, 1996, 8, "Amalfi, Italy", 40.6340, 14.6027),
                    ("tl9", .cityscape, 2003, 10, "Kyoto, Japan", 35.0116, 135.7681),
                    ("tl10", .mountains, 2008, 7, "Queenstown, New Zealand", -45.0312, 168.6626),
                    ("tl11", .roadTrip, 2012, 6, "Reykjavík, Iceland", 64.1466, -21.9426),
                    ("tl12", .cityscape, 2017, 9, "Porto, Portugal", 41.1579, -8.6291),
                  ])),

        PhotoPack(id: "classic-holidays",
                  title: "Classic Holidays",
                  blurb: "Birthdays, weddings and long tables of family.",
                  availability: .bundled,
                  items: build([
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
                  ])),

        PhotoPack(id: "americana-1970s",
                  title: "1970s Americana",
                  blurb: "Downloadable on demand. Pack delivery is not wired up in this prototype.",
                  availability: .remote,
                  items: []),
    ]

    static let defaultEnabledPackIDs: Set<String> = ["everyday-life", "travel-landmarks", "classic-holidays"]

    static func pack(id: String) -> PhotoPack? { packs.first { $0.id == id } }

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
                              placeName: item.placeName)
                }
            }
    }

    static func item(packID: String, itemID: String) -> PackItem? {
        pack(id: packID)?.items.first { $0.id == itemID }
    }

    private static func build(
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
                            motif: motif,
                            date: date,
                            placeName: place,
                            coordinate: Coordinate(latitude: lat, longitude: lon))
        }
    }
}
