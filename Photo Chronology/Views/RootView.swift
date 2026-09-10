//
//  RootView.swift
//  Photo Chronology
//
//  The app opens straight into play — no login, no splash beyond the one-time
//  first-run flow (spec §3.2, §7.1).
//

import SwiftUI

struct RootView: View {

    @State private var engine = GameEngine()
    @State private var isShowingCaregiver = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let highContrast = engine.settings.highContrast

        ZStack {
            Palette.background(highContrast).ignoresSafeArea()

            switch engine.phase {
            case .firstRun:
                FirstRunView(engine: engine)
            case .preparing:
                PreparingView()
            case .playing:
                PlayView(engine: engine) { isShowingCaregiver = true }
            case .sessionComplete:
                SessionCompleteView(engine: engine) { isShowingCaregiver = true }
            case let .noContent(reason):
                NoContentView(engine: engine, reason: reason) { isShowingCaregiver = true }
            }
        }
        .environment(\.photoTextScale, engine.settings.textScale.multiplier)
        .environment(\.photoHighContrast, highContrast)
        .tint(Palette.accent)
        .task { await engine.start() }
        .onChange(of: scenePhase) { _, phase in
            // Engagement events ride along quietly; leaving the app is a good moment to send.
            if phase != .active {
                Task { await engine.telemetry.flush() }
            }
        }
        // The soft gate: a deliberate press-and-hold, then a plain confirmation. No password.
        .sheet(isPresented: $isShowingCaregiver) {
            CaregiverGateSheet(engine: engine)
        }
    }
}

// MARK: - Preparing

struct PreparingView: View {
    @Environment(\.photoHighContrast) private var highContrast

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Choosing some photos…")
                .appFont(20, weight: .medium)
                .foregroundStyle(Palette.softInk(highContrast))
        }
    }
}

// MARK: - First run

struct FirstRunView: View {

    let engine: GameEngine
    @Environment(\.photoHighContrast) private var highContrast
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Photo Chronology")
                        .appFont(38, weight: .bold)
                        .foregroundStyle(Palette.ink(highContrast))
                    Text("A gentle photo game for all ages.")
                        .appFont(22)
                        .foregroundStyle(Palette.softInk(highContrast))
                }

                VStack(alignment: .leading, spacing: 18) {
                    Bullet(symbol: "photo.on.rectangle.angled",
                           title: "Your photos, a few at a time",
                           detail: "Each round shows a handful of photos and asks one easy question about them.")
                    Bullet(symbol: "hand.tap",
                           title: "Just tap a photo",
                           detail: "There's no score, no timer, and no wrong turn you can't take back.")
                    Bullet(symbol: "lock.shield",
                           title: "Photos stay on this phone",
                           detail: "Your photos never leave your device. To spot things like "
                                + "a dog or a cake, your iPhone looks at them here on the "
                                + "phone. Only GPS coordinates are sent, to name a place, "
                                + "and only once per location.")
                }

                VStack(spacing: 12) {
                    Button {
                        Task {
                            isRequesting = true
                            await engine.requestPhotoAccess()
                            isRequesting = false
                            await engine.completeFirstRun()
                        }
                    } label: {
                        Text(isRequesting ? "One moment…" : "Use my photos")
                            .appFont(22, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequesting)

                    Button("Play with the built-in photos instead") {
                        Task { await engine.completeFirstRun() }
                    }
                    .appFont(18, weight: .medium)
                }

                Text(ClaimLanguage.standingDisclaimer)
                    .appFont(13)
                    .foregroundStyle(Palette.softInk(highContrast))
            }
            .padding(28)
        }
    }

    private struct Bullet: View {
        @Environment(\.photoHighContrast) private var highContrast
        let symbol: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .appFont(22, weight: .semibold)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appFont(19, weight: .semibold)
                        .foregroundStyle(Palette.ink(highContrast))
                    Text(detail)
                        .appFont(16)
                        .foregroundStyle(Palette.softInk(highContrast))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Nothing to play

struct NoContentView: View {

    let engine: GameEngine
    let reason: String
    let onCaregiverGate: () -> Void

    @Environment(\.photoHighContrast) private var highContrast

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "photo.stack")
                .appFont(52)
                .foregroundStyle(Palette.warmth)
            Text("Let's find some photos")
                .appFont(28, weight: .bold)
                .foregroundStyle(Palette.ink(highContrast))
            Text(reason)
                .appFont(18)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.softInk(highContrast))

            VStack(spacing: 12) {
                if !engine.library.access.canRead {
                    Button("Allow photo access") {
                        Task {
                            await engine.requestPhotoAccess()
                            await engine.prepare()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .appFont(19, weight: .semibold)
                }
                Button("Open caregiver setup", action: onCaregiverGate)
                    .appFont(18, weight: .medium)
                Button("Try again") {
                    Task { await engine.prepare() }
                }
                .appFont(18, weight: .medium)
            }
        }
        .padding(34)
    }
}

// MARK: - Soft gate

/// The confirmation step between gameplay and setup. A plain "is this you?" question,
/// deliberately not a login (spec §7.1).
struct CaregiverGateSheet: View {

    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmed = false

    var body: some View {
        if isConfirmed {
            CaregiverHubView(engine: engine)
        } else {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "person.2")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.accent)
                Text("Setting this up for someone else?")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Photo sources, difficulty, text size and how things are going. No password needed.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    isConfirmed = true
                } label: {
                    Text("Yes, open setup")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                Button("No, keep playing") { dismiss() }
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .padding(.bottom, 8)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .tint(Palette.accent)
            .presentationDetents([.medium])
            .presentationBackground(Color(.systemGroupedBackground))
        }
    }
}
