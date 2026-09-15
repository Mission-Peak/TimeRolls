//
//  MorePacksView.swift
//  Photo Chronology
//
//  Adding photo packs from OneBucket (spec §6.2, §8). A starter pack ships in the app;
//  everything else is downloaded here, which is what lets the photo library grow without
//  the app binary growing with it.
//

import SwiftUI

struct MorePacksView: View {

    let engine: GameEngine
    @State private var downloader = PackDownloader()

    var body: some View {
        List {
            switch downloader.state {
            case .idle, .loadingCatalog:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for photo packs…").foregroundStyle(.secondary)
                }

            case let .failed(reason):
                Section {
                    Text("Couldn't reach the photo packs.")
                        .font(.subheadline.weight(.semibold))
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await downloader.loadCatalog() }
                    }
                }

            case .ready:
                if downloader.available.isEmpty {
                    Text("No extra packs are available yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(downloader.available) { pack in
                    packRow(pack)
                }
            }

            if !installedPacks.isEmpty {
                Section {
                    ForEach(installedPacks, id: \.self) { packID in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PublicPackLibrary.pack(id: packID)?.title ?? packID)
                                Text(byteDescription(PackStore.shared.sizeOnDisk(packID)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                PackStore.shared.remove(packID)
                                Task { await engine.applySettingsChange() }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Downloaded")
                } footer: {
                    Text("Removing a pack frees the space. It can be downloaded again "
                         + "whenever you like.")
                }
            }

            if let error = downloader.lastError {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("More photos")
        .task {
            if downloader.state == .idle {
                await downloader.loadCatalog()
            }
        }
    }

    private var installedPacks: [String] {
        PackStore.shared.installedDirectories()
            .map(\.lastPathComponent)
            .sorted()
    }

    @ViewBuilder
    private func packRow(_ pack: CatalogPack) -> some View {
        let isInstalled = PackStore.shared.isInstalled(pack.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.title)
                        .font(.body.weight(.semibold))
                    Text(pack.blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail(for: pack))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)

                if isInstalled {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Palette.correct)
                        .font(.title3)
                } else if downloader.isDownloading(pack) {
                    Button("Stop") { downloader.cancel(pack) }
                        .buttonStyle(.borderless)
                } else {
                    Button("Get") {
                        downloader.download(pack) {
                            Task { await engine.applySettingsChange() }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let fraction = downloader.progress[pack.id] {
                ProgressView(value: fraction)
                    .tint(Palette.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(for pack: CatalogPack) -> String {
        var parts = ["\(pack.photoCount) photos", pack.sizeDescription, pack.license]
        if let years = pack.yearsDescription {
            parts.insert(years, at: 1)
        }
        return parts.joined(separator: " · ")
    }

    private func byteDescription(_ bytes: Int) -> String {
        String(format: "%.0f MB on this device", Double(bytes) / 1_000_000)
    }
}
