//
//  CaregiverViews.swift
//  Photo Chronology
//
//  Caregiver setup, behind the soft gate — no password, no account (spec §7.1).
//

import SwiftUI

struct CaregiverHubView: View {

    @Bindable var engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PhotoSourcesView(engine: engine)
                    } label: {
                        Row(symbol: "photo.on.rectangle.angled",
                            title: "Photo sources",
                            detail: sourceSummary)
                    }
                    NavigationLink {
                        HowsItGoingView(engine: engine)
                    } label: {
                        Row(symbol: "chart.bar",
                            title: "How's it going",
                            detail: sessionSummary)
                    }
                }

                Section("Difficulty & pace") {
                    Picker("Starting difficulty", selection: $engine.settings.startingDifficulty) {
                        ForEach(CaregiverSettings.StartingDifficulty.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text(engine.settings.startingDifficulty.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Stepper(value: $engine.settings.levelsPerSession, in: 0...20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Photo sets per session")
                            Text(engine.settings.levelsPerSession == 0
                                 ? "No set length — play as long as you like"
                                 : "\(engine.settings.levelsPerSession) per session")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $engine.settings.adaptiveTiming) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adjust to their pace")
                            Text("Timing is used quietly to pick photos. It is never shown, counted down, or scored.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Accessibility") {
                    Picker("Text size", selection: $engine.settings.textScale) {
                        ForEach(CaregiverSettings.TextScale.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("Extra contrast", isOn: $engine.settings.highContrast)
                    Toggle("Sound and touch cues", isOn: $engine.settings.audioCues)

                    Picker("Black and white photos", selection: $engine.settings.monochromeMode) {
                        ForEach(CaregiverSettings.MonochromeMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text("Black and white makes a level a little harder. It stays crisp and "
                         + "high-contrast rather than faded, and you can switch it off entirely.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Row(symbol: "lock.shield", title: "Privacy & what we claim", detail: nil)
                    }
                    NavigationLink {
                        DiagnosticsView(engine: engine)
                    } label: {
                        Row(symbol: "wrench.and.screwdriver",
                            title: "Prototype diagnostics",
                            detail: nil)
                    }
                }

                Section {
                    Text("Sharing these numbers with a caregiver's own phone — a one-time "
                         + "pairing code, still no account — is designed but not built in this "
                         + "prototype.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Palette.accent)
            .navigationTitle("Caregiver setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: engine.settings) { engine.settings.save() }
            .onChange(of: engine.settings.startingDifficulty) { engine.resetDifficulty() }
            .onChange(of: sourceKey) {
                Task { await engine.applySettingsChange() }
            }
        }
    }

    private var sessionSummary: String {
        let count = engine.stats.sessionsThisWeek
        return "\(count) session\(count == 1 ? "" : "s") this week"
    }

    private var sourceSummary: String {
        let packs = engine.settings.enabledPackIDs.count
        let base = engine.settings.useAllPhotos ? "All photos" : "Chosen albums"
        return "\(base) · \(packs) photo pack\(packs == 1 ? "" : "s")"
    }

    /// Only photo-source changes are worth re-indexing the library for.
    private var sourceKey: String {
        let albums = engine.settings.albumSelection
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")
        let packs = engine.settings.enabledPackIDs.sorted().joined(separator: ",")
        let labels = engine.settings.labels
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        return "\(engine.settings.useAllPhotos)|\(albums)|\(packs)|\(labels)"
    }

    private struct Row: View {
        let symbol: String
        let title: String
        let detail: String?

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Photo sources

struct PhotoSourcesView: View {

    @Bindable var engine: GameEngine

    var body: some View {
        List {
            Section {
                Toggle("Use all my photos", isOn: $engine.settings.useAllPhotos)
            } footer: {
                Text(engine.library.access.canRead
                     ? "\(engine.library.photos.count) photos are in play right now."
                     : "Photo access hasn't been granted, so only photo packs are in play.")
            }

            if !engine.library.access.canRead {
                Section {
                    Button("Ask for photo access") {
                        Task {
                            await engine.requestPhotoAccess()
                            await engine.applySettingsChange()
                        }
                    }
                }
            }

            if !engine.library.albums.isEmpty {
                Section {
                    ForEach(engine.library.albums) { album in
                        Toggle(isOn: albumBinding(album)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                Text("\(album.estimatedCount) photos")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(engine.settings.useAllPhotos ? "Skip these albums" : "Include these albums")
                } footer: {
                    Text(engine.settings.useAllPhotos
                         ? "Screenshots and receipts are rarely worth showing. Turn one on here to leave it out."
                         : "Only the albums you turn on will appear in the game.")
                }
            }

            Section {
                ForEach(PublicPackLibrary.packs) { pack in
                    Toggle(isOn: packBinding(pack)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.title)
                            Text(pack.blurb)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!pack.isPlayable)
                }
            } header: {
                Text("Photo packs")
            } footer: {
                Text("Packs fill in when there aren't enough personal photos for a theme, and "
                     + "mix in for variety. Pack artwork in this prototype stands in for licensed "
                     + "historical photography.")
            }

            Section {
                NavigationLink("Add plain labels") {
                    LabelsView(engine: engine)
                }
            } footer: {
                Text("Optional notes like \"Italy 2005\" help pick better photo sets. They stay on "
                     + "this device and are not a face or person ID.")
            }
        }
        .navigationTitle("Photo sources")
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
        List {
            if engine.library.albums.isEmpty {
                Text("No albums to label yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(engine.library.albums) { album in
                VStack(alignment: .leading, spacing: 6) {
                    Text(album.title).font(.subheadline.weight(.semibold))
                    TextField("e.g. Mom's 80th", text: labelBinding(album.id))
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Labels")
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

// MARK: - Diagnostics

struct DiagnosticsView: View {

    let engine: GameEngine

    var body: some View {
        List {
            Section("Curation") {
                ForEach(engine.diagnostics, id: \.0) { row in
                    HStack(alignment: .top) {
                        Text(row.0)
                        Spacer()
                        Text(row.1)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.footnote)
                }
            }

            Section {
                Button("Flush engagement queue") {
                    Task { await engine.telemetry.flush() }
                }
                if let error = engine.telemetry.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if let flush = engine.telemetry.lastFlush {
                    Text("Last flush \(flush.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Engagement telemetry")
            } footer: {
                Text("Events carry theme, right/wrong, attempts, duration and difficulty only — "
                     + "never which photo, person or place. The OneBucket sink is a stub until the "
                     + "bucket namespace and event schema are settled.")
            }

            Section {
                NavigationLink("Things coverage") {
                    ObjectCoverageView(engine: engine)
                }
            } header: {
                Text("Objects theme")
            } footer: {
                Text("Which allow-listed categories actually turn up in this library, and "
                     + "which of them can carry a level. This is the evidence for deciding "
                     + "which Vision categories are reliable enough to ship.")
            }

            Section {
                Button("Reset progress numbers", role: .destructive) {
                    engine.stats.reset()
                }
                Button("Forget photo labels and look again", role: .destructive) {
                    engine.reclassifyPhotos()
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}

// MARK: - Objects coverage

/// Reports the allow-list against a real library — the evidence for the "which Vision
/// categories are reliable enough to ship" decision (spec §12).
struct ObjectCoverageView: View {

    let engine: GameEngine

    private var rows: [(category: ObjectCategory, matches: Int)] {
        engine.objects.coverage(in: engine.taggedPool)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Photos looked at",
                               value: "\(engine.objects.taggedCount)")
                LabeledContent("Still to look at",
                               value: "\(engine.objects.pendingCount(in: engine.library.photos))")
                LabeledContent("Couldn't be read",
                               value: "\(engine.objects.unreadableCount)")
                if engine.objects.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking at photos…").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            } footer: {
                if let reason = engine.objects.unavailableReason {
                    Text("The on-device classifier could not start, so personal photos "
                         + "have no subjects yet and the Things game is running on the photo "
                         + "packs alone. This is expected in the iOS Simulator, whose Core ML "
                         + "runtime cannot load the image classifier — run on a device to see "
                         + "it work.\n\nReported: \(reason)")
                }
            }

            Section {
                ForEach(rows, id: \.category.id) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.category.displayName)
                            Text("\(row.category.family.rawValue) · floor \(String(format: "%.2f", row.category.confidence))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(row.matches)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(row.matches > 0 ? Palette.accent : .secondary)
                    }
                }
            } header: {
                Text("Photos matched, per category")
            } footer: {
                Text("A category needs one clear photo of its own plus enough photos that "
                     + "plainly don't contain it before it can carry a level.")
            }
        }
        .navigationTitle("Things coverage")
    }
}
