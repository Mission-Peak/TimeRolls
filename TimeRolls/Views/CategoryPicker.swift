//
//  CategoryPicker.swift
//  Time Rolls
//
//  What to play: a grid of categories on the Home screen — Animals, Geography, Famous
//  Faces, the player's own photos — each switched on or off with a tap.
//
//  It used to be a sheet behind a small chip in the top corner of the play screen, which
//  is the last place anybody looks when deciding what to play. Home is where that decision
//  is made, so the choice lives there, large, as a picture and a name rather than a list
//  of toggles. Each category already mixes its own kinds of question, so there is no
//  separate "mix" and no list of question types.
//

import SwiftUI

struct CategoryGrid: View {

    @Bindable var engine: GameEngine

    @Environment(\.photoHighContrast) private var highContrast
    @Environment(\.photoTextScale) private var textScale

    private static let tints: [Color] = [Meadow.badgeOchre, Meadow.badgeOlive, Meadow.badgeSlate,
                                         Meadow.badgeRose, Meadow.badgeMauve]

    private var packs: [PhotoPack] { PublicPackLibrary.packs.filter(\.isPlayable) }

    var body: some View {
        StickerCard(fill: highContrast ? Palette.surface(true) : Meadow.cardCream) {
            VStack(alignment: .leading, spacing: 14) {
                // The screen's own title says "What to play"; the card says only how.
                Text("Tap to switch on or off")
                    .font(.system(size: 15 * textScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Meadow.muted)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    if engine.library.access != .denied {
                        tile(symbol: "person.crop.square.fill", tint: Meadow.badgeSage,
                             title: "My own photos",
                             isOn: engine.settings.ownPhotosOn) {
                            choose(ownPhotos: !engine.settings.ownPhotosOn,
                                   packs: engine.settings.enabledPackIDs)
                        }
                    }
                    ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                        tile(symbol: Self.symbol(for: pack.id),
                             tint: Self.tints[index % Self.tints.count],
                             title: pack.title,
                             isOn: engine.settings.enabledPackIDs.contains(pack.id)) {
                            var chosen = engine.settings.enabledPackIDs
                            if chosen.contains(pack.id) { chosen.remove(pack.id) } else { chosen.insert(pack.id) }
                            choose(ownPhotos: engine.settings.ownPhotosOn, packs: chosen)
                        }
                    }
                    // Notable places close by — looked up live, so it sits at the end.
                    tile(symbol: "mappin.and.ellipse", tint: Meadow.badgeClay,
                         title: "Places near you",
                         isOn: engine.settings.localTriviaEnabled) {
                        engine.settings.localTriviaEnabled.toggle()
                        engine.settings.save()
                        if engine.settings.localTriviaEnabled { engine.startLocalTriviaIfWanted() }
                    }
                }
            }
        }
        // A question type pinned before this moved here would hide most categories with
        // no way left to unpin it.
        .onAppear { if engine.pinnedTheme != nil { engine.choose(theme: nil) } }
    }

    /// Switch categories, but never down to nothing: the last one on stays on.
    private func choose(ownPhotos: Bool, packs: Set<String>) {
        guard ownPhotos || !packs.isEmpty else { return }
        engine.chooseSources(useOwnPhotos: ownPhotos, packIDs: packs)
    }

    private func tile(symbol: String, tint: Color, title: String, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, tint: tint)
                    .opacity(isOn ? 1 : 0.45)
                Text(title)
                    .font(.system(size: 16 * textScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(highContrast ? Palette.ink(true) : Meadow.title)
                    .opacity(isOn ? 1 : 0.55)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(isOn ? Meadow.cardMint : Color.white.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isOn ? Meadow.on : Meadow.muted.opacity(0.5))
                    .padding(6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    static func symbol(for packID: String) -> String {
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
}
