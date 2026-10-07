//
//  PlayView.swift
//  Time Rolls
//
//  The core loop (spec §3): one theme, 3–5 photos, one tap-to-answer question.
//  No score, no countdown, no fail state — a wrong tap just dims and invites another look.
//

import SwiftUI

struct PlayView: View {

    let engine: GameEngine
    let onCaregiverGate: () -> Void

    @Environment(\.photoHighContrast) private var highContrast
    @Environment(\.photoTextScale) private var textScale
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showFeedback = false
    @State private var isPickingCategory = false
    /// Cards turned over to read the back. Cleared with every new round.
    /// The one card turned over, if any.
    ///
    /// One rather than a set, and shown full screen rather than in place. Turned in the
    /// grid, a card had to grow to be readable and overlapped the photograph above it;
    /// and several could be turned at once, which left the round looking like a pile of
    /// text with the photographs underneath.
    @State private var flipped: GamePhoto?
    /// The fact card can be put aside to get back to the photographs — otherwise it
    /// covers the grid and there is no way to turn the other cards over.
    @State private var factPutAside = false
    /// The photograph being looked at closely, full screen.
    @State private var zoomed: GamePhoto?


    /// How far a finger has to travel before it counts as "next".
    ///
    /// Generous. The hands this is built for are not always steady, and a swipe that has
    /// to be precise is a swipe that fails and teaches somebody the gesture does not work.
    private static let swipeToAdvance: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            header

            if let level = engine.level {
                // The question sits on its own card. On a painted sky it has to: the sun
                // and the clouds live exactly where a centred heading goes, and a
                // question nobody can read is worse than a plain background.
                VStack(spacing: 0) {
                    Text(level.livelyPrompt ?? level.prompt)
                        .font(.system(size: 27 * textScale, weight: .heavy, design: .rounded))
                        .foregroundStyle(highContrast ? Palette.ink(true) : Meadow.title)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        // Tap the question to hear it again. This replaced a fourth
                        // button along the bottom, which sat beside a nearly identical
                        // one and was easy to press by mistake — and the question is
                        // where somebody looks when they want it repeated anyway.
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard engine.settings.narration else { return }
                            engine.speakQuestion()
                        }
                        .accessibilityHint(engine.settings.narration
                                           ? "Tap to hear the question again" : "")


                    // No "That's the one" or "Not that one" under the question any more.
                    // The tiles already say it — a green ring and a tick on the answer, a
                    // fade on a wrong tap — and the card stays one height, so the photos
                    // below it don't jump when the line appears.

                    // The landmark hint: what country or state the named place is in.
                    // It rules photographs out without pointing at the one that's left,
                    // and it is on screen from the start rather than being asked for.
                    if let hint = level.hint {
                        HStack(spacing: 8) {
                            // A pin for a place, a clock for a year. The pin was on both.
                            Image(systemName: level.theme == .places
                                  ? "mappin.and.ellipse"
                                  : level.theme.isQuiz ? "lightbulb.fill" : "clock.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Meadow.walnut, in: Circle())
                            Text(hint)
                                .font(.system(size: 16 * textScale, weight: .semibold,
                                              design: .rounded))
                                .foregroundStyle(Meadow.title)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(highContrast ? AnyShapeStyle(Palette.wash(true))
                                                 : AnyShapeStyle(Meadow.hintWash),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .frame(maxWidth: .infinity)
                .background(
                    highContrast ? AnyShapeStyle(Palette.surface(true))
                                 : AnyShapeStyle(.white.opacity(0.88)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.top, 6)

                // Centre the photos in whatever space is left, and scroll only when
                // five tiles genuinely don't fit.
                GeometryReader { proxy in
                    ScrollView {
                        grid(level, in: proxy.size)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity,
                                   minHeight: proxy.size.height,
                                   alignment: .center)
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
        .readableColumn(maxWidth: 1100)
        .overlay {
            if let flipped {
                FlippedCardView(photo: flipped, provider: engine.images) {
                    self.flipped = nil
                }
            }

            if let zoomed {
                ZoomView(photo: zoomed, provider: engine.images) { self.zoomed = nil }
                    .transition(.opacity)
            }
        }
        .overlay {
            if engine.answeredCorrectly, !factPutAside,
               let level = engine.level,
               let answer = level.photos.first(where: { $0.id == level.correctPhotoID }),
               let fact = answer.fact {
                FactPopup(photo: answer,
                          fact: fact,
                          provider: engine.images,
                          highContrast: highContrast,
                          textScale: textScale,
                          onSeePhotos: {
                              // Reading the fact is a deliberate act; the clock stops for it.
                              factPutAside = true
                          }) {
                    engine.advance()
                }
                .transition(.opacity)
            }
        }
        // Swipe right for the next round, once this one is answered. One of three ways
        // to move on — the button, the swipe, and saying so out loud — because the round
        // no longer moves on by itself and somebody has to be able to find at least one
        // of them.
        .gesture(
            DragGesture(minimumDistance: Self.swipeToAdvance)
                .onEnded { move in
                    guard engine.answeredCorrectly,
                          move.translation.width > Self.swipeToAdvance,
                          abs(move.translation.height) < abs(move.translation.width)
                    else { return }
                    engine.advance()
                }
        )
        .sheet(isPresented: $isPickingCategory) {
            PlayPickerView(engine: engine)
        }
        .onChange(of: engine.level?.id) {
            flipped = nil
            factPutAside = false
        }
        .onChange(of: engine.answeredCorrectly) {
        }
        // Read the question as the photographs appear. `task(id:)` rather than
        // `onChange`, because onChange fires on a *change* and the very first round is
        // already sitting there when this screen opens — which is why the game used to
        // stay silent until the second round.
        .task(id: engine.level?.id) {
            engine.speakQuestion()
        }
        .animation(.easeOut(duration: 0.25), value: engine.answeredCorrectly)
        .animation(.easeOut(duration: 0.2), value: engine.wrongIDs)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if let theme = engine.level?.theme {
                // The way into "what would you like?", and nothing else.
                //
                // It used to name the theme beside the icon — "Places", "Things". On a
                // phone that has the theme chip, the gear and the sound switch sharing
                // one row, the longest of those names wrapped onto a second line and the
                // header grew to meet it. The name is not what the button is for: it says
                // what you are playing now, and the reason to press it is to play
                // something else. The icon and the chevron say that on their own, and the
                // screen it opens names every theme in full.
                Button {
                    isPickingCategory = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: theme.symbolName)
                        Image(systemName: "chevron.down")
                            .appFont(12, weight: .black)
                            .opacity(0.8)
                    }
                    // The same painted-wood yellow as the Done button in setup, so the
                    // two things you can press up here look pressable.
                    .appFont(16, weight: .heavy)
                    .foregroundStyle(highContrast ? Palette.accent : Meadow.buttonInk)
                    // A round-ish chip now there is no word in it, and wide enough that
                    // it is still a comfortable target rather than a small icon.
                    .frame(minWidth: 30)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(highContrast ? AnyShapeStyle(Palette.accent.opacity(0.12))
                                             : AnyShapeStyle(Meadow.button),
                                in: Capsule())
                    .overlay {
                        if !highContrast {
                            Capsule().strokeBorder(Meadow.buttonEdge, lineWidth: 3)
                        }
                    }
                    .shadow(color: .black.opacity(highContrast ? 0 : 0.18), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playing \(theme.title)")
                .accessibilityHint("Choose what to look for and which photos to use")

            }

            Spacer()

            // Progress through today's challenge, not through this sitting. A row of dots
            // that resets every eight rounds tells somebody nothing about the thing they
            // are actually working towards, and it reset itself in the middle of a good
            // afternoon.
            if engine.settings.dailyCardGoal > 0,
               !engine.stats.hasMetChallenge(goal: engine.settings.dailyCardGoal) {
                let goal = engine.settings.dailyCardGoal
                let done = min(engine.stats.cardsToday, goal)
                Group {
                    // A dot each, while they fit. The challenge can now be set by hand
                    // as high as twenty, and twenty dots is 280 points of header on a
                    // phone that also holds the theme chip, the gear and the sound
                    // switch. Past eight the same thing is said in two numbers.
                    if goal <= 8 {
                        HStack(spacing: 6) {
                            ForEach(0..<goal, id: \.self) { index in
                                Circle()
                                    .fill(index < done ? Palette.accent
                                                       : Palette.accent.opacity(0.20))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    } else {
                        Text("\(done) of \(goal)")
                            .appFont(14, weight: .heavy)
                            .monospacedDigit()
                            .foregroundStyle(Palette.accent)
                    }
                }
                .accessibilityLabel("\(done) of \(goal) photo sets done today")
            }

            Spacer()

            // Setup and sound sit up here, not along the bottom. The bottom edge of a
            // phone is where a thumb rests while you hold it, so the two things nobody
            // means to press were the two easiest to press by accident — and the button
            // that actually moves the game on had to share its row with them.
            HStack(spacing: 10) {
                SettingsGear(onOpen: onCaregiverGate, compact: true)
                soundSwitch
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }


    // MARK: - Grid

    /// Two columns on a phone. On an iPad a set of three reads better in one row, and
    /// five as three-then-two; four stays a square.
    private var columnCount: Int {
        guard sizeClass == .regular, let count = engine.level?.photos.count else { return 2 }
        return count == 4 ? 2 : min(count, 3)
    }

    /// Laid out eagerly, on purpose.
    ///
    /// This was a LazyVGrid, which is the obvious choice and the wrong one here. A lazy
    /// container inside a ScrollView whose content is re-centred by `.frame(minHeight:)`
    /// can hand back hit regions that no longer sit where the tiles are drawn — tap a
    /// photo and the one below it answers. Three to five tiles is not a case where
    /// laziness buys anything, and rows built by hand have real frames.
    private func grid(_ level: Level, in space: CGSize) -> some View {
        let rows = stride(from: 0, to: level.photos.count, by: columnCount).map { start in
            Array(level.photos[start ..< min(start + columnCount, level.photos.count)])
        }
        // Grow the tiles to whatever room is left over, rather than letting them take a
        // share of the width and leaving half an iPad of empty meadow underneath. Both
        // directions get a say: the widest tile the row can hold, or the widest one whose
        // 4:3 height still lets every row fit without scrolling — whichever is smaller.
        let spacing: CGFloat = 14
        let columns = CGFloat(columnCount)
        let rowCount = CGFloat(max(rows.count, 1))
        // A phone has no width to spare, and two columns are all it can hold, so the
        // margin is as thin as still looks deliberate. The wider one is an iPad thing,
        // where a row of three would otherwise run into the bezel.
        let margin: CGFloat = sizeClass == .regular ? 64 : 28
        // Square cards on a phone. Width is what limits a two-column row, so a 4:3 card
        // could only ever be so big, and it left a band of empty meadow under the grid
        // while the photographs stayed small. A square is the same width and a third
        // taller — which is exactly the room that was going spare.
        let shape: CGFloat = sizeClass == .regular ? 4.0 / 3.0 : 1
        let acrossWidth = (space.width - margin - spacing * (columns - 1)) / columns
        let acrossHeight = (space.height - 24 - spacing * (rowCount - 1)) / rowCount * shape
        let tile = max(150, min(acrossWidth, acrossHeight))
        return VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 14) {
                    ForEach(row) { photo in
                        let index = level.photos.firstIndex { $0.id == photo.id } ?? 0
                        PhotoTile(photo: photo,
                                  caption: level.caption(for: photo),
                                  playingCaption: level.name(for: photo),
                                  isFlipped: false,
                                  onFlip: { flipped = photo },
                                  onZoom: { zoomed = photo },
                                  state: state(for: photo),
                                  monochrome: engine.isMonochromeLevel,
                                  provider: engine.images,
                                  position: index + 1,
                                  total: level.photos.count,
                                  shape: shape)
                            .frame(width: tile)
                            // The tap area is the tile as drawn — rounded corners and
                            // all — rather than whatever bounds the shadow and the
                            // scale effect leave behind.
                            .contentShape(RoundedRectangle(cornerRadius: 22,
                                                           style: .continuous))
                            .onTapGesture {
                                if engine.answeredCorrectly {
                                    flipped = photo
                                } else {
                                    select(photo)
                                }
                            }
                    }
                    // A short last row keeps the tiles the same size as the row above
                    // instead of stretching to fill. The filler is shaped like a tile,
                    // square and all: a plain Color.clear is flexible in both directions
                    // and stretches the row to whatever height is on offer.
                    if row.count < columnCount {
                        ForEach(0 ..< (columnCount - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(width: tile, height: tile / shape)
                        }
                    }
                }
            }
        }
    }

    /// The sentence that goes with the photo they just found, if it has one. Personal
    /// photos never do — the app has nothing true to say about somebody's own picture,
    /// and inventing something would be worse than saying nothing.
    private func factForAnswer(_ level: Level) -> String? {
        level.photos.first { $0.id == level.correctPhotoID }?.fact
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
        // `audioCues` now goes off with the sound switch, so this one test covers both.
        case .correct: Feedback.correct(enabled: engine.settings.audioCues)
        case .tryAgain: Feedback.tryAgain(enabled: engine.settings.audioCues)
        case .ignored: break
        }
    }

    /// Places near here, on or off, beside the theme chip.
    ///
    /// It lived in setup under a paragraph about rounded locations and Wikipedia. That
    /// paragraph still matters and is still there, but the switch itself belongs where the
    /// thing it changes happens.
    private var soundSwitch: some View {
        Button {
            engine.settings.soundOn.toggle()
            engine.settings.save()
            if engine.settings.soundOn {
                engine.startListeningIfWanted()
            } else {
                // Stop, do not merely stop starting: a round already listening would keep
                // its microphone open until the next question.
                engine.narrator.stop()
                engine.stopListening()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: engine.settings.soundOn
                      ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .appFont(17, weight: .black)
                // The word stays. A crossed-out speaker on its own is a symbol somebody
                // has to already know, and this is the control that decides whether the
                // game talks to you at all.
                Text(engine.settings.soundOn ? "Sound on" : "Sound off")
                    .appFont(13, weight: .heavy)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(highContrast ? Palette.softInk(true) : Meadow.buttonInk)
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(highContrast ? AnyShapeStyle(Palette.wash(true))
                                     : AnyShapeStyle(Meadow.button),
                        in: Capsule())
            .overlay {
                if !highContrast {
                    Capsule().strokeBorder(Meadow.buttonEdge, lineWidth: 3)
                }
            }
            .shadow(color: .black.opacity(highContrast ? 0 : 0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(engine.settings.narration
                            ? "Sound is on. Turn the reading voice off."
                            : "Sound is off. Turn the reading voice on.")
    }

    // MARK: - Footer

    /// One button along the bottom, the width of the screen: the way on.
    ///
    /// It used to be a row of three — setup, the way on, and the sound — and that put the
    /// two controls nobody means to press exactly where a thumb rests when you hold a
    /// phone. Setup and sound have moved into the header. What is left is the only thing
    /// down here somebody is reaching for, and it now gets the whole width.
    ///
    /// "Say it again" is gone from here too. It was a fourth yellow button beside a nearly
    /// identical one, and the question now re-reads itself when tapped, which is where
    /// somebody looks anyway.
    private func footer(_ level: Level) -> some View {
        HStack(spacing: 12) {
            if engine.answeredCorrectly {
                Button {
                    engine.advance()
                } label: {
                    // The same countdown as the fact card, for rounds with no fact to
                    // show — otherwise those move on with no warning at all.
                    Text("Next roll")
                        .appFont(18, weight: .heavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(Meadow.buttonInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Meadow.button, in: Capsule())
                        .overlay { Capsule().strokeBorder(Meadow.buttonEdge, lineWidth: 3) }
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    engine.skip()
                } label: {
                    HStack(spacing: 6) {
                        // Shorter on a phone. Between a gear and a sound switch there is
                        // not room for the whole sentence, and shrinking it ended in
                        // "Show me different…", which is worse than saying less.
                        Text(sizeClass == .regular ? "Show me different photos"
                                                   : "Different photos")
                            .appFont(16, weight: .heavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right")
                            .appFont(13, weight: .black)
                            .opacity(0.5)
                    }
                    .foregroundStyle(Meadow.title)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white.opacity(0.9), in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
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
    let playingCaption: String
    /// Showing its back — the name and what it is known for.
    let isFlipped: Bool
    let onFlip: () -> Void
    let onZoom: () -> Void
    let state: State
    let monochrome: Bool
    let provider: ImageProvider
    let position: Int
    let total: Int
    /// Width over height: wider than tall on an iPad, square on a phone.
    let shape: CGFloat

    @Environment(\.photoHighContrast) private var highContrast
    @Environment(\.photoTextScale) private var textScale
    @SwiftUI.State private var image: UIImage?

    /// The Geography pack's maps. See `front`.
    private var isMap: Bool { photo.packID == "geography" }
    /// The photograph could not be fetched — almost always an iCloud photograph that is
    /// not on this device.
    @SwiftUI.State private var loadFailed = false

    private var isRevealed: Bool { state == .correct || state == .revealed }

    var body: some View {
        front
            // A real turn, not a cross-fade: the card rotates and the back appears at
            // ninety degrees, which is what makes it read as the same card rather than
            // a different one.
            .opacity(isFlipped ? 0 : 1)
            .overlay { if isFlipped { back } }
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 0.45), value: isFlipped)
    }

    /// The photograph's number, so it can be answered out loud.
    ///
    /// Somebody who cannot reliably land a finger on the right tile — a tremor, arthritis,
    /// a hand that no longer does what it is told — can say "two" instead. The number has
    /// to be readable from a lap's distance and never on top of a face, so it sits in the
    /// corner on a solid disc rather than floated over the picture.
    private var numberBadge: some View {
        Text("\(position)")
            .font(.system(size: 22 * textScale, weight: .heavy, design: .rounded))
            .foregroundStyle(Meadow.title)
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.94), in: Circle())
            .overlay { Circle().strokeBorder(Meadow.title.opacity(0.18), lineWidth: 2) }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .padding(10)
            .opacity(isFlipped ? 0 : 1)
            .accessibilityHidden(true)
    }

    /// The back of the card: who or what this is, and what they are known for.
    private var back: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fact = photo.fact {
                FactText(fact: fact, name: photo.title, size: 16 * textScale,
                         bodyColour: highContrast ? Palette.ink(true) : Meadow.body)
            } else if let title = photo.title {
                Text(title)
                    .font(.system(size: 18 * textScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.title)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(highContrast ? AnyShapeStyle(Palette.surface(true))
                                 : AnyShapeStyle(Meadow.cardCream))
        .overlay(alignment: .topLeading) {
            // The way back. The front's button is face-down once the card has turned.
            Button(action: onFlip) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Meadow.title)
                    .padding(8)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the photo")
        }
        .aspectRatio(shape, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.photo - 6, style: .continuous))
        .padding(7)
        .background(.white, in: RoundedRectangle(cornerRadius: Radius.photo,
                                                 style: .continuous))
        .shadow(color: .black.opacity(0.20), radius: 9, y: 5)
        // Flipped back the other way, or the words come out mirrored.
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        .minimumScaleFactor(0.7)
    }

    private var front: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Palette.surface(highContrast))
                // Behind the photograph: the same photograph, blown up and blurred out
                // of legibility. It fills the corners so the card still reads as
                // photo-first, without any of the real picture being cut away.
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(1.25)
                            .blur(radius: 22)
                            .overlay(Color.black.opacity(0.10))
                    }
                }
                // The photograph itself, whole. Cropping to 4:3 took the chin off a
                // portrait and the head off a parrot: a face half in frame is worse
                // than a small face, because the face is what answers the question.
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            // A map fills the tile: it is drawn wider than any tile, with
                            // everything that matters in its middle, so filling only ever
                            // trims surrounding sea and land. A photograph is shown whole.
                            .aspectRatio(contentMode: isMap ? .fill : .fit)
                    } else if loadFailed {
                        // Say so rather than spinning. A photograph that still lives in
                        // iCloud and will not come down is not a slow photograph, and a
                        // card that turns for ever looks like the game has frozen.
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 26, weight: .semibold))
                            Text("Not on this device")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Meadow.muted)
                        .padding(8)
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

            let shown = isRevealed ? caption : playingCaption
            if !shown.isEmpty {
                Text(shown)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.55))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 4:3 on an iPad, where width is the plentiful thing; square on a phone,
        // where it is not.
        .aspectRatio(shape, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.photo - 6, style: .continuous))
        // The collectible-card frame: a thick white border around the photograph rather
        // than cream padding inside it.
        .padding(7)
        .background(cardFrame, in: RoundedRectangle(cornerRadius: Radius.photo,
                                                    style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.photo, style: .continuous)
                .strokeBorder(borderColor, lineWidth: state == .correct ? 5 : 0)
        }
        .overlay(alignment: .bottomLeading) {
            if image != nil, !isFlipped {
                Button(action: onZoom) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Meadow.title)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.88), in: Circle())
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .padding(13)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look closer")
            }
        }
        .shadow(color: .black.opacity(state == .dimmed ? 0.05 : 0.20), radius: 9, y: 5)
        .overlay(alignment: .topTrailing) {
            if state == .correct {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(30)
                    .foregroundStyle(.white, Palette.correct)
                    .padding(10)
            }
        }
        .overlay(alignment: .topLeading) {
            if photo.title != nil {
                Button(action: onFlip) {
                    Image(systemName: isFlipped ? "photo.fill" : "info")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Meadow.title)
                        .frame(width: 30, height: 30)
                        // A translucent white badge sitting on the photograph.
                        .background(.white.opacity(0.88), in: Circle())
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .padding(13)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFlipped ? "Show the photo" : "What is this?")
            }
        }
        .overlay(alignment: .topLeading) { numberBadge }
        .scaleEffect(state == .correct ? 1.02 : 1)
        .task(id: photo.id) {
            loadFailed = false
            // Big enough for a tile on a 13-inch iPad, where a square is about 250pt.
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 400, height: 400))
            loadFailed = image == nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo \(position) of \(total)")
        .accessibilityValue(isRevealed ? caption : playingCaption)
        .accessibilityAddTraits(.isButton)
    }


    /// White, or green once this is the answer, so the frame itself does the announcing.
    private var cardFrame: Color {
        state == .correct ? Meadow.on : .white
    }

    private var borderColor: Color {
        switch state {
        // A white sticker rim, and a bold green one on the answer.
        case .correct: Meadow.on
        case .dimmed: Color.white.opacity(0.6)
        case .revealed: Color.white
        case .idle: Color.white
        }
    }
}

// MARK: - Session complete

/// The way into setup: a gear rather than a row of dots in the top corner, where a
/// caregiver had to be told it existed.
///
/// One tap. It used to take three inside a couple of seconds — a child lock, meant to stop
/// an idle tap opening a screen full of settings. It was removed: the person most likely to
/// be defeated by a gesture nobody told them about is the caregiver who needs the screen,
/// and the setup screen changes nothing a player can come to harm by seeing.
///
/// Its own view because the end-of-session screen needs it too. It used to live inside the
/// play screen, which meant that the moment a session finished the only way into setup
/// disappeared — and the end of a session is exactly when somebody thinks to change
/// something.
struct SettingsGear: View {

    let onOpen: () -> Void
    /// The header size. Smaller than the one the end-of-session screen uses, because up
    /// there it sits beside the sound switch rather than standing on its own.
    var compact = false

    @Environment(\.photoHighContrast) private var highContrast

    var body: some View {
        Button(action: onOpen) {
            Image(systemName: "gearshape.fill")
                .appFont(compact ? 18 : 22, weight: .black)
                .foregroundStyle(highContrast ? Palette.softInk(true) : Meadow.buttonInk)
                .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                .background(highContrast ? AnyShapeStyle(Palette.wash(true))
                                         : AnyShapeStyle(Meadow.button),
                            in: Circle())
                .overlay {
                    if !highContrast { Circle().strokeBorder(Meadow.buttonEdge, lineWidth: 3) }
                }
                .shadow(color: .black.opacity(highContrast ? 0 : 0.18), radius: 5, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Setup")
        .accessibilityHint("Opens setup for photo sources, text size and the daily challenge")
    }
}

/// The Home tab: the first thing anybody sees, and where the game comes back to when the
/// day's challenge is done.
///
/// Laid out after the design Hanna supplied: a welcome, one card for today's round with
/// the one button that matters, and the streak and stars on a single line beneath it.
/// Once the challenge is done the same card says so, and the button plays on.
struct HomeView: View {

    let engine: GameEngine
    let onCaregiverGate: () -> Void
    let onPlay: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var goal: Int { engine.settings.dailyCardGoal }
    private var done: Int { engine.stats.cardsToday }
    private var left: Int { max(goal - done, 0) }
    private var challengeMet: Bool {
        goal > 0 && engine.stats.hasMetChallenge(goal: goal)
    }

    @Environment(\.photoHighContrast) private var highContrast
    @Environment(\.photoTextScale) private var textScale

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        welcome
                        dailyRoundCard
                        statsLine
                        shareCard
                        // The way into setup, as on the play screen.
                        SettingsGear(onOpen: onCaregiverGate)
                    }
                    .readableColumn(maxWidth: 620)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 24)
                    // On an iPad, larger: drawn at phone size it was a small block in a
                    // lot of hill.
                    .scaleEffect(sizeClass == .regular ? 1.3 : 1)
                    // Centred down the screen, on a phone and an iPad alike; anything too
                    // tall to fit still scrolls.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }

            if isAskingForSupport {
                SupportNote {
                    engine.settings.hasAskedAboutSupport = true
                    engine.settings.save()
                    isAskingForSupport = false
                } onSupport: {
                    engine.settings.hasAskedAboutSupport = true
                    engine.settings.save()
                    isAskingForSupport = false
                    Supporting.open()
                }
                .transition(.opacity)
            }
        }
        .task {
            // End of a session, never during one — and never on simply opening the app.
            guard engine.phase == .sessionComplete, Supporting.isAvailable,
                  Supporting.shouldAsk(firstPlayed: engine.stats.stats.firstPlayed,
                                       sessions: engine.stats.stats.totalSessions,
                                       alreadyAsked: engine.settings.hasAskedAboutSupport)
            else { return }
            try? await Task.sleep(for: .seconds(1.2))
            isAskingForSupport = true
        }
        .sheet(isPresented: $isPickingPhotoToShare) {
            PhotoShareSheet(photos: engine.ownPhotosThisSession, provider: engine.images)
        }
    }

    @SwiftUI.State private var isAskingForSupport = false
    @SwiftUI.State private var isPickingPhotoToShare = false

    private var ink: Color { highContrast ? Palette.ink(true) : Meadow.title }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 8) {
            Text(challengeMet ? "Congratulations!" : "Welcome back!")
                .font(.system(size: 44 * textScale, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if challengeMet {
                // Cream on deep sage: green on green was hard to read wherever the line
                // landed on the hills, and cream alone vanished against the pale sky.
                Text("You completed today's challenge!")
                    .font(.system(size: 21 * textScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(highContrast ? Palette.ink(true) : Meadow.buttonInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(highContrast ? Palette.wash(true) : Meadow.button,
                                in: Capsule())
            } else {
                Text(done == 0 ? "Ready for a quick round?" : "Ready for another round?")
                    .font(.system(size: 21 * textScale, design: .rounded))
                    .foregroundStyle(ink.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    // MARK: Daily round

    private var dailyRoundCard: some View {
        HStack(alignment: .center, spacing: 14) {
            PolaroidStack()
                .frame(width: 118, height: 128)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                // The pill sits above the title, at the card's top right, so the two
                // never meet — laid over the corner it covered the end of "Round".
                if goal > 0 {
                    rollsPill.frame(maxWidth: .infinity, alignment: .trailing)
                }
                // On two lines, as in the design: it is the card's name, and big.
                Text("Daily\nRound")
                    .font(.system(size: 36 * textScale, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                    .lineSpacing(-6)
                    .minimumScaleFactor(0.7)
                Text(cardLine)
                    .font(.system(size: 17 * textScale, design: .rounded))
                    .foregroundStyle(ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        Text(buttonTitle)
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 20 * textScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.buttonInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Meadow.button, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(highContrast ? Palette.surface(true) : Meadow.cardCream,
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
    }

    private var cardLine: String {
        if goal == 0 { return "Play for as long as you like." }
        if challengeMet { return "All done for today. Well played!" }
        if done == 0 { return "Your challenge is ready." }
        // "Nearly there" only when it is true — it said so with seven of eight to go.
        if left <= max(2, goal / 4) { return "Keep going — you're nearly there." }
        return done == 1 ? "You've made a start." : "\(done) done, \(left) to go."
    }

    private var buttonTitle: String {
        if challengeMet { return "Play more" }
        return done == 0 ? "Play today" : "Keep playing"
    }

    /// "8 rolls left" on a die, or a tick once the challenge is done.
    private var rollsPill: some View {
        HStack(spacing: 8) {
            Image(systemName: challengeMet ? "checkmark.circle.fill" : "dice.fill")
                .font(.system(size: 22 * textScale, weight: .bold))
            VStack(alignment: .leading, spacing: -2) {
                Text(challengeMet ? "Done" : "\(left)")
                    .font(.system(size: 22 * textScale, weight: .black, design: .rounded))
                Text(challengeMet ? "for today" : left == 1 ? "roll left" : "rolls left")
                    .font(.system(size: 12 * textScale, design: .rounded))
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(highContrast ? Palette.wash(true) : Meadow.onWash, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(challengeMet ? "Today's challenge is done"
                            : "\(left) \(left == 1 ? "roll" : "rolls") left today")
    }

    // MARK: Streak and stars

    private var statsLine: some View {
        HStack(spacing: 0) {
            stat(symbol: "flame.fill", tint: Meadow.flame,
                 value: engine.stats.dayStreak,
                 label: engine.stats.dayStreak == 1 ? "day streak" : "days streak")
            Rectangle()
                .fill(Meadow.muted.opacity(0.3))
                .frame(width: 1, height: 38)
            stat(symbol: "star.fill", tint: Meadow.sparkle,
                 value: engine.stats.starsToday,
                 label: engine.stats.starsToday == 1 ? "star" : "stars")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(highContrast ? Palette.surface(true) : Meadow.cardCream,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func stat(symbol: String, tint: Color, value: Int, label: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26 * textScale, weight: .bold))
                .foregroundStyle(highContrast ? Palette.ink(true) : tint)
            Text("\(value)")
                .font(.system(size: 38 * textScale, weight: .black, design: .rounded))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 18 * textScale, design: .rounded))
                .foregroundStyle(ink.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Share

    @ViewBuilder
    private var shareCard: some View {
        if !engine.ownPhotosThisSession.isEmpty {
            StickerCard(fill: highContrast ? Palette.wash(true) : Meadow.cardLavender) {
                HStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24 * textScale, weight: .black))
                        .foregroundStyle(highContrast ? Palette.ink(true) : Meadow.clay)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep the moment")
                            .font(.system(size: 18 * textScale, weight: .heavy, design: .rounded))
                            .foregroundStyle(highContrast ? Palette.ink(true) : Meadow.title)
                        Text("Send one of today's photos to somebody.")
                            .font(.system(size: 14 * textScale, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { isPickingPhotoToShare = true } label: {
                        Text("Share")
                            .font(.system(size: 17 * textScale, weight: .heavy, design: .rounded))
                            .foregroundStyle(Meadow.buttonInk)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Meadow.button, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share a photo from today")
                }
            }
        }
    }

}

/// Two snapshots, one on top of the other, with a smiling sun in the front one — the
/// picture on the Daily Round card.
private struct PolaroidStack: View {

    var body: some View {
        ZStack {
            print(sky: Meadow.cardMint)
                .rotationEffect(.degrees(-12))
                .offset(x: -12, y: 6)
            print(sky: Color.hex(0xDCE6E6), front: true)
                .rotationEffect(.degrees(4))
                .offset(x: 8, y: 0)
            // A few strokes of shine around the corner, as in the drawing.
            ForEach(0..<3) { index in
                Capsule()
                    .fill(Meadow.badgeWalnut)
                    .frame(width: 3, height: 11)
                    .rotationEffect(.degrees([-40.0, -10, 25][index]))
                    .offset(x: [-52.0, -36, -16][index], y: [-50.0, -60, -64][index])
            }
            ForEach(0..<2) { index in
                Capsule()
                    .fill(Meadow.badgeWalnut)
                    .frame(width: 3, height: 11)
                    .rotationEffect(.degrees([60.0, 30][index]))
                    .offset(x: [-56.0, -48][index], y: [40.0, 54][index])
            }
        }
    }

    private func print(sky: Color, front: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.hex(0xFDFBF5))
            .frame(width: 82, height: 96)
            .overlay(alignment: .top) {
                ZStack(alignment: .bottom) {
                    sky
                    // Two soft hills.
                    Ellipse().fill(Meadow.badgeOlive.opacity(0.8))
                        .frame(width: 70, height: 34).offset(x: -18, y: 14)
                    Ellipse().fill(Meadow.badgeSage.opacity(0.85))
                        .frame(width: 80, height: 30).offset(x: 20, y: 16)
                    if front { SunFace().offset(y: -26) }
                }
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(.top, 6)
            }
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    }
}

private struct SunFace: View {
    var body: some View {
        ZStack {
            ForEach(0..<8) { ray in
                Capsule()
                    .fill(Meadow.sparkle)
                    .frame(width: 2.5, height: 6)
                    .offset(y: -16)
                    .rotationEffect(.degrees(Double(ray) * 45))
            }
            Circle().fill(Meadow.sparkle.opacity(0.85)).frame(width: 22, height: 22)
            HStack(spacing: 5) {
                Circle().fill(Meadow.walnut).frame(width: 2.5, height: 2.5)
                Circle().fill(Meadow.walnut).frame(width: 2.5, height: 2.5)
            }
            .offset(y: -2)
            Circle()
                .trim(from: 0.1, to: 0.4)
                .stroke(Meadow.walnut, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 9, height: 9)
                .offset(y: 1)
        }
    }
}

/// A photograph in a white border, like a print.
private struct Snapshot: View {
    let photo: GamePhoto
    let provider: ImageProvider
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Vision says where the eye goes; the crop keeps that rather than
                    // the middle of the frame, which on a portrait is somebody's chest.
                    .alignmentGuideForSubject(photo.subjectArea)
            } else {
                Color.white.opacity(0.6)
            }
        }
        .frame(width: 104, height: 104)
        .clipped()
        .padding(7)
        .padding(.bottom, 14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
        .task(id: photo.id) {
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 320, height: 320))
        }
    }
}

// MARK: - Did you know?

/// The fact, full screen, with the photograph they just found.
///
/// It takes the whole screen on purpose. The strip version sat under the grid and read as
/// a footnote; this is meant to be the reward for getting it right, so it gets the room —
/// and it carries the photograph, because the sentence is about that picture.
struct FactPopup: View {

    let photo: GamePhoto
    let fact: String
    let provider: ImageProvider
    let highContrast: Bool
    let textScale: Double
    let onSeePhotos: () -> Void
    let onContinue: () -> Void

    @State private var image: UIImage?

    /// Chosen by the photograph rather than at random, so it does not change under the
    /// reader's eyes when the view redraws.
    private var praise: String {
        let lines = ["Correct!", "Great job!", "Way to go!", "That's the one!", "Nicely done!"]
        return lines[Int(photo.id.hashValue64 % UInt64(lines.count))]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { onSeePhotos() }

            ScrollView {
                VStack(spacing: 14) {
                    // The praise gets its own box above the fact, so "Way to go!" reads
                    // as the answer to what they just did rather than as a heading on
                    // the paragraph underneath it.
                    Text(praise)
                        .font(.system(size: 30 * textScale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Meadow.on,
                                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white, lineWidth: 3)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                    factCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .readableColumn(maxWidth: 560)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: photo.id) {
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 900, height: 900))
        }
        .accessibilityAddTraits(.isModal)
    }

    private var factCard: some View {
        VStack(spacing: 16) {
                    photograph

                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Meadow.sparkle, in: Circle())
                            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                        Text("Did you know?")
                            .font(.system(size: 26 * textScale, weight: .heavy,
                                          design: .rounded))
                            .foregroundStyle(Meadow.title)
                        Spacer(minLength: 0)
                    }

                    FactText(fact: fact,
                             name: photo.title,
                             size: 20 * textScale,
                             bodyColour: highContrast ? Palette.ink(true) : Meadow.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onContinue) {
                        Text("Next roll")
                            .font(.system(size: 22 * textScale, weight: .heavy,
                                          design: .rounded))
                            .foregroundStyle(Meadow.buttonInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Meadow.button,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Meadow.buttonEdge, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Button(action: onSeePhotos) {
                        Text("Look at the photos")
                            .font(.system(size: 17 * textScale, weight: .semibold,
                                          design: .rounded))
                            .foregroundStyle(Meadow.title)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(highContrast ? AnyShapeStyle(Palette.surface(true))
                                         : AnyShapeStyle(Meadow.cardCream),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private var photograph: some View {
        Group {
            if let image {
                if photo.packID == "geography" {
                    // A map fills the frame — its middle is what matters, and fitting it
                    // left bars of card colour down each side.
                    Color.clear
                        .frame(height: 280)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                ProgressView().frame(height: 140)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white, lineWidth: 4)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

// MARK: - The fact, with its subject picked out

/// A sourced sentence with the thing it is about set in bold navy.
///
/// The name used to be printed above the sentence and then again inside it — "Herbert
/// Hoover" as a heading, then "Herbert Clark Hoover was the 31st president…". Saying it
/// twice wastes the line and puts a gap where the eye expects to keep reading, so the
/// heading is gone and the name is picked out where it already appears.
struct FactText: View {

    let fact: String
    /// What the card is called. The name is the thing to pick out, and only the card
    /// knows it: Nellie Bly's sentence opens "Elizabeth Cochrane Seaman…", so guessing
    /// from the sentence alone bolds a name the player has never heard.
    var name: String?
    var size: CGFloat
    var bodyColour: Color

    var body: some View {
        Text(highlighted)
            .font(.system(size: size, design: .rounded))
            .foregroundStyle(bodyColour)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var highlighted: AttributedString {
        var text = AttributedString(fact)
        guard let range = nameRange ?? Self.subjectRange(of: fact),
              let attributed = Range(range, in: text) else { return text }
        text[attributed].font = .system(size: size, weight: .heavy, design: .rounded)
        text[attributed].foregroundColor = Meadow.title
        return text
    }

    /// The card's own name where the sentence says it, whole word and any case. A
    /// pack title carries a leading article the sentence often drops — the card says
    /// "The Acropolis", the sentence says "Acropolis of Athens" — so that comes off
    /// before looking.
    private var nameRange: Range<String.Index>? {
        guard let name else { return nil }
        var candidates = [name]
        for article in ["The ", "A ", "An "] where name.hasPrefix(article) {
            candidates.append(String(name.dropFirst(article.count)))
        }
        for candidate in candidates where candidate.count > 2 {
            if let found = fact.range(of: candidate, options: .caseInsensitive) {
                return found
            }
        }
        // Wikipedia opens with the full name, so the card's "Louis Armstrong" is not in
        // "Louis Daniel Armstrong" as written. Allow a word or two in between.
        for candidate in candidates {
            let words = candidate.split(separator: " ")
            guard words.count >= 2, let first = words.first, let last = words.last else {
                continue
            }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: String(first)))"
                + "(?: [\\p{L}.'-]+){0,2} "
                + NSRegularExpression.escapedPattern(for: String(last)) + "\\b"
            if let found = fact.range(of: pattern, options: [.regularExpression,
                                                             .caseInsensitive]) {
                return found
            }
        }
        return nil
    }

    /// The subject of the opening sentence: everything before the verb that follows it.
    /// Wikipedia's first sentence is reliably "X is/was/are/were …", which is exactly
    /// the shape this needs — "The Colosseum is an elliptical amphitheatre",
    /// "Grasshoppers are a group of insects".
    private static func subjectRange(of fact: String) -> Range<String.Index>? {
        for verb in [" is ", " was ", " are ", " were "] {
            if let found = fact.range(of: verb), found.lowerBound != fact.startIndex {
                return fact.startIndex ..< found.lowerBound
            }
        }
        return nil
    }
}

// MARK: - A closer look

/// One photograph, as large as the screen allows.
/// One of the two buttons under a zoomed photograph.
private func zoomAction(_ title: String, symbol: String,
                        action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 19, weight: .black))
            Text(title).font(.system(size: 19, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Meadow.accentInk)
        .padding(.horizontal, 22)
        .frame(height: 54)
        .background(.white, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
}

struct ZoomView: View {

    let photo: GamePhoto
    let provider: ImageProvider
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var isSharing = false
    @State private var savedNote: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
                .onTapGesture { onClose() }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Meadow.title)
                            .frame(width: 42, height: 42)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .padding(18)
                }
                Spacer()

                // Sharing lives here rather than on the tile: the photograph is already
                // open and full size, and a pack photograph has only been fetched at all
                // because somebody chose to look at it.
                if let image {
                    HStack(spacing: 14) {
                        zoomAction("Share", symbol: "square.and.arrow.up") {
                            isSharing = true
                        }
                        zoomAction("Save", symbol: "arrow.down.circle") {
                            Task {
                                let saved = await SharePhoto.save(image)
                                savedNote = saved ? "Saved to your photos"
                                                  : "Time Rolls could not save it"
                            }
                        }
                    }
                    .padding(.bottom, 28)
                }

                if let savedNote {
                    Text(savedNote)
                        .appFont(17, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            if let image {
                // The credit goes with it. Most pack photographs are CC BY or CC BY-SA,
                // which allow exactly this on condition the photographer is named, so
                // sending one on without the credit would be the app breaking the licence
                // on somebody's behalf. Their own photographs carry nothing.
                ShareSheet(items: [image] + (SharePhoto.credit(for: photo).map { [$0] } ?? []))
            }
        }
        .task(id: photo.id) {
            // Bigger than a tile needs: this one is meant to be looked at.
            image = await provider.image(for: photo,
                                         targetSize: CGSize(width: 1400, height: 1400))
        }
    }
}


// Not private any more: the share sheet crops the same photographs to the same kind of
// square, and cropping one of them to its middle instead of to its subject is how a
// portrait becomes a picture of somebody's chest.
extension View {
    /// Shifts a filled image so the salient part of the photograph sits in the middle
    /// of whatever box it is being cropped to. A no-op when Vision found nothing to
    /// point at, which is the right answer for a landscape.
    @ViewBuilder
    func alignmentGuideForSubject(_ area: SubjectArea?) -> some View {
        if let area {
            let horizontal = (area.centreX - 0.5) * 2
            let vertical = (area.centreY - 0.5) * 2
            self.scaleEffect(1.15)
                .offset(x: -horizontal * 18, y: -vertical * 18)
        } else {
            self
        }
    }
}

// MARK: - Supporting the app

/// The one-time note about supporting Time Rolls.
///
/// It appears at the end of a session, never during one, and never more than once in the
/// life of the app. The wording is addressed to whoever set the game up rather than to
/// the player, because the player may be somebody who cannot remember whether they have
/// already given and should not be asked in the first place.
struct SupportNote: View {

    let onDismiss: () -> Void
    let onSupport: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            StickerCard(fill: Meadow.cardCream) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "heart.fill", tint: Meadow.badgeRose)
                        Text("Enjoying Time Rolls?")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Meadow.title)
                    }
                    Text("It's free, and it stays free. If it has been good company, a "
                       + "donation helps us keep building it and keep supporting the "
                       + "people using it.")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Meadow.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onSupport) {
                        MeadowButtonLabel(title: "Find out how", symbol: "heart.fill")
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("Not just now")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Meadow.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    Text("You'll only see this once.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Meadow.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 26)
            .readableColumn(maxWidth: 480)
        }
        .accessibilityAddTraits(.isModal)
    }
}
