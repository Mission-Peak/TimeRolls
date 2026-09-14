//
//  DesignSystem.swift
//  Photo Chronology
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

enum Palette {
    static func background(_ highContrast: Bool) -> Color {
        highContrast ? Color(white: 0.99) : Color(red: 0.98, green: 0.96, blue: 0.93)
    }

    static func surface(_ highContrast: Bool) -> Color {
        highContrast ? .white : Color(red: 1.0, green: 0.99, blue: 0.97)
    }

    static func ink(_ highContrast: Bool) -> Color {
        highContrast ? Color(white: 0.04) : Color(red: 0.13, green: 0.12, blue: 0.11)
    }

    static func softInk(_ highContrast: Bool) -> Color {
        highContrast ? Color(white: 0.22) : Color(red: 0.40, green: 0.37, blue: 0.34)
    }

    static let accent = Color(red: 0.13, green: 0.38, blue: 0.40)
    static let correct = Color(red: 0.10, green: 0.44, blue: 0.28)
    static let warmth = Color(red: 0.85, green: 0.52, blue: 0.20)
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
    }

    @MainActor
    static func tryAgain(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

/// The standing disclaimer and the safe claim language, carried over verbatim
/// from the Evidence Foundation doc (spec §10).
enum ClaimLanguage {
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

    /// Parallel line for the Objects theme. Draft — the Evidence Foundation doc's
    /// "Unified claim language" section is authoritative and should carry the final wording.
    static let objectsPrivacy = """
    For the Things game, this device looks at your photos on the device itself to spot \
    everyday things like a dog or a cake. No photo and no label is ever sent anywhere.
    """
}
