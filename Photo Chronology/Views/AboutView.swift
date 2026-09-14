//
//  AboutView.swift
//  Photo Chronology
//
//  Claim language and the data-flow summary, carried over verbatim (spec §9, §10).
//

import SwiftUI

struct AboutView: View {

    var body: some View {
        List {
            Section("What this is") {
                Text(ClaimLanguage.safeSummary)
                    .font(.subheadline)
            }

            Section("Where photos go") {
                DataRow(title: "Photo pixels",
                        leaves: "Never",
                        detail: "Photos are drawn on this screen and, for the Things game, looked at by this device's own photo recognition. No image is ever stored or sent.")
                DataRow(title: "What's in a photo",
                        leaves: "Never",
                        detail: ClaimLanguage.objectsPrivacy)
                DataRow(title: "Photo dates",
                        leaves: "Never",
                        detail: "Used on this device to pick photo sets.")
                DataRow(title: "GPS coordinates",
                        leaves: "Yes, coordinates only",
                        detail: ClaimLanguage.placesPrivacy)
                DataRow(title: "How often it's played",
                        leaves: "Yes, anonymously",
                        detail: "Counts only — theme, right or wrong, how long a set took. Never which photo, person or place.")
                DataRow(title: "Name, email, account",
                        leaves: "Never collected",
                        detail: "There is no sign-in.")
            }

            Section {
                Text(ClaimLanguage.standingDisclaimer)
                    .font(.footnote)
            } header: {
                Text("Please read")
            }
        }
        .navigationTitle("Privacy & claims")
    }

    private struct DataRow: View {
        let title: String
        let leaves: String
        let detail: String

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(leaves)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.accent)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Photo credits

/// CC0 waives attribution entirely, so nothing here is required. It exists so any
/// photograph that ships in a pack can be traced back to where it came from.
struct PhotoCreditsView: View {

    var body: some View {
        List {
            ForEach(PublicPackLibrary.creditedPacks, id: \.pack.id) { entry in
                Section {
                    ForEach(Array(entry.credits.enumerated()), id: \.offset) { _, credit in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credit.title)
                                .font(.subheadline)
                            Text(credit.creator)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(credit.source) · \(credit.license)")
                                .font(.caption2)
                                .foregroundStyle(Palette.accent)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("\(entry.pack.title) — \(entry.credits.count) photographs")
                }
            }

            Section {
                Text("Every photograph in these packs is released under CC0, a worldwide "
                     + "waiver of copyright. That matters more than it sounds: \"public "
                     + "domain\" depends on which country you are in, while CC0 does not.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Photo credits")
    }
}
