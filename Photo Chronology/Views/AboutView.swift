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
                        detail: "Photos are only ever drawn on this screen. Nothing about the image itself is read, stored or sent.")
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
