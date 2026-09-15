//
//  CategoryPicker.swift
//  Photo Chronology
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

    private var packs: [PhotoPack] {
        PublicPackLibrary.packs.filter(\.isPlayable)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "A mix", detail: "Change between them as you go",
                        isChosen: engine.settings.pinnedTheme == nil) {
                        engine.choose(theme: nil)
                    }
                    ForEach(GameTheme.allCases) { theme in
                        if engine.availableThemes.contains(theme) {
                            row(title: theme.title,
                                detail: question(for: theme),
                                symbol: theme.symbolName,
                                isChosen: engine.settings.pinnedTheme == theme) {
                                engine.choose(theme: theme)
                            }
                        }
                    }
                } header: {
                    Text("What to look for")
                }

                Section {
                    if engine.library.access != .denied {
                        row(title: "My own photos",
                            detail: engine.library.access.canRead
                                ? "\(engine.library.photos.count) photos on this device"
                                : "Ask for permission to use them",
                            symbol: "person.crop.square",
                            isChosen: engine.settings.useAllPhotos) {
                            engine.chooseSources(useOwnPhotos: !engine.settings.useAllPhotos,
                                                 packIDs: engine.settings.enabledPackIDs)
                        }
                    }
                    ForEach(packs) { pack in
                        row(title: pack.title,
                            detail: "\(pack.items.count) photos",
                            symbol: "photo.stack",
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
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Pick as many sets as you like.")
                }
            }
            .tint(Palette.accent)
            .navigationTitle("What would you like?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func question(for theme: GameTheme) -> String {
        switch theme {
        case .chronology: "Which photo is older?"
        case .places: "Which photo was taken there?"
        case .objects: "Which photo has it in it?"
        }
    }

    @ViewBuilder
    private func row(title: String,
                     detail: String,
                     symbol: String? = nil,
                     isChosen: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
