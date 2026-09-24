//
//  GameModel.swift
//  Time Rolls
//
//  Core value types for the game loop. See PhotoChronology_Prototype_Spec_v1 §3–§5.
//

import Foundation
import CoreLocation

// MARK: - Themes

/// Chronology and Places need PhotoKit metadata only; Objects adds on-device Vision
/// classification (spec §4, §6.3).
enum GameTheme: String, CaseIterable, Identifiable, Codable {
    case chronology
    case places
    case objects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chronology: "Time"
        case .places: "Places"
        case .objects: "Things"
        }
    }

    var symbolName: String {
        switch self {
        case .chronology: "clock"
        case .places: "map"
        case .objects: "tag"
        }
    }

    /// True for themes that need to look at the photo itself rather than its metadata.
    var readsPhotoContent: Bool { self == .objects }
}

// MARK: - Photos

/// A coordinate we can hash, compare and cache without dragging CLLocation around.
struct Coordinate: Hashable, Codable {
    var latitude: Double
    var longitude: Double

    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// Grid cell used as the cache key for reverse geocoding, ~11km on a side.
    var clusterKey: String {
        String(format: "%.1f,%.1f", latitude, longitude)
    }

    func distance(to other: Coordinate) -> CLLocationDistance {
        clLocation.distance(from: other.clLocation)
    }
}

/// One playable photo, from either the player's library or a public pack.
/// Personal photos are referenced by identifier only — no pixels are held here.
struct GamePhoto: Identifiable, Hashable {
    enum Origin: Hashable {
        case personal(localIdentifier: String)
        case pack(packID: String, itemID: String)

        var isPersonal: Bool {
            if case .personal = self { return true }
            return false
        }

        /// Which pack this came from, or nil for the player's own photographs.
        var packID: String? {
            if case let .pack(packID, _) = self { return packID }
            return nil
        }
    }



    var id: String
    var origin: Origin
    var creationDate: Date?
    var coordinate: Coordinate?
    /// Plain caregiver-supplied context ("Mom's 80th"). Local only, never a person-ID.
    var caregiverLabel: String?
    /// Filled in by `PlaceResolver` for Places levels.
    var placeName: String?
    /// Allow-listed categories the on-device classifier is confident about (spec §6.3).
    var objectTags: Set<String> = []
    /// Categories it saw any hint of — used only to rule this photo out as a distractor.
    var possibleObjectTags: Set<String> = []
    /// The country the photograph was taken in, and its code. A question about a
    /// photograph taken abroad asks about the country rather than the town.
    var countryName: String?
    var countryCode: String?

    /// Which of the things the Things game can ask about this photograph looks most
    /// like, and how strongly — the themes model's own reading, independent of the
    /// classifier's tags. This is what a question is now built from.
    var conceptID: String?
    var conceptScore: Double = 0

    /// What the photograph is of, as the bundled themes model has it: a birthday, a
    /// beach, the garden. Used to build a round out of one kind of occasion, and to ask
    /// about it by name.
    var themeID: String?
    var themeTitle: String?
    var themeQuestion: String?
    /// What to ask when this is the only photograph in the round of its kind —
    /// "Which one shows a wedding?" rather than "Which wedding came first?".
    var themeIdentify: String?
    /// Every theme this photograph could plausibly belong to, on a deliberately generous
    /// bar — not the one confident answer `themeID` holds.
    ///
    /// It exists to disqualify distractors, so generosity is the safe direction. Asking
    /// "which one shows a wedding?" is ruined by a second wedding standing beside the
    /// answer, and a photograph that is *arguably* a wedding is exactly the one that
    /// ruins it. Anything faintly like the theme is therefore listed and kept out, at the
    /// cost of some perfectly good distractors going unused.
    var plausibleThemeIDs: Set<String> = []

    /// Attach a theme worked out somewhere other than this device.
    ///
    /// A pack photograph is classified once when the pack is built, not on every phone
    /// that downloads it, so the identify question has to be looked up from the shipped
    /// theme table rather than carried in the manifest — otherwise a pack would pin the
    /// wording of a question and the table could never be rephrased without rebuilding
    /// every pack.
    func carrying(themeID: String?, plausible: Set<String>,
                  subjectID: String? = nil) -> GamePhoto {
        guard themeID != nil || subjectID != nil else { return self }
        var copy = self
        copy.subjectID = subjectID
        guard let themeID else { return copy }
        copy.themeID = themeID
        copy.plausibleThemeIDs = plausible.isEmpty ? [themeID] : plausible
        copy.themeIdentify = GamePhoto.identifyQuestion(themeID)
        copy.wasExamined = true
        return copy
    }

    /// Filled in at launch from the shipped theme table. A closure rather than a direct
    /// call because the curation code is compiled without the themes model, so the
    /// harness can check it.
    nonisolated(unsafe) static var identifyQuestion: (String) -> String? = { _ in nil }

    /// Where the subject of the photograph sits, in unit coordinates from the top-left,
    /// as Vision's attention model has it. Nil when nothing stood out — a landscape, a
    /// pattern, a wall.
    var subjectArea: SubjectArea?

    /// Apple's own rating of the photograph, roughly -1 … 1. Zero when unexamined.
    var aesthetics: Double = 0
    /// How good a shot it is of whoever is in it — eyes open, in focus, lit. Zero when
    /// there is no face, which is why it is only ever used to choose between two
    /// photographs of the same moment.
    var shotQuality: Double = 0

    /// How much of the frame the largest face fills, 0 when there is none.
    var faceProminence: Double = 0
    /// Whether the on-device pass has actually looked at this photograph. Without it,
    /// "no face was found" and "nobody has looked yet" are the same value.
    var wasExamined = false
    /// Taken with the front camera, as PhotoKit's own Selfies album has it.
    var isSelfie = false

    /// Whether this photograph shows so much face that there is nothing else to see.
    ///
    /// Fine for "who came first", useless for "which photo is from Rome": a picture of
    /// somebody's chin and a sliver of sky says nothing about where it was taken, and
    /// asking anyway makes the round a guess.
    var hidesSurroundings: Bool { isSelfie || faceProminence > 0.08 }

    /// A photograph of a person, rather than a photograph with a person in it.
    ///
    /// The line is drawn much higher than `hidesSurroundings`, which only has to decide
    /// whether a photograph says anything about *where* it was taken. This decides whether
    /// the picture is *about* the person — and a birthday photograph of somebody holding a
    /// cake has a face in it and is still a fine round about cake.
    var isAPortrait: Bool { isSelfie || faceProminence > 0.22 }

    /// Whether the picture is mostly words — a receipt, a meme, a screenshot that
    /// PhotoKit never flagged as one. Never shown, never an answer.
    var looksLikeDocument = false
    /// Whether this photograph's date is the subject's birthday rather than the date
    /// the picture was taken.
    var dateIsBirth = false

    /// Whether this photograph's date says something about its *subject* rather than
    /// about the photograph.
    ///
    /// Famous Faces carries the year somebody was born; Famous Artworks carries the year
    /// a painting was made. Those are facts about the thing in the picture, and a round
    /// built on them asks a real question — who was born first, which was painted first.
    ///
    /// Animals and Landmarks carry the year the photograph was uploaded. Every animal in
    /// the pack says 2015 and every landmark says something between 2006 and 2015, which
    /// is a fact about Wikimedia rather than about lions or the Colosseum. The spacing
    /// rule exists so an era can be read off a picture, and it has nothing to say about
    /// dates like these — which is why it applies here and not everywhere.
    var dateIsAboutTheSubject = false

    /// What this photograph is *of*, where several photographs can be of the same thing.
    ///
    /// A pack used to hold one photograph per subject, so "two photographs of the Eiffel
    /// Tower" could not happen. Packs now hold several of each — which is the only way to
    /// reach five thousand photographs that are all of things people recognise — and that
    /// makes it possible for a round to offer two pictures of the same tower and mark one
    /// of them wrong.
    ///
    /// Nil for the player's own photographs: nothing claims to know what two of their
    /// pictures have in common.
    var subjectID: String?

    /// What kind of thing this shows, for the hint beside the question — "a mammal",
    /// "a bird", "a fish".
    ///
    /// "Which photo has a pangolin in it?" is a hard question asked cold and a fair one
    /// asked as *it's a mammal*: somebody who cannot name the animal can still recognise
    /// the kind, and the round becomes answerable by looking rather than by knowing.
    var subjectKind: String?
    /// Whether the on-device detector found a face in this photograph.
    ///
    /// Not a category and never an answer — the Things game must not start asking
    /// "which one has a person in it" about somebody's family. It is here so a round
    /// built from the player's own photographs can be all faces or all scenery rather
    /// than a jumble of the two.
    var showsPeople = false
    /// Pack photos only: what the picture is of, in one noun. Lets a set of presidents
    /// be asked about as presidents rather than as photographs.
    var subject: String?
    /// Personal photos only: the album the player themselves put this in. Not a guess —
    /// somebody typed it.
    var albumName: String?
    /// Pack photos only: who or what this is. The answer to "which of these was the
    /// earliest president" is not a date, it is Abraham Lincoln.
    var title: String?
    /// Pack photos only: something true about the subject, for after the answer.
    var fact: String?
    /// Pack photos only: how this pack phrases a question about its own named subjects.
    /// "{name}" stands in for the photograph's title.
    var namedSubjectPrompt: String?
    /// Whether to show this photograph's name before the answer is given.
    var showsTitleWhilePlaying = false

    var isPersonal: Bool { origin.isPersonal }
    /// Which pack this photograph came from, or nil when it is the player's own.
    var packID: String? { origin.packID }
}

// MARK: - Levels

/// One level: a theme, a curated photo set, one question, one right answer (spec §3.1).
/// The part of a photograph worth keeping when there is not room for all of it.
/// Unit coordinates, origin top-left, so it can be stored and compared without
/// dragging a graphics framework into the curation code.
struct SubjectArea: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var centreX: Double { x + width / 2 }
    var centreY: Double { y + height / 2 }
}

struct Level: Identifiable {
    let id = UUID()
    var theme: GameTheme
    var prompt: String
    /// The same question in warmer words, when the on-device model produced one that
    /// passed every guardrail. The written `prompt` is what everything else — the
    /// harness, the checks, the fallbacks — is built on; this is only what is shown.
    var livelyPrompt: String?
    var photos: [GamePhoto]
    var correctPhotoID: String
    /// Human-readable note on why this set is this hard. Surfaced only in caregiver diagnostics.
    var curationNote: String
    /// Objects only: the category the question asked about, so the answer's reveal
    /// caption names *that* rather than whatever else is in the photo.
    var focusTag: String?
    /// A standing hint shown with the question. Places uses it to say what country or
    /// state the named place is in, which rules photographs out without pointing at the
    /// one that is left.
    var hint: String?

    var usesPackPhotos: Bool { photos.contains { !$0.isPersonal } }

    func caption(for photo: GamePhoto) -> String {
        // Somebody's own photographs are never captioned.
        //
        // They used to be, and inconsistently: a date under this one, a place under that
        // one, nothing under the third — not because the third held nothing, but because
        // a date or a place name happened to be missing from it. A row where some tiles
        // carry a line and some do not reads as a statement about the bare ones, and it
        // is really a statement about our records.
        //
        // There is also nothing to tell. A pack photograph is captioned because nobody
        // knows who Kofi Annan is until it says so; the player took these, and the game
        // naming their own afternoon back at them adds nothing.
        // Places is the exception, and everything in it is captioned the same way — see
        // the Places branch below.
        guard !photo.isPersonal || theme == .places else { return "" }
        switch theme {
        case .chronology:
            guard let date = photo.creationDate else {
                return photo.title ?? photo.caregiverLabel ?? ""
            }
            guard let title = photo.title else {
                return Level.captionFormatter.string(from: date)
            }
            // Name the person, and only the year with it. The month on a public
            // photograph is made up — the pack records the year something happened,
            // not the day somebody pressed the shutter.
            let year = Level.yearFormatter.string(from: date)
            // Say what the year means. A 1950s photograph captioned "1901" looks wrong
            // until you know the round is about when people were born.
            return "\(title)\n\(photo.dateIsBirth ? "born \(year)" : year)"
        case .places:
            // The place, and only the place — for every photograph in the round.
            //
            // It used to be the landmark's name where there was one, which meant a pack
            // photograph said "The Colosseum" while somebody's own said "Virginia". Both
            // true, and wildly uneven: one names the thing in the picture, the other names
            // a state, and the row reads as though the game knows far more about the
            // stock photographs than about the player's life. It also gave away which
            // were which.
            //
            // Every photograph in a Places round has a place name — the theme requires it
            // — and the packs write theirs in the same shape reverse geocoding produces,
            // "Rome, Italy" beside "McLean, VA". So this is even by construction.
            return photo.placeName ?? ""
        case .objects:
            // Only the answer is named.
            //
            // This used to name every photograph the classifier could name, which meant
            // some tiles got a word under them and some got nothing — not because those
            // photographs held nothing, but because nothing had been written down about
            // them. A row where three tiles are captioned and one is blank reads as a
            // statement about the blank one, and it is really a statement about our
            // records.
            guard photo.id == correctPhotoID else { return "" }
            if let focusTag, let asked = ObjectCatalog.category(id: focusTag) {
                return asked.displayName.capitalized
            }
            // Named-subject rounds carry the creature's own name rather than a category.
            return photo.title ?? focusTag?.capitalized ?? ""
        }
    }

    /// What to write under a photograph while the round is still open — the name only.
    /// The reveal caption carries the year with it, and in a "which happened first"
    /// round the year is the answer.
    func name(for photo: GamePhoto) -> String {
        photo.showsTitleWhilePlaying ? (photo.title ?? "") : ""
    }

    private static let captionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    fileprivate static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
}

// MARK: - Theme rotation

/// Which theme to play next. Pure and injectable so its distribution can be checked
/// rather than eyeballed: mostly alternate, occasionally repeat, never starve a theme.
enum ThemeRotation {

    static let alternateChance = 0.7

    static func next(from available: [GameTheme],
                     last: GameTheme?,
                     roll: () -> Double = { Double.random(in: 0...1) },
                     pick: ([GameTheme]) -> GameTheme? = { $0.randomElement() }) -> GameTheme? {
        guard !available.isEmpty else { return nil }
        guard available.count > 1 else { return available[0] }
        if let last, roll() < alternateChance {
            let others = available.filter { $0 != last }
            return pick(others) ?? pick(available)
        }
        return pick(available)
    }
}

// MARK: - The numbers curation is built from

/// Every number a round is built from, and not one of them adjustable.
///
/// There used to be a difficulty lever here: a value from 0 to 1 that tightened the time
/// between photographs, made distractors look more like the answer, narrowed the radius
/// Places drew from, and moved itself after every round depending on whether somebody got
/// it right and how quickly. Beside it sat a round size of three, four or five. Both are
/// gone, along with the settings that fed them.
///
/// The lever was removed because it was solving a problem this game does not have. A lever that
/// adjusts itself silently is a game quietly deciding somebody is doing badly and making
/// things easier, or doing well and making them harder — and for a player with memory
/// difficulties, a good day followed by a harder game is a punishment for the good day.
/// The spec's own instruction was that adaptation stay invisible, which is most of the way
/// to saying it should not be there. It also fought the one thing that does matter: rounds
/// are three parts public to one part personal now, and the lever worked by choosing among
/// photographs the player owns. Measured end to end it had stopped moving anyway — the
/// gentlest and the hardest settings both produced fifty-three-year spreads.
///
/// What is left are the numbers the old "standard" setting used, fixed. The game plays the
/// way it played on the default, every time, for everybody.
enum DifficultyKnob {

    /// How many photographs a round holds. Four, always.
    ///
    /// It was three, four or five, chosen by a caregiver and capped to four on a phone
    /// because a fifth photograph starts a third row and shrinks every card. So five only
    /// ever happened on an iPad, three only if somebody went looking for it, and the
    /// setting had no screen anywhere in the app — it could be stored but not changed.
    ///
    /// Four is also what the rest of the game now assumes: a round is one of the player's
    /// photographs and three from the packs, which is a sentence that only parses at four.
    static let photoCount = 4

    /// How close together the curated photographs should sit in time.
    ///
    /// Nine years: what the old lever produced at its default, and comfortably clear of
    /// the twenty-five-year floor that applies the moment a public photograph is in the
    /// round, which in practice is almost always.
    static let chronologyTargetGap: TimeInterval = 9 * .year

    /// How often a distractor is chosen from the *alike* end of the pile rather than the
    /// unlike end. A quarter — alike enough to be a decision, rarely enough that a round
    /// is not usually a squint.
    static let chanceOfAlikeDistractors = 0.25

    /// The oldest photo has to be *clearly* the oldest — errorless design means
    /// the right answer is never a coin flip (spec §2).
    static let chronologyDecisiveGap: TimeInterval = max(45 * .day, chronologyTargetGap * 0.3)

    /// With public photographs, half a century apart is the floor. Nobody can place two
    /// strangers' photographs a few years apart; you can only do that with your own,
    /// where you remember. Eras are what a public photograph offers to read — the dress,
    /// the cars, the film itself — and those need decades between them to be legible.
    /// Kept equal to `everyPublicPairMinimumGap`. This used to be fifty years and applied
    /// only between the answer and the rest, which contradicted the twenty-five-year rule
    /// the moment that rule started applying to every pair: a round could satisfy one and
    /// fail the other. One number, applied in the one place it means something.
    static let publicPhotographMinimumGap: TimeInterval = everyPublicPairMinimumGap

    /// The least time between any two *public* photographs in a Time round.
    ///
    /// The rule this replaces only held between the answer and each other photograph, and
    /// between two of the player's own. Two pack photographs could sit a year apart, so a
    /// round asked which was older and offered two pictures from the same decade as the
    /// wrong answers — unanswerable, and unanswerable in the way that looks like the game
    /// being broken rather than the question being hard.
    ///
    /// Twenty-five years is a generation. It is what it takes for the clothes, the cars,
    /// the film and the hair to have changed enough that somebody can read the difference
    /// off the picture, which is the only way a Time round can be played at all when the
    /// photographs are not your own.
    ///
    /// Only between public photographs. The player's own are exempt: they were there, and
    /// asking for a generation between two of their own pictures would need a library
    /// spanning seventy-five years, which almost nobody has. Their photograph sits at the
    /// recent end of the round instead — see `personalPhotoIsMostRecent`.
    static let everyPublicPairMinimumGap: TimeInterval = 25 * .year

    /// How often an Objects level draws its distractors from the same family as the
    /// answer — a cat and a horse against a dog, rather than a bridge.
    static let objectsSameFamilyChance = chanceOfAlikeDistractors

    /// How far away a Places distractor may be drawn from.
    ///
    /// Just under a million metres — what the old lever gave at its default. Wide enough
    /// that the wrong answers are somewhere else entirely, narrow enough that they are not
    /// absurd: another part of the same country rather than another continent.
    static let placesNeighbourRadius: CLLocationDistance = 900_000
}

// MARK: - Small helpers

extension TimeInterval {
    static let day: TimeInterval = 86_400
    static let year: TimeInterval = 365.25 * 86_400
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
