//
//  PlayView.swift
//  Photo Chronology
//
//  The core loop (spec §3): one theme, 3–5 photos, one tap-to-answer question.
//  No score, no countdown, no fail state — a wrong tap just dims and invites another look.
//

import SwiftUI

struct PlayView: View {

    let engine: GameEngine
    let onCaregiverGate: () -> Void

    @Environment(\.photoHighContrast) private var highContrast
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if let level = engine.level {
                Text(level.prompt)
                    .appFont(27, weight: .semibold)
                    .foregroundStyle(Palette.ink(highContrast))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)

                feedbackLine(level)

                // Centre the photos in whatever space is left, and scroll only when
                // five tiles genuinely don't fit.
                GeometryReader { proxy in
                    ScrollView {
                        grid(level)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(minHeight: proxy.size.height, alignment: .center)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                footer(level)
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .animation(.easeOut(duration: 0.25), value: engine.answeredCorrectly)
        .animation(.easeOut(duration: 0.2), value: engine.wrongIDs)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if let theme = engine.level?.theme {
                Label(theme.title, systemImage: theme.symbolName)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
            }

            Spacer()

            if let target = engine.sessionTarget {
                HStack(spacing: 6) {
                    ForEach(0..<target, id: \.self) { index in
                        Circle()
                            .fill(index < engine.levelsThisSession
                                  ? Palette.accent
                                  : Palette.accent.opacity(0.20))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityLabel("\(engine.levelsThisSession) of \(target) photo sets done")
            }

            Spacer()

            // Press-and-hold, so a stray tap never lands here (spec §7.1).
            Image(systemName: "ellipsis.circle")
                .appFont(24)
                .foregroundStyle(Palette.softInk(highContrast).opacity(0.55))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.7) { onCaregiverGate() }
                .accessibilityLabel("Caregiver setup")
                .accessibilityHint("Press and hold to open setup")
                .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Feedback

    private func feedbackLine(_ level: Level) -> some View {
        Group {
            if engine.answeredCorrectly {
                Label(praise, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.correct)
            } else if !engine.wrongIDs.isEmpty {
                Text("Not that one — have another look.")
                    .foregroundStyle(Palette.warmth)
            } else {
                Text(hint(for: level))
                    .foregroundStyle(Palette.softInk(highContrast).opacity(0.8))
            }
        }
        .appFont(17, weight: .medium)
        .frame(height: 44)
        .transition(.opacity)
    }

    private var praise: String {
        engine.attempts == 1 ? "That's the one." : "There it is."
    }

    private func hint(for level: Level) -> String {
        switch level.theme {
        case .chronology: "Tap the photo you think came first."
        case .places: "Tap the photo that belongs there."
        case .objects: "Tap the photo that has it."
        }
    }

    // MARK: - Grid

    private func grid(_ level: Level) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)],
                  spacing: 14) {
            ForEach(Array(level.photos.enumerated()), id: \.element.id) { index, photo in
                PhotoTile(photo: photo,
                          caption: level.caption(for: photo),
                          state: state(for: photo),
                          monochrome: engine.isMonochromeLevel,
                          provider: engine.images,
                          position: index + 1,
                          total: level.photos.count)
                    .onTapGesture { select(photo) }
            }
        }
    }

    private func state(for photo: GamePhoto) -> PhotoTile.State {
        guard let level = engine.level else { return .idle }
        if engine.answeredCorrectly {
            return photo.id == level.correctPhotoID ? .correct : .revealed
        }
        return engine.wrongIDs.contains(photo.id) ? .dimmed : .idle
    }

    private func select(_ photo: GamePhoto) {
        switch engine.select(photo) {
        case .correct: Feedback.correct(enabled: engine.settings.audioCues)
        case .tryAgain: Feedback.tryAgain(enabled: engine.settings.audioCues)
        case .ignored: break
        }
    }

    // MARK: - Footer

    private func footer(_ level: Level) -> some View {
        VStack(spacing: 10) {
            if engine.answeredCorrectly {
                Button {
                    engine.advance()
                } label: {
                    Text("Next photos")
                        .appFont(21, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Show me different photos") {
                    engine.skip()
                }
                .appFont(16, weight: .medium)
                .foregroundStyle(Palette.softInk(highContrast).opacity(0.8))
                .padding(.vertical, 15)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
}

// MARK: - Tile

struct PhotoTile: View {

    enum State {
        case idle
        /// A wrong tap: dim it and let the player keep going (spec §3.1).
        case dimmed
        case correct
        case revealed
    }

    let photo: GamePhoto
    let caption: String
    let state: State
    let monochrome: Bool
    let provider: ImageProvider
    let position: Int
    let total: Int

    @Environment(\.photoHighContrast) private var highContrast
    @SwiftUI.State private var image: UIImage?

    private var isRevealed: Bool { state == .correct || state == .revealed }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Palette.surface(highContrast))
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView().tint(Palette.softInk(highContrast))
                    }
                }
                .clipped()
                // Crisp mono, never faded — the contrast guardrail in spec §7.1.
                .grayscale(monochrome ? 1 : 0)
                .contrast(monochrome ? 1.14 : 1)
                .saturation(state == .dimmed ? 0.15 : 1)
                .opacity(state == .dimmed ? 0.4 : 1)

            if isRevealed, !caption.isEmpty {
                Text(caption)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.6))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor, lineWidth: state == .correct ? 5 : 1.5)
        }
        .overlay(alignment: .topTrailing) {
            if state == .correct {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(30)
                    .foregroundStyle(.white, Palette.correct)
                    .padding(8)
            }
        }
        .shadow(color: .black.opacity(state == .dimmed ? 0 : 0.10), radius: 6, y: 3)
        .scaleEffect(state == .correct ? 1.02 : 1)
        .task(id: photo.id) {
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 240, height: 240))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo \(position) of \(total)")
        .accessibilityValue(isRevealed ? caption : "")
        .accessibilityAddTraits(.isButton)
    }

    private var borderColor: Color {
        switch state {
        case .correct: Palette.correct
        case .dimmed: Palette.softInk(highContrast).opacity(0.15)
        case .revealed: Palette.softInk(highContrast).opacity(0.20)
        case .idle: Palette.softInk(highContrast).opacity(0.20)
        }
    }
}

// MARK: - Session complete

struct SessionCompleteView: View {

    let engine: GameEngine
    let onCaregiverGate: () -> Void

    @Environment(\.photoHighContrast) private var highContrast

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles")
                .appFont(54)
                .foregroundStyle(Palette.warmth)
            Text("Nice set of photos")
                .appFont(30, weight: .bold)
                .foregroundStyle(Palette.ink(highContrast))
            Text("Stop here, or keep going as long as you like.")
                .appFont(19)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.softInk(highContrast))

            Button {
                engine.continueSession()
            } label: {
                Text("Keep playing")
                    .appFont(21, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()

            Button("Caregiver setup") { onCaregiverGate() }
                .appFont(16, weight: .medium)
                .foregroundStyle(Palette.softInk(highContrast).opacity(0.75))
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 28)
    }
}
