//
//  CategoryPicker.swift
//  Time Rolls
//
//  Letting the player choose what they are looking at, from the chip on the play screen.
//
//  It is player-facing rather than caregiver-facing, so it stays large, visual and free
//  of settings language — a picture and a name, not a list of toggles.
//
//  There was a first-run version of this too, asking which sets of photographs to play
//  with before the player had seen a single round. It is gone, along with the card it was
//  built from: every pack is on to begin with, and whoever wants fewer can turn them off
//  in setup once they know what they are turning off.
//

import SwiftUI

// MARK: - Mid-session: change what I'm playing

/// Opened from the chip on the play screen. Covers both halves of "what am I playing":
/// the kind of question, and which photos it draws on.
struct PlayPickerView: View {

    @Bindable var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.photoHighContrast) private var highContrast

    private var packs: [PhotoPack] {
        PublicPackLibrary.packs.filter(\.isPlayable)
    }

    /// The tile colours run in the same order as the pack strip in caregiver setup, so a
    /// pack keeps its colour wherever you meet it.
    private static let packTints: [Color] = [.hex(0xF3C765), .hex(0x7FC98A), .hex(0x7FB3E8),
                                             .hex(0xF2A0C0), .hex(0xA99BE8)]

    var body: some View {
        ZStack {
            if highContrast {
                Palette.background(true).ignoresSafeArea()
            } else {
                MeadowBackdrop()
            }
            ScrollView {
                VStack(spacing: 20) {
                    header
                    lookForCard
                    photosCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
                .readableColumn(maxWidth: 620)
            }
            .scrollContentBackground(.hidden)
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("What would\nyou like?")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Meadow.title)
                .lineSpacing(-4)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.woodInk)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Meadow.wood,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Meadow.woodEdge, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
    }

    private var lookForCard: some View {
        StickerCard(fill: Meadow.cardCream) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "sparkle.magnifyingglass", title: "What to look for",
                              tint: .hex(0x8B8BE8), band: .hex(0xFBEFC9))

                VStack(spacing: 10) {
                    pickRow(symbol: "square.grid.2x2.fill", tint: .hex(0xF3C765),
                            title: "A mix", detail: "Change between them as you go",
                            fill: Meadow.cardLavender,
                            isChosen: engine.pinnedTheme == nil) {
                        engine.choose(theme: nil)
                    }
                    ForEach(Array(GameTheme.allCases.enumerated()), id: \.element) { index, theme in
                        if engine.availableThemes.contains(theme) {
                            pickRow(symbol: theme.symbolName,
                                    tint: Self.packTints[(index + 1) % Self.packTints.count],
                                    title: theme.title, detail: question(for: theme),
                                    fill: Meadow.cardSky,
                                    isChosen: engine.pinnedTheme == theme) {
                                engine.choose(theme: theme)
                            }
                        }
                    }
                }

                footnote("Just for now — next time you play it starts on a mix again.")
            }
        }
    }

    private var photosCard: some View {
        StickerCard(fill: Meadow.cardSky) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "camera.fill", title: "Photos",
                              tint: .hex(0x5AA9E6), band: .hex(0xD3E9F9))

                VStack(spacing: 10) {
                    if engine.library.access != .denied {
                        pickRow(symbol: "person.crop.square.fill", tint: .hex(0x5FBF7F),
                                title: "My own photos",
                                detail: engine.library.access.canRead
                                    ? "\(engine.library.photos.count) photos on this device"
                                    : "Ask for permission to use them",
                                fill: Meadow.cardMint,
                                isChosen: engine.settings.useAllPhotos) {
                            engine.chooseSources(useOwnPhotos: !engine.settings.useAllPhotos,
                                                 packIDs: engine.settings.enabledPackIDs)
                        }
                    }
                    // Notable places near the player, listed with the photo sources
                    // because that is what it is — another place the game draws pictures
                    // and questions from. It used to be a chip on the play screen and a
                    // card three screens into setup, neither of which is where somebody
                    // looks when deciding what to play with.
                    pickRow(symbol: "mappin.and.ellipse", tint: .hex(0xE8A33D),
                            title: "Places near you",
                            detail: engine.settings.localTriviaEnabled
                                ? "Notable places close by" : "Add notable places close by",
                            fill: .white.opacity(0.7),
                            isChosen: engine.settings.localTriviaEnabled) {
                        engine.settings.localTriviaEnabled.toggle()
                        engine.settings.save()
                        if engine.settings.localTriviaEnabled {
                            engine.startLocalTriviaIfWanted()
                        }
                    }
                    ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                        pickRow(symbol: "photo.fill",
                                tint: Self.packTints[index % Self.packTints.count],
                                title: pack.title, detail: "\(pack.items.count) photos",
                                fill: .white.opacity(0.7),
                                isChosen: engine.settings.enabledPackIDs.contains(pack.id)) {
                            var chosen = engine.settings.enabledPackIDs
                            if chosen.contains(pack.id) {
                                chosen.remove(pack.id)
                            } else {
                                chosen.insert(pack.id)
                            }
                            engine.chooseSources(useOwnPhotos: engine.settings.useAllPhotos,
                                                 packIDs: chosen)
                        }
                    }
                }

                footnote("Pick as many sets as you like.")
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundStyle(Meadow.sparkle)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Meadow.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.white.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A chooser row: badge, title, detail, and a round tick that fills in when picked.
    @ViewBuilder
    private func pickRow(symbol: String, tint: Color, title: String, detail: String,
                         fill: Color, isChosen: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(Meadow.title)
                    Text(detail)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Circle()
                    .fill(isChosen ? Meadow.on : .white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(isChosen ? .white : Meadow.muted.opacity(0.45))
                    }
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            }
            .padding(12)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private func question(for theme: GameTheme) -> String {
        switch theme {
        case .chronology: "Which photo is older?"
        case .places: "Which photo was taken there?"
        case .objects: "Which photo has it in it?"
        }
    }

}
