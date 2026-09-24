//
//  DesignSystem.swift
//  Time Rolls
//
//  Calm, large, high-contrast. Type scales from the caregiver's text-size choice on
//  top of Dynamic Type, and the high-contrast option deepens ink rather than
//  desaturating anything (accessibility guardrail, spec §7.1).
//

import SwiftUI

extension EnvironmentValues {
    @Entry var photoTextScale: Double = 1.0
    @Entry var photoHighContrast: Bool = false
}

/// Sage & Cream. Sage-green off-white surfaces, deep-sage ink and accent, earthy
/// clay secondaries, one green family throughout.
///
/// Extra contrast deepens the ink and lifts the paper; it never desaturates towards
/// grey or white. That is the accessibility guardrail in spec §7.1 — contrast
/// sensitivity declines with age, and colour discrimination is hit hard in some
/// dementia subtypes, so the answer is more contrast, not less colour.
enum Palette {

    // MARK: Surfaces

    /// The app background. Everything sits on this.
    static func background(_ highContrast: Bool) -> Color {
        highContrast ? .hex(0xF2F6EA) : .hex(0xE6ECDB)
    }

    /// Card fill — a step lighter than the page, never stark white.
    static func surface(_ highContrast: Bool) -> Color {
        highContrast ? .hex(0xFBFDF7) : .hex(0xF1F5EB)
    }

    /// Small backings — stat tiles, chips — between page and card.
    static func wash(_ highContrast: Bool) -> Color {
        highContrast ? .hex(0xF6F9F0) : .hex(0xEBF0E1)
    }

    /// Launch and first-run cream, warmer than the page.
    static let launch = Color.hex(0xEFEBDF)

    // MARK: Ink

    static func ink(_ highContrast: Bool) -> Color {
        highContrast ? .hex(0x12160F) : .hex(0x23281F)
    }

    static func softInk(_ highContrast: Bool) -> Color {
        highContrast ? .hex(0x3A4034) : .hex(0x5B6350)
    }

    // MARK: Accents — one green family

    static let accent = Color.hex(0x46593D)
    static let accentLight = Color.hex(0x5E7353)
    static let accentDark = Color.hex(0x35452D)
    static let olive = Color.hex(0x6E7A55)

    /// The right answer. Deeper than the accent so a five-point ring still announces
    /// itself on a page that is already green.
    static let correct = Color.hex(0x35452D)

    /// "Not that one — have another look." Clay, not the terracotta warning red: a
    /// second look is not an error, and this game has no failure state.
    static let warmth = Color.hex(0xA9744E)

    /// Reserved for genuine warnings. Earthy, never a clean alarm red.
    static let terracotta = Color.hex(0xB0503F)

    // MARK: Edges

    /// Card and tile edges are tone plus a faint sage hairline — no drop shadows.
    static let cardHairline = accent.opacity(0.28)
    static let tileHairline = accent.opacity(0.18)
}

enum Radius {
    static let card: CGFloat = 10
    static let tile: CGFloat = 6
    static let photo: CGFloat = 22
}

extension Color {
    /// Design tokens arrive as hex; keeping them that way means the palette can be
    /// checked against the design file by reading it.
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// Puts a settings list on the Sage & Cream page instead of iOS grey: sage paper
/// behind, card-coloured rows on top, with the system's own separators left alone.
private struct SageList: ViewModifier {
    let highContrast: Bool

    func body(content: Content) -> some View {
        // Order matters. `.listRowBackground` has to reach the List itself, so it goes
        // on before `.background` wraps the whole thing — applied after, the rows stayed
        // system white on a sage page.
        content
            .listRowBackground(Palette.surface(highContrast))
            .scrollContentBackground(.hidden)
            .tint(Palette.accent)
            .background(Palette.background(highContrast))
    }
}

/// Keeps content in a comfortable column on a big screen instead of letting it
/// stretch the full width of an iPad.
private struct ReadableColumn: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

private struct ScaledFont: ViewModifier {
    @Environment(\.photoTextScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func readableColumn(maxWidth: CGFloat = 820) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }

    func sageList(highContrast: Bool) -> some View {
        modifier(SageList(highContrast: highContrast))
    }

    func appFont(_ size: CGFloat,
                 weight: Font.Weight = .regular,
                 design: Font.Design = .rounded) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

/// Gentle audio and haptic cues, both optional (spec §7.1).
enum Feedback {
    @MainActor
    static func correct(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Chime.shared.play(.correct)
    }

    @MainActor
    static func tryAgain(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Chime.shared.play(.tryAgain)
    }
}

/// The standing disclaimer and the safe claim language, carried over verbatim
/// from the Evidence Foundation doc (spec §10).
enum ClaimLanguage {

    /// The written policy, which is what governs. The screen in the app is a plain summary
    /// of the same thing, and where the two ever disagree the written one is the one that
    /// counts — so it is linked rather than paraphrased and left to drift.
    static let privacyPolicyURL = "https://mission-peak.com/privacy/time-rolls"

    static let safeSummary = """
    Activities inspired by cognitive stimulation, spaced-retrieval memory practice, \
    reminiscence, and coordination research used in dementia care.
    """

    static let standingDisclaimer = """
    Wellness and engagement tool; not a medical device; does not diagnose, treat, cure, \
    or prevent any condition; does not slow, stop, or reverse cognitive decline; consult \
    a healthcare professional for medical advice.
    """

    static let placesPrivacy = """
    Your photos never leave your device; only GPS coordinates are sent to identify a \
    place name, and only once per location.
    """

    /// Local Trivia is the only feature that uses where the iPad *is* rather than where
    /// a photograph was taken, so it gets its own line rather than hiding inside the
    /// Places one. Draft — the Evidence Foundation doc's "Unified claim language"
    /// section is authoritative and should carry the final wording.
    static let localTriviaPrivacy = """
    Only when Local Trivia is switched on. Your rough location — rounded to about a \
    kilometre — is sent to Wikipedia to ask what notable places are nearby. It is not \
    stored, nothing identifies this device, and no photograph is involved.
    """

    /// Parallel line for the Objects theme. Draft — the Evidence Foundation doc's
    /// "Unified claim language" section is authoritative and should carry the final wording.
    static let objectsPrivacy = """
    For the Things game, this device looks at your photos on the device itself to spot \
    everyday things like a dog or a cake. No photo and no label is ever sent anywhere.
    """

    /// One line of the privacy summary: a kind of information, whether it leaves the
    /// device, and what happens to it.
    struct PrivacyLine: Identifiable {
        let title: String
        let leaves: String
        let detail: String
        var id: String { title }

        init(_ title: String, leaves: String, detail: String) {
            self.title = title
            self.leaves = leaves
            self.detail = detail
        }
    }

    /// Everything the app does with information, in one list.
    ///
    /// Here rather than in the view because this is the text that has to agree with the
    /// written policy on the website, and something that has to be checked against another
    /// document should be readable in one place rather than spread through a layout. It
    /// was previously split — three lines here, twelve written inline in `AboutView` —
    /// which is exactly the arrangement that lets the two drift apart unnoticed.
    ///
    /// The order is deliberate: photographs first, because that is what somebody opening
    /// this screen is worried about, then the rest of what the app touches.
    static let privacyLines: [PrivacyLine] = [
        PrivacyLine("Photo pixels",
                    leaves: "Never",
                    detail: "Photos are drawn on this screen and, for the Things game, looked at by this device's own photo recognition. No image is ever stored or sent."),
        PrivacyLine("What's in a photo",
                    leaves: "Never",
                    detail: objectsPrivacy),
        PrivacyLine("Photo dates",
                    leaves: "Never",
                    detail: "Used on this device to pick photo sets."),
        PrivacyLine("GPS coordinates",
                    leaves: "Yes, coordinates only",
                    detail: placesPrivacy),
        PrivacyLine("Where you are",
                    leaves: "Only for Local Trivia",
                    detail: localTriviaPrivacy),
        PrivacyLine("How often it's played",
                    leaves: "Never",
                    detail: "Counts are kept in a file on this device — which theme, right or wrong, how long a set took. Never which photo, person or place, and never sent anywhere."),
        PrivacyLine("Name, email, account",
                    leaves: "Never collected",
                    detail: "There is no sign-in, and no account to make."),
        PrivacyLine("Pack photographs",
                    leaves: "Yes, a request for a picture",
                    detail: "Photo sets are fetched from OneBucket, our storage provider, as you play. The request says which photograph is wanted and nothing about you — no identifier, no account, nothing about your own photos. Each is cached on the device so it is fetched once."),
        PrivacyLine("Sharing a photograph",
                    leaves: "Only where you send it",
                    detail: "Tapping Share hands the picture to iOS's own share sheet. You choose who gets it, and it never passes through us. A pack photograph carries its photographer's credit and licence with it; your own carries nothing."),
        PrivacyLine("Saving a photograph",
                    leaves: "Never",
                    detail: "Save puts a copy in your own photo library. It asks only for permission to add, never to read what is already there."),
        PrivacyLine("Microphone",
                    leaves: "Never",
                    detail: "Answering out loud is recognised on this device. Nothing is recorded, stored, or sent, and the microphone is only open while a round is waiting for an answer — and not at all when sound is off."),
        PrivacyLine("Your score and streak",
                    leaves: "Never",
                    detail: "Days played, sets finished and stars are kept on this device only. Deleting the app deletes them."),
        PrivacyLine("Photos a caregiver hides",
                    leaves: "Never",
                    detail: "A photograph struck off is remembered by its identifier on this device, so it is never shown again. The list does not leave the device and says nothing about what is in the picture."),
        PrivacyLine("Crash and usage analytics",
                    leaves: "No third parties",
                    detail: "There is no advertising SDK, no analytics SDK, and no tracking of any kind. Nothing is shared with anyone for advertising, and nothing is sold, ever."),
        PrivacyLine("Children",
                    leaves: "Not collected",
                    detail: "The app collects nothing that could identify anybody, of any age."),
    ]
}
