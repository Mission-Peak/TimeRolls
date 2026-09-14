//
//  CompanionBar.swift
//  Photo Chronology
//
//  The Together-mode strip: a quiet row addressed to whoever is sitting alongside
//  the player. Nothing here keeps score or reports anything anywhere — it offers a
//  hint to pass on, and something to ask once the photos are open.
//

import SwiftUI

struct CompanionBar: View {

    let level: Level
    let hasAnswered: Bool

    @Environment(\.photoHighContrast) private var highContrast
    @State private var shown: String?
    @State private var hintIndex = 0
    @State private var promptIndex = 0

    private var hints: [String] { CompanionPrompts.hints(for: level) }
    private var prompts: [String] { CompanionPrompts.conversation(for: level) }

    var body: some View {
        VStack(spacing: 10) {
            if let shown {
                HStack(alignment: .top, spacing: 10) {
                    Text(shown)
                        .appFont(16)
                        .foregroundStyle(Palette.ink(highContrast))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        self.shown = nil
                    } label: {
                        Image(systemName: "xmark")
                            .appFont(13, weight: .semibold)
                            .foregroundStyle(Palette.softInk(highContrast))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Hide")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.accent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                Label("Together", systemImage: "person.2")
                    .appFont(13, weight: .medium)
                    .foregroundStyle(Palette.softInk(highContrast).opacity(0.75))

                Spacer()

                Button(action: advance) {
                    Text(actionTitle)
                        .appFont(15, weight: .semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Palette.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.2), value: shown)
        // The reminiscence moment: once the set is open, offer something to ask.
        .onChange(of: hasAnswered) { _, answered in
            if answered {
                promptIndex = 0
                shown = prompts.first
            }
        }
    }

    private var actionTitle: String {
        if hasAnswered {
            return shown == nil ? "Something to talk about" : "Another"
        }
        if shown == nil { return "Offer a hint" }
        return hintIndex < hints.count - 1 ? "Another hint" : "Hide hint"
    }

    private func advance() {
        if hasAnswered {
            guard !prompts.isEmpty else { return }
            if shown == nil {
                promptIndex = 0
            } else {
                promptIndex = (promptIndex + 1) % prompts.count
            }
            shown = prompts[promptIndex]
            return
        }

        guard !hints.isEmpty else { return }
        if shown == nil {
            hintIndex = 0
            shown = hints[0]
        } else if hintIndex < hints.count - 1 {
            hintIndex += 1
            shown = hints[hintIndex]
        } else {
            shown = nil
            hintIndex = 0
        }
    }
}
