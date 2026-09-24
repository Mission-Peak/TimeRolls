//
//  CaregiverViews.swift
//  Time Rolls
//
//  Caregiver setup, behind the soft gate — no password, no account (spec §7.1).
//

import SwiftUI

struct CaregiverHubView: View {

    @Bindable var engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MeadowBackdrop()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        sourcesCard
                        paceCard
                        accessibilityCard
                        privacyCard
                        Text("Sharing these numbers with a caregiver's own phone — a "
                             + "one-time pairing code, still no account — is designed but "
                             + "not built in this prototype.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Meadow.body.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                    .readableColumn(maxWidth: 620)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: engine.settings) { engine.settings.save() }
            .onChange(of: engine.settings.photoSourceFingerprint) {
                Task { await engine.applySettingsChange() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.title)
                    .lineSpacing(-4)
                Text("Pick what makes your photo adventure special!")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Meadow.title.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.woodInk)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Meadow.wood, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    // MARK: Cards

    /// How far the on-device passes have got, in a sentence.
    private var examinationStatus: String {
        if let reason = engine.objects.unavailableReason {
            return "Paused — \(reason)"
        }
        if let reason = PhotoThemeIndex.shared.unavailableReason {
            return "Themes unavailable — \(reason)"
        }
        let done = engine.objects.taggedCount
        let waiting = engine.objects.pendingCount(in: engine.generator.personal)
        if waiting > 0 {
            return "\(done) looked at, \(waiting) to go"
        }
        return done > 0 ? "All \(done) looked at" : "Nothing to look at yet"
    }

    private var sourcesCard: some View {
        StickerCard(fill: Meadow.cardCream) {
            VStack(spacing: 14) {
                NavigationLink {
                    PhotoSourcesView(engine: engine)
                } label: {
                    MeadowRow(symbol: "camera.fill", tint: .hex(0x8B8BE8),
                              title: "Photo sources", detail: sourceSummary, chevron: true)
                }
                .buttonStyle(.plain)

                packStrip

                NavigationLink {
                    HowsItGoingView(engine: engine)
                } label: {
                    MeadowRow(symbol: "photo.stack.fill", tint: .hex(0x7FB3E8),
                              title: "How's it going", detail: sessionSummary, chevron: true)
                        .padding(12)
                        .background(Meadow.cardSky,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The pack thumbnails from the reference, as tinted tiles with a badge.
    private var packStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(PublicPackLibrary.packs.filter(\.isPlayable).prefix(5).enumerated()),
                    id: \.element.id) { index, pack in
                let tints: [Color] = [.hex(0xF3C765), .hex(0x7FC98A), .hex(0x7FB3E8),
                                      .hex(0xF2A0C0), .hex(0xA99BE8)]
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tints[index % tints.count])
                    .aspectRatio(0.92, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(tints[index % tints.count])
                            }
                            .padding(4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white, lineWidth: 3)
                    }
                    .accessibilityLabel(pack.title)
            }
        }
    }

    private var paceCard: some View {
        StickerCard(fill: Meadow.cardCream) {
            VStack(alignment: .leading, spacing: 14) {
                SectionBanner(symbol: "gamecontroller.fill", title: "Difficulty & pace",
                              tint: .hex(0x8B8BE8), band: .hex(0xFBEFC9))

                HStack(spacing: 12) {
                    IconBadge(symbol: "photo.on.rectangle.angled", tint: .hex(0xF3C765))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's challenge")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Meadow.title)
                        Text(engine.settings.dailyCardGoal == 0
                             ? "No challenge — play for as long as you like"
                             : "\(engine.settings.dailyCardGoal) photo cards a day, then "
                             + "carry on for as long as they want")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    }
                    Spacer(minLength: 4)
                    countPill
                }
                .padding(12)
                .background(Meadow.cardLavender,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            }
        }
    }

    private var countPill: some View {
        HStack(spacing: 10) {
            stepButton("minus") {
                engine.settings.dailyCardGoal = max(0, engine.settings.dailyCardGoal - 1)
            }
            Text("\(engine.settings.dailyCardGoal)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Meadow.title)
                .frame(minWidth: 22)
            stepButton("plus") {
                engine.settings.dailyCardGoal = min(30, engine.settings.dailyCardGoal + 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.75), in: Capsule())
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.hex(0x8B8BE8), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Fewer photo sets" : "More photo sets")
    }

    private var accessibilityCard: some View {
        StickerCard(fill: Meadow.cardSky) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "eye.fill", title: "Accessibility",
                              tint: .hex(0x5AA9E6), band: .hex(0xD3E9F9))

                VStack(spacing: 0) {
                    pickerRow(symbol: "textformat.size", tint: .hex(0xF3C765), title: "Text size",
                              value: engine.settings.textScale.title) {
                        Picker("", selection: $engine.settings.textScale) {
                            ForEach(CaregiverSettings.TextScale.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Divider().padding(.leading, 52)
                    toggleRow(symbol: "speaker.wave.2.fill", tint: .hex(0xD48BE0),
                              title: "Sound and touch cues", isOn: $engine.settings.audioCues)
                }
                .padding(.vertical, 4)
                .background(.white.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if Supporting.isAvailable {
                    Button {
                        Supporting.open()
                    } label: {
                        MeadowRow(symbol: "heart.fill", tint: .hex(0xD4708A),
                                  title: "Support Time Rolls",
                                  detail: "It's free, and it stays free", chevron: true)
                            .padding(12)
                            .background(.white.opacity(0.7),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    NarrationView(engine: engine)
                } label: {
                    MeadowRow(symbol: "speaker.wave.2.fill", tint: .hex(0x5AA9E6),
                              title: "Reading aloud",
                              detail: engine.settings.narration ? "On" : "Off",
                              chevron: true)
                        .padding(12)
                        .background(.white.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

            }
        }
    }

    private var privacyCard: some View {
        StickerCard(fill: Meadow.cardLavender) {
            NavigationLink { AboutView() } label: {
                MeadowRow(symbol: "lock.shield.fill", tint: .hex(0x7FC98A),
                          title: "Privacy & what we claim", detail: nil, chevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func toggleRow(symbol: String, tint: Color, title: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Meadow.title)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Meadow.on)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func pickerRow<P: View>(symbol: String, tint: Color, title: String,
                                    value: String, @ViewBuilder picker: () -> P) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Meadow.title)
            Spacer()
            picker()
                .labelsHidden()
                .tint(Meadow.title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionSummary: String {
        let count = engine.stats.sessionsThisWeek
        return "\(count) session\(count == 1 ? "" : "s") this week"
    }

    private var sourceSummary: String {
        let packs = PublicPackLibrary.packs.count { engine.settings.enabledPackIDs.contains($0.id) }
        let base = engine.settings.useAllPhotos ? "All photos" : "Chosen albums"
        return "\(base) · \(packs) photo pack\(packs == 1 ? "" : "s")"
    }
}

/// A row on a sticker card: badge, title, quiet detail, chevron.
struct MeadowRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                }
            }
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Meadow.muted)
            }
        }
    }
}

// MARK: - Photo sources

struct PhotoSourcesView: View {

    @Bindable var engine: GameEngine
    @Environment(\.photoHighContrast) private var highContrast

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
                    ownPhotosCard
                    if !engine.library.albums.isEmpty { albumsCard }
                    packsCard
                    labelsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .readableColumn(maxWidth: 620)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Photo sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: engine.settings) { engine.settings.save() }
        .onChange(of: engine.settings.photoSourceFingerprint) {
            Task { await engine.applySettingsChange() }
        }
    }

    private var ownPhotosCard: some View {
        StickerCard(fill: Meadow.cardCream) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "camera.fill", title: "My photos",
                              tint: .hex(0x8B8BE8), band: .hex(0xFBEFC9))

                HStack(spacing: 12) {
                    IconBadge(symbol: "person.crop.square.fill", tint: .hex(0x5FBF7F))
                    Text("Use all my photos")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Meadow.title)
                    Spacer()
                    Toggle("", isOn: $engine.settings.useAllPhotos)
                        .labelsHidden().tint(Meadow.on)
                }
                .padding(12)
                .background(Meadow.cardMint,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                note(engine.library.access.canRead
                     ? "\(engine.library.photos.count) photos are in play right now."
                     : "Photo access hasn't been granted, so only photo packs are in play.")

                if !engine.library.access.canRead {
                    Button {
                        Task {
                            await engine.requestPhotoAccess()
                            await engine.applySettingsChange()
                        }
                    } label: {
                        Text("Ask for photo access")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(Meadow.woodInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Meadow.wood,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Meadow.woodEdge, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var albumsCard: some View {
        StickerCard(fill: Meadow.cardLavender) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "rectangle.stack.fill",
                              title: engine.settings.useAllPhotos ? "Skip these albums"
                                                                  : "Include these albums",
                              tint: .hex(0xA99BE8), band: .hex(0xE3DCFA))

                VStack(spacing: 8) {
                    ForEach(Array(engine.library.albums.enumerated()), id: \.element.id) { index, album in
                        toggleTile(symbol: "folder.fill",
                                   tint: Self.packTints[index % Self.packTints.count],
                                   title: album.title,
                                   detail: "\(album.estimatedCount) photos",
                                   isOn: albumBinding(album))
                    }
                }

                note(engine.settings.useAllPhotos
                     ? "Screenshots and receipts are rarely worth showing. Turn one on here to leave it out."
                     : "Only the albums you turn on will appear in the game.")
            }
        }
    }

    private var packsCard: some View {
        StickerCard(fill: Meadow.cardSky) {
            VStack(alignment: .leading, spacing: 12) {
                SectionBanner(symbol: "photo.stack.fill", title: "Photo packs",
                              tint: .hex(0x5AA9E6), band: .hex(0xD3E9F9))

                VStack(spacing: 8) {
                    ForEach(Array(PublicPackLibrary.packs.enumerated()), id: \.element.id) { index, pack in
                        toggleTile(symbol: "photo.fill",
                                   tint: Self.packTints[index % Self.packTints.count],
                                   title: pack.title,
                                   detail: pack.isPlayable
                                       ? "\(pack.items.count) photos · \(pack.blurb)"
                                       : pack.blurb,
                                   isOn: packBinding(pack))
                            .disabled(!pack.isPlayable)
                    }
                }
            }
        }
    }


    private var localTriviaDetail: String {
        // CoreLocation tells its delegate the authorisation status the moment one is
        // set, so the service reports "waiting for permission" from launch — which read
        // as though something were pending even with the switch off.
        guard engine.settings.localTriviaEnabled else { return "Off" }
        return switch engine.localTrivia.state {
        case .idle: "Off"
        case .needsPermission: "Waiting for permission"
        case .denied: "Location is turned off for Time Rolls"
        case .looking: "Looking for places nearby…"
        case let .ready(count): "\(count) places near here"
        case .nothingNearby: "Nothing notable found nearby"
        case let .failed(reason): reason
        }
    }

    private var labelsCard: some View {
        StickerCard(fill: Meadow.cardCream) {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    LabelsView(engine: engine)
                } label: {
                    MeadowRow(symbol: "tag.fill", tint: .hex(0xF2A0C0),
                              title: "Add plain labels", detail: nil, chevron: true)
                }
                .buttonStyle(.plain)
                note("Optional notes like \"Italy 2005\" help pick better photo sets. They "
                     + "stay on this device and are not a face or person ID.")
            }
        }
    }

    private func toggleTile(symbol: String, tint: Color, title: String,
                            detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.title)
                Text(detail)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Meadow.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: isOn).labelsHidden().tint(Meadow.on)
        }
        .padding(12)
        .background(.white.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func note(_ text: String) -> some View {
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

    /// When "use all photos" is on, the toggle means *skip*; otherwise it means *include*.
    private func albumBinding(_ album: AlbumInfo) -> Binding<Bool> {
        Binding {
            let selection = engine.settings.albumSelection[album.id]
            return engine.settings.useAllPhotos ? (selection == false) : (selection == true)
        } set: { isOn in
            if engine.settings.useAllPhotos {
                if isOn {
                    engine.settings.albumSelection[album.id] = false
                } else {
                    engine.settings.albumSelection.removeValue(forKey: album.id)
                }
            } else {
                if isOn {
                    engine.settings.albumSelection[album.id] = true
                } else {
                    engine.settings.albumSelection.removeValue(forKey: album.id)
                }
            }
        }
    }

    private func packBinding(_ pack: PhotoPack) -> Binding<Bool> {
        Binding {
            engine.settings.enabledPackIDs.contains(pack.id)
        } set: { isOn in
            if isOn {
                engine.settings.enabledPackIDs.insert(pack.id)
            } else {
                engine.settings.enabledPackIDs.remove(pack.id)
            }
        }
    }
}

// MARK: - Labels

struct LabelsView: View {

    @Bindable var engine: GameEngine

    var body: some View {
        MeadowScreen(title: "Labels",
                     subtitle: "A note like \"Italy 2005\" helps pick better photo sets.") {
            StickerCard(fill: Meadow.cardCream) {
                VStack(alignment: .leading, spacing: 12) {
                    if engine.library.albums.isEmpty {
                        Text("No albums to label yet.")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    }
                    ForEach(engine.library.albums) { album in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(album.title)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(Meadow.title)
                            TextField("e.g. Mom's 80th", text: labelBinding(album.id))
                                .font(.system(size: 16, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.85),
                                            in: RoundedRectangle(cornerRadius: 14,
                                                                 style: .continuous))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Meadow.cardSky,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }

            MeadowNote(text: "Labels stay on this device and are never a face or person ID.")
        }
    }

    private func labelBinding(_ id: String) -> Binding<String> {
        Binding {
            engine.settings.labels[id] ?? ""
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                engine.settings.labels.removeValue(forKey: id)
            } else {
                engine.settings.labels[id] = trimmed
            }
        }
    }
}

// MARK: - Reading the question aloud

/// The voice picker, and how to get a better one (spec §6).
///
/// The app cannot install a voice. There is no API to download one, none to list what is
/// downloadable, and no way to deep-link to the screen that does it — so the difference
/// between a robot and something you would want reading to your mother is a walk through
/// Settings that somebody has to be told about. That is what the bottom half of this
/// screen is: the instructions, written out, because a feature nobody knows how to switch
/// on is a feature that does not exist.
struct NarrationView: View {

    @Bindable var engine: GameEngine

    private var narrator: Narrator { engine.narrator }

    @State private var previewing: String?

    var body: some View {
        MeadowScreen(title: "Reading aloud",
                     subtitle: "The question can be read out when each round opens, for "
                             + "anyone who finds a line of text hard work.") {
            StickerCard(fill: Meadow.cardCream) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $engine.settings.narration) {
                        Text("Read the question aloud")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Meadow.title)
                    }
                    .tint(Color.hex(0x5FA86B))
                    Text("The photographs are never described — only the question is "
                       + "read, once, as the round opens. There is a “Say it again” "
                       + "button under it.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                }
            }

            if engine.settings.narration {
                StickerCard(fill: Meadow.cardSky) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionBanner(symbol: "waveform", title: "Voice",
                                      tint: .hex(0x5AA9E6), band: .white.opacity(0.75))
                        if narrator.available.isEmpty {
                            Text("No voices are installed for your language yet — the "
                               + "steps below will add one.")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Meadow.muted)
                        }
                        ForEach(narrator.available) { choice in
                            voiceRow(choice)
                        }
                    }
                }

                StickerCard(fill: Meadow.cardSky) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionBanner(symbol: "globe", title: "Other languages",
                                      tint: .hex(0x8B8BE8), band: .white.opacity(0.75))
                        Text("The questions themselves stay in English — only the voice "
                           + "changes. For somebody whose first language isn't English, a "
                           + "familiar accent can still be easier to follow.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                        ForEach(narrator.otherLanguages) { choice in
                            voiceRow(choice)
                        }
                    }
                }
            }

            StickerCard(fill: Meadow.cardMint) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionBanner(symbol: "mic.fill", title: "Answering out loud",
                                  tint: .hex(0x5FA86B), band: .white.opacity(0.75))
                    Text("Every photo is numbered. With this on, saying \"two\" picks the "
                       + "second one — the same as tapping it. Tapping always works too.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Meadow.body)
                    switch engine.voiceAnswers.permission {
                    case .allowed:
                        Toggle(isOn: $engine.settings.voiceAnswers) {
                            Text("Let them answer by voice")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Meadow.title)
                        }
                        .tint(Color.hex(0x5FA86B))
                    case .notAsked:
                        Button {
                            Task { await engine.voiceAnswers.requestPermission() }
                        } label: {
                            MeadowButtonLabel(title: "Allow the microphone",
                                              symbol: "mic.fill")
                        }
                        .buttonStyle(.plain)
                    case .refused:
                        Text("The microphone is turned off for Time Rolls. Settings → "
                           + "Privacy & Security → Microphone.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    case .unavailable:
                        Text("This device can't recognise speech without sending it away, "
                           + "so this is switched off. Nothing said in this room leaves "
                           + "the device.")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    }
                    if let heard = engine.voiceAnswers.lastHeard {
                        Text("Last heard: \u{201C}\(heard)\u{201D}")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    }
                    if engine.settings.voiceAnswers {
                        Text(engine.voiceAnswers.diagnostics)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Meadow.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            StickerCard(fill: Meadow.cardLavender) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionBanner(symbol: "person.wave.2.fill",
                                  title: "A voice you recorded",
                                  tint: .hex(0x8B8BE8), band: .white.opacity(0.75))
                    switch narrator.personalVoice {
                    case .notAsked:
                        Text("If someone has recorded a Personal Voice on this device, "
                           + "this app can ask the questions in it. iOS keeps recorded "
                           + "voices hidden from apps until you allow it.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Meadow.body)
                        Button {
                            Task {
                                await narrator.requestPersonalVoice()
                            }
                        } label: {
                            MeadowButtonLabel(title: "Allow a recorded voice",
                                              symbol: "person.wave.2.fill")
                        }
                        .buttonStyle(.plain)
                    case .allowed:
                        Text(narrator.available.contains(where: \.isPersonal)
                             ? "Allowed. Any recorded voice appears at the top of the list "
                             + "above."
                             : "Allowed — but no recorded voice was found on this device. "
                             + "It is made in Settings → Accessibility → Personal Voice, "
                             + "and it has to be on the device the game is played on. If "
                             + "it was recorded elsewhere, turn on Share Across Devices "
                             + "there, on the same Apple Account.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Meadow.body)
                    case .refused:
                        Text("Not allowed. iOS only asks once — to change it, go to "
                           + "Settings → Privacy & Security → Personal Voice and turn "
                           + "Time Rolls on.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Meadow.body)
                    case .unsupported:
                        Text("This device can't make or use a recorded voice.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                    }
                }
            }

            StickerCard(fill: Meadow.cardMint) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionBanner(symbol: "arrow.down.circle.fill",
                                  title: "For a warmer voice",
                                  tint: .hex(0x5FA86B), band: .white.opacity(0.75))
                    Text("Apple's better voices are a free download, but only the Settings "
                       + "app can fetch them — this app has no way to do it for you.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Meadow.body)
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.hex(0x5FA86B), in: Circle())
                            Text(step)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Meadow.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("Look for one marked Enhanced or Premium. They are a few hundred "
                       + "megabytes, so use Wi-Fi. Once it has downloaded it appears in "
                       + "the list above.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                }
            }
        }
        .task {
            narrator.refreshPersonalVoiceStatus()
            engine.voiceAnswers.refreshPermission()
        }
        .onDisappear { narrator.stop() }
    }

    private static let steps = [
        "Open the Settings app.",
        "Tap Accessibility.",
        "Tap Spoken Content.",
        "Tap Voices, then your language.",
        "Tap a voice, then the download button beside it.",
    ]

    private func voiceNote(for choice: Narrator.Choice) -> String {
        if choice.isPersonal { return "A voice recorded on this device" }
        if !choice.isThisLanguage {
            return choice.quality == "Standard" ? choice.language
                                                : "\(choice.language) · \(choice.quality)"
        }
        return choice.quality == "Standard"
            ? "Standard — the built-in voice"
            : "\(choice.quality) — downloaded"
    }

    private func voiceRow(_ choice: Narrator.Choice) -> some View {
        let isChosen = engine.settings.voiceIdentifier == choice.id
            || (engine.settings.voiceIdentifier == nil && choice.isBest)
        return HStack(spacing: 10) {
            Button {
                engine.settings.voiceIdentifier = choice.id
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isChosen ? Color.hex(0x1F6B43) : Meadow.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Meadow.title)
                        Text(voiceNote(for: choice))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(choice.quality == "Standard"
                                             ? Meadow.muted : Color.hex(0x1F6B43))
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button {
                previewing = choice.id
                narrator.say("Which photo is older?", voiceIdentifier: choice.id)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.hex(0x5AA9E6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hear \(choice.name)")
        }
        .padding(10)
        .background(.white.opacity(isChosen ? 0.9 : 0.6),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
