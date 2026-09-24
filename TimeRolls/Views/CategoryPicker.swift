//
//  CategoryPicker.swift
//  Time Rolls
//
//  Letting the player choose what they are looking at: once during the first run, for
//  anyone who isn't playing with their own photos, and any time afterwards from the chip
//  on the play screen.
//
//  Both are player-facing rather than caregiver-facing, so they stay large, visual and
//  free of settings language — a picture and a name, not a list of toggles.
//

import SwiftUI

// MARK: - A card for one set of photos

struct PackCard: View {

    let title: String
    let blurb: String
    let preview: PhotoPack?
    let isChosen: Bool
    let provider: ImageProvider

    @Environment(\.photoHighContrast) private var highContrast
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.accent.opacity(0.12))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .appFont(24)
                        .foregroundStyle(Palette.accent.opacity(0.7))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(20, weight: .semibold)
                    .foregroundStyle(Palette.ink(highContrast))
                Text(blurb)
                    .appFont(15)
                    .foregroundStyle(Palette.softInk(highContrast))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isChosen ? "checkmark.circle.fill" : "chevron.right")
                .appFont(isChosen ? 24 : 16, weight: .semibold)
                .foregroundStyle(isChosen ? Palette.correct : Palette.softInk(highContrast).opacity(0.5))
        }
        .padding(14)
        .background(Palette.surface(highContrast),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isChosen ? Palette.correct : Palette.softInk(highContrast).opacity(0.15),
                              lineWidth: isChosen ? 3 : 1)
        }
        .contentShape(Rectangle())
        .task(id: preview?.id) {
            guard let preview else { return }
            image = await provider.preview(for: preview,
                                           targetSize: CGSize(width: 170, height: 170))
        }
    }
}

// MARK: - First run: which photos?

/// Shown when someone chooses not to play with their own photos. One tap picks a set
/// and starts — no confirm step, nothing to read twice.
struct CategoryChooserView: View {

    let engine: GameEngine
    let onChosen: (Set<String>) -> Void

    @Environment(\.photoHighContrast) private var highContrast

    private var packs: [PhotoPack] {
        PublicPackLibrary.packs.filter(\.isPlayable)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Which photos would you like?")
                        .appFont(30, weight: .bold)
                        .foregroundStyle(Palette.ink(highContrast))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You can change this at any time while you play.")
                        .appFont(17)
                        .foregroundStyle(Palette.softInk(highContrast))
                }
                .padding(.bottom, 4)

                Button {
                    onChosen(Set(packs.map(\.id)))
                } label: {
                    PackCard(title: "A little of everything",
                             blurb: "Photos from all the sets below.",
                             // A different set's photo, so this card doesn't look
                             // identical to the first one listed underneath it.
                             preview: packs.count > 1 ? packs[1] : packs.first,
                             isChosen: false,
                             provider: engine.images)
                }
                .buttonStyle(.plain)

                // Places near the player, alongside the photo sets rather than three
                // screens into setup. It is the same kind of choice as the ones below —
                // what the game draws on — and it was in a settings screen only because
                // it arrived later than they did.
                Button {
                    engine.settings.localTriviaEnabled.toggle()
                    engine.settings.save()
                    if engine.settings.localTriviaEnabled {
                        engine.startLocalTriviaIfWanted()
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: engine.settings.localTriviaEnabled
                              ? "mappin.circle.fill" : "mappin.circle")
                            .appFont(30, weight: .black)
                            .foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Places near you")
                                .appFont(20, weight: .heavy)
                                .foregroundStyle(Palette.ink(highContrast))
                            Text(engine.settings.localTriviaEnabled
                                 ? "Notable places close by are in the game."
                                 : "Add notable places close by.")
                                .appFont(15)
                                .foregroundStyle(Palette.softInk(highContrast))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.wash(highContrast),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Places near you")
                .accessibilityValue(engine.settings.localTriviaEnabled ? "On" : "Off")

                ForEach(packs) { pack in
                    Button {
                        onChosen([pack.id])
                    } label: {
                        PackCard(title: pack.title,
                                 blurb: pack.blurb,
                                 preview: pack,
                                 isChosen: false,
                                 provider: engine.images)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .readableColumn(maxWidth: 700)
        }
    }
}

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
