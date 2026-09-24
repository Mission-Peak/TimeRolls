//
//  AboutView.swift
//  Time Rolls
//
//  Claim language and the data-flow summary, carried over verbatim (spec §9, §10).
//

import SwiftUI

struct AboutView: View {

    var body: some View {
        MeadowScreen(title: "Privacy",
                     subtitle: "What stays here, what leaves, and what we don't claim.") {
            StickerCard(fill: Meadow.cardCream) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionBanner(symbol: "sparkles", title: "What this is",
                                  tint: .hex(0x8B8BE8), band: .hex(0xFBEFC9))
                    Text(ClaimLanguage.safeSummary)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Meadow.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StickerCard(fill: Meadow.cardSky) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionBanner(symbol: "lock.shield.fill", title: "Where photos go",
                                  tint: .hex(0x5AA9E6), band: .white.opacity(0.75))
                    // The lines themselves live in ClaimLanguage, which is the file to
                    // read against the written policy. This is only how they are drawn.
                    ForEach(ClaimLanguage.privacyLines) { line in
                        DataRow(title: line.title,
                                leaves: line.leaves,
                                detail: line.detail)
                    }
                }
            }

            StickerCard(fill: Meadow.cardCream) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionBanner(symbol: "doc.text.fill", title: "The full policy",
                                  tint: .hex(0x5FBF7F), band: .hex(0xD8F0E2))
                    Text("The summary above is what the app actually does. The full written "
                       + "policy, which is the one that governs, lives on our website.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Meadow.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: URL(string: ClaimLanguage.privacyPolicyURL)!) {
                        MeadowRow(symbol: "safari.fill", tint: .hex(0x5FBF7F),
                                  title: "mission-peak.com",
                                  detail: "Read the privacy policy",
                                  chevron: true)
                    }
                }
            }

            StickerCard(fill: Meadow.cardMint) {
                NavigationLink { PhotoCreditsView() } label: {
                    MeadowRow(symbol: "camera.fill", tint: .hex(0x7FB3E8),
                              title: "Photo credits",
                              detail: "Who took the photographs, and under which licence",
                              chevron: true)
                }
                .buttonStyle(.plain)
            }

            StickerCard(fill: Meadow.cardLavender) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionBanner(symbol: "exclamationmark.circle.fill", title: "Please read",
                                  tint: .hex(0xE08B8B), band: .white.opacity(0.7))
                    Text(ClaimLanguage.standingDisclaimer)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Meadow.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One flow of data: what it is, whether it leaves, and why. The verdict sits in a
    /// pill rather than grey text, because the verdict is the part being read.
    private struct DataRow: View {
        let title: String
        let leaves: String
        let detail: String

        private var isKept: Bool { leaves.hasPrefix("Never") }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Meadow.title)
                    Spacer(minLength: 8)
                    Text(leaves)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isKept ? Color.hex(0x1F6B43) : Meadow.woodInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isKept ? AnyShapeStyle(Color.hex(0xCFEFD9))
                                           : AnyShapeStyle(Meadow.wood.opacity(0.75)),
                                    in: Capsule())
                }
                Text(detail)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Meadow.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Photo credits

/// CC0 waives attribution entirely, so nothing here is required. It exists so any
/// photograph that ships in a pack can be traced back to where it came from.
private extension PhotoCreditsView {

    /// Whether this licence asks for the photographer to be named.
    static func needsCredit(_ licence: String) -> Bool {
        let text = licence.lowercased()
        return text.contains("cc by") || text.contains("cc-by") || text.contains("attribution")
    }

    static func summary(all: Int, needing: Int) -> String {
        let free = all - needing
        if needing == 0 { return "\(all) photographs, none requiring credit" }
        if free == 0 { return "\(all) photographs, each credited" }
        return "\(all) photographs · \(needing) credited below · "
             + "\(free) public domain or CC0"
    }
}

struct PhotoCreditsView: View {

    /// Which pack's credits are open. One at a time, and none to begin with.
    ///
    /// The screen used to draw every credit for every pack at once — two and a half
    /// thousand entries of three lines each. That is unusable to scroll and slow to open,
    /// and it is not what the licences ask for: Creative Commons asks for attribution
    /// reasonable to the medium, not a single unbroken wall of it.
    @State private var opened: String?

    var body: some View {
        MeadowScreen(title: "Photo credits") {
            ForEach(PublicPackLibrary.creditedPacks, id: \.pack.id) { entry in
                let needing = entry.credits.filter { Self.needsCredit($0.license) }
                StickerCard(fill: Meadow.cardCream) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                opened = opened == entry.pack.id ? nil : entry.pack.id
                            }
                        } label: {
                            HStack(spacing: 10) {
                                SectionBanner(symbol: "photo.fill",
                                              title: entry.pack.title,
                                              tint: .hex(0x7FB3E8), band: .hex(0xFBEFC9))
                                Spacer(minLength: 0)
                                Image(systemName: opened == entry.pack.id
                                      ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundStyle(Meadow.muted)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(Self.summary(all: entry.credits.count, needing: needing.count))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if opened == entry.pack.id {
                            // Only the photographs whose licence asks to be credited.
                            // Public domain and CC0 waive attribution, so listing them
                            // adds length without adding anything a licence requires.
                            ForEach(Array(needing.enumerated()), id: \.offset) { _, credit in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(credit.title)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(Meadow.title)
                                    Text(credit.creator)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(Meadow.body)
                                    Text("\(credit.source) · \(credit.license)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Meadow.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.white.opacity(0.65),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }

            MeadowNote(text: "Every photograph in these packs carries a licence that allows "
                       + "it to be used here. Those under a Creative Commons licence name "
                       + "their photographer above, which is what the licence asks for. The "
                       + "rest are public domain or CC0, which ask for nothing — they are "
                       + "counted rather than listed.")
        }
    }
}
