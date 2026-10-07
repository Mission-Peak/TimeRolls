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

/// Opened from the chip on the play screen: one list of categories — Animals, Geography,
/// Famous Faces, the player's own photos — each switched on or off.
///
/// It used to be two cards, a list of question types (Time, Places, Things, with "A mix")
/// and a list of photo sets, and the two had become the same choice made twice. A category
/// already mixes its own questions, so the categories are the only choice there is.
struct PlayPickerView: View {

    @Bindable var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.photoHighContrast) private var highContrast

    /// The tile colours run in the same order as the pack strip in caregiver setup, so a
    /// pack keeps its colour wherever you meet it.
    private static let packTints: [Color] = [Meadow.badgeOchre, Meadow.badgeOlive, Meadow.badgeSlate,
                                             Meadow.badgeRose, Meadow.badgeMauve]

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
                    categoriesCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
                .readableColumn(maxWidth: 620)
            }
            .scrollContentBackground(.hidden)
        }
        .presentationDetents([.large])
        // A question type pinned before the picker changed would hide most categories
        // with no way left to unpin it.
        .onAppear { if engine.pinnedTheme != nil { engine.choose(theme: nil) } }
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
                    .foregroundStyle(Meadow.buttonInk)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Meadow.button,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Meadow.buttonEdge, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
    }

    /// Every category, each one switched on or off. Each already mixes its own kinds of
    /// question — Famous Faces asks who was born first and which one is Einstein, Travel
    /// Landmarks asks where — so there is no separate "mix" to choose, and no list of
    /// question types: what somebody picks is what the pictures are of.
    private var categoriesCard: some View {
        StickerCard(fill: Meadow.cardCream) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "sparkle.magnifyingglass", title: "What to play",
                              tint: Meadow.badgeWalnut, band: Meadow.bandSand)

                VStack(spacing: 10) {
                    if engine.library.access != .denied {
                        pickRow(symbol: "person.crop.square.fill", tint: Meadow.badgeSage,
                                title: "My own photos",
                                detail: engine.library.access.canRead
                                    ? "Your pictures, in the order you took them"
                                    : "Ask for permission to use them",
                                fill: Meadow.cardMint,
                                isChosen: engine.settings.ownPhotosOn) {
                            choose(ownPhotos: !engine.settings.ownPhotosOn,
                                   packs: engine.settings.enabledPackIDs)
                        }
                    }
                    ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                        pickRow(symbol: Self.symbol(for: pack.id),
                                tint: Self.packTints[index % Self.packTints.count],
                                title: pack.title, detail: pack.blurb,
                                fill: Meadow.cardSky,
                                isChosen: engine.settings.enabledPackIDs.contains(pack.id)) {
                            var chosen = engine.settings.enabledPackIDs
                            if chosen.contains(pack.id) { chosen.remove(pack.id) } else { chosen.insert(pack.id) }
                            choose(ownPhotos: engine.settings.ownPhotosOn, packs: chosen)
                        }
                    }
                    // Notable places close by — looked up live, so it is a category like
                    // the others but lives at the end.
                    pickRow(symbol: "mappin.and.ellipse", tint: Meadow.badgeClay,
                            title: "Places near you",
                            detail: "Notable places close by",
                            fill: Meadow.cardSky,
                            isChosen: engine.settings.localTriviaEnabled) {
                        engine.settings.localTriviaEnabled.toggle()
                        engine.settings.save()
                        if engine.settings.localTriviaEnabled { engine.startLocalTriviaIfWanted() }
                    }
                }

                footnote("Pick as many as you like. Each one mixes its own questions.")
            }
        }
    }

    private var packs: [PhotoPack] {
        PublicPackLibrary.packs.filter(\.isPlayable)
    }

    /// Switch categories, but never down to nothing: the last one on stays on.
    private func choose(ownPhotos: Bool, packs: Set<String>) {
        guard ownPhotos || !packs.isEmpty else { return }
        engine.chooseSources(useOwnPhotos: ownPhotos, packIDs: packs)
    }

    private static func symbol(for packID: String) -> String {
        switch packID {
        case "animals": "pawprint.fill"
        case "plants": "leaf.fill"
        case "travel-landmarks": "building.columns.fill"
        case "famous-artworks": "paintpalette.fill"
        case "famous-faces": "person.2.fill"
        case "geography": "globe.americas.fill"
        case "cars": "car.fill"
        case "film-stars": "film.fill"
        case "sports-stars": "sportscourt.fill"
        default: "photo.fill"
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


}
