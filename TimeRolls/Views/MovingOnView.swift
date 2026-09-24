//
//  MovingOnView.swift
//  Time Rolls
//
//  Showing somebody how to move to the next photographs, once, before they start.
//
//  A round used to move on by itself a few seconds after a correct answer, so nobody had
//  to be told anything. That is gone: the countdown ran while somebody was deciding
//  whether to send a photograph to their daughter, and took it away mid-thought.
//
//  What replaces it is three ways to move on, none of which announces itself — a swipe has
//  no button to see, and saying "next" has nothing on screen at all. A gesture nobody
//  knows about is a gesture nobody uses, so it is demonstrated here rather than explained:
//  the card moves on its own, slowly, on a loop, which is a thing somebody can copy
//  without reading a word.
//

import SwiftUI

struct MovingOnView: View {

    @Bindable var engine: GameEngine
    let onDone: () -> Void

    /// How far the demonstration card slides, and how long it rests before repeating.
    private static let travel: CGFloat = 96
    private static let rest: Duration = .milliseconds(900)

    @State private var offset: CGFloat = 0
    @State private var fading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Moving on")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Meadow.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("When you have found the right photo, the game waits for you. "
                       + "Nothing disappears on its own, so there is time to look at a "
                       + "picture, or send it to somebody.")
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(Meadow.body)
                }

                demonstration

                ForEach(ways, id: \.title) { way in
                    StickerCard(fill: Meadow.cardCream) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: way.symbol)
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(Meadow.woodInk)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(way.title)
                                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Meadow.title)
                                Text(way.detail)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(Meadow.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Button {
                    engine.settings.save()
                    onDone()
                } label: {
                    MeadowButtonLabel(title: "Start playing", symbol: "play.fill")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .readableColumn(maxWidth: 620)
        }
        .task {
            // Loops until the screen goes away. Slow enough to be read as an invitation
            // rather than as something that has already happened.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 1.1)) { offset = Self.travel }
                try? await Task.sleep(for: .milliseconds(1100))
                withAnimation(.easeOut(duration: 0.25)) { fading = true }
                try? await Task.sleep(for: .milliseconds(250))
                offset = 0
                fading = false
                try? await Task.sleep(for: Self.rest)
            }
        }
    }

    /// A photo card sliding to the right, with a finger following it.
    private var demonstration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Meadow.cardMint)
                .frame(height: 132)
                .overlay {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(Meadow.woodInk.opacity(0.35))
                }
                .offset(x: offset)
                .opacity(fading ? 0 : 1)

            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(Meadow.woodInk)
                .offset(x: offset - 10, y: 46)
                .opacity(fading ? 0 : 0.9)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    /// Saying "next" is only listed when the microphone is actually on. Offering it
    /// otherwise teaches somebody a way to play that does nothing when they try it.
    private var ways: [(symbol: String, title: String, detail: String)] {
        var out: [(symbol: String, title: String, detail: String)] = [
            ("hand.draw.fill", "Swipe across",
             "Slide a finger to the right, anywhere on the photos."),
            ("forward.fill", "Or press Next photos",
             "The button at the bottom does the same thing."),
        ]
        if engine.settings.voiceAnswers {
            out.append(("mic.fill", "Or just say \u{201C}next\u{201D}",
                        "Say it out loud and the next photos come up. "
                      + "This only works while sound is on."))
        }
        return out
    }
}
