//
//  RootView.swift
//  Time Rolls
//
//  The app opens straight into play — no login, no splash beyond the one-time
//  first-run flow (spec §3.2, §7.1).
//

import SwiftUI

struct RootView: View {

    @State private var engine = GameEngine()
    @State private var isShowingCaregiver = false
    /// Somebody asked to start before the first pass had finished. Remembered for the
    /// session so the screen does not come back between rounds.
    @State private var hasSkippedIndexing = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let highContrast = engine.settings.highContrast

        ZStack {
            // The painted meadow. Under extra contrast it drops back to flat paper —
            // an illustrated sky behind the content is the first thing to go for
            // somebody who needs every bit of separation the screen can give.
            if highContrast {
                Palette.background(true).ignoresSafeArea()
            } else {
                MeadowBackdrop()
            }

            switch engine.phase {
            case .firstRun:
                FirstRunView(engine: engine)
            case .preparing:
                PreparingView()
            case .playing:
                // Only while there is genuinely a lot still to look at, and only until
                // somebody says otherwise. A short wait is not worth a screen.
                if !hasSkippedIndexing,
                   let progress = engine.objects.progress,
                   progress < 0.9, engine.objects.stillToExamine >= 200 {
                    GettingReadyView(engine: engine) { hasSkippedIndexing = true }
                } else {
                    PlayView(engine: engine) { isShowingCaregiver = true }
                }
            case .sessionComplete:
                SessionCompleteView(engine: engine) { isShowingCaregiver = true }
            case let .noContent(reason):
                NoContentView(engine: engine, reason: reason) { isShowingCaregiver = true }
            }
        }
        // An iPad is held further away and has the room, so everything comes up a size —
        // but a gentle size. At 1.3 it compounded with the caregiver's own choice and
        // "Largest" on an iPad came out at nearly twice the drawn size, which is not
        // large, it is broken.
        .environment(\.photoTextScale,
                     engine.settings.textScale.multiplier * (sizeClass == .regular ? 1.12 : 1.0))
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
        // Hold the session still while setup is open. Whoever opened it is not watching
        // the game, and the player is watching somebody else use the iPad.
        .onChange(of: isShowingCaregiver) { _, isOpen in
            if isOpen { engine.pause() } else { engine.resume() }
        }
    }
}

// MARK: - Preparing

struct PreparingView: View {

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Choosing some photos…")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Meadow.title)
        }
    }
}

// MARK: - First run

/// The wordmark: bold, italic, deep sage (§4 of the design file).
///
/// Set in mixed case rather than the all-caps of the chess wordmark it comes from,
/// because the capital Y in the middle is the name — "YESTERYEAR" throws it away. The
/// ink is `#35452D`, held at that value in both contrast modes: a wordmark is the one
/// place in the app where the colour *is* the identity, and it clears 9:1 on the launch
/// cream either way.
struct Wordmark: View {

    var size: CGFloat = 40

    var body: some View {
        Text("Time Rolls")
            // The default face, not the rounded one the rest of the app uses: SF Rounded
            // has no true italic and SwiftUI will not fake one, so `.italic()` was
            // silently doing nothing. The design file asks for bold italic and names
            // Helvetica Neue Bold Italic as the non-SF substitute — this is that shape.
            .font(.system(size: size, weight: .bold, design: .default))
            .italic()
            .kerning(0.5)
            .foregroundStyle(Color.hex(0x35452D))
            .accessibilityAddTraits(.isHeader)
    }
}

struct FirstRunView: View {

    let engine: GameEngine
    @State private var isRequesting = false

    /// Where somebody is in the first run.
    ///
    /// Reading aloud and answering out loud used to live only in caregiver setup, behind
    /// a child lock, three screens down — which is a fine place for a setting nobody needs
    /// and the wrong place entirely for the two that decide whether somebody can play at
    /// all. They are asked here instead, once, while the person setting the game up is
    /// still sitting with it.
    private enum Stage { case intro, choosingPhotos, voice, challenge, movingOn }
    @State private var stage: Stage = .intro

    var body: some View {
        switch stage {
        case .choosingPhotos:
            CategoryChooserView(engine: engine) { packIDs in
                engine.applyOnboardingChoice(packIDs: packIDs)
                stage = .voice
            }
        case .voice:
            VoiceSetupView(engine: engine) { stage = .challenge }
        case .challenge:
            DailyChallengeSetupView(engine: engine) { stage = .movingOn }
        case .movingOn:
            MovingOnView(engine: engine) {
                Task { await engine.completeFirstRun() }
            }
        case .intro:
            // No separate cream ground any more — the first screen sits on the same
            // painted meadow as the rest of the app.
            intro
        }
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Wordmark()
                    Text("A gentle photo game for all ages.")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(Meadow.title.opacity(0.85))
                }

                // The three promises, on the same sticker cards as the rest of the app
                // rather than as a plain bulleted list.
                StickerCard(fill: Meadow.cardCream) {
                    VStack(alignment: .leading, spacing: 14) {
                        Bullet(symbol: "photo.on.rectangle.angled", tint: .hex(0x8B8BE8),
                               title: "Your photos, a few at a time",
                               detail: "Each round shows a handful of photos and asks one easy question about them.")
                        Bullet(symbol: "hand.tap.fill", tint: .hex(0xF3A05A),
                               title: "Just tap a photo",
                               detail: "There's no score, no timer, and no wrong turn you can't take back.")
                        Bullet(symbol: "lock.shield.fill", tint: .hex(0x7FC98A),
                               title: "Photos stay on this device",
                               detail: "Your photos never leave this device. To spot things like "
                                    + "a dog or a cake, it looks at them here, on the device "
                                    + "itself. Only GPS coordinates are sent, to name a place, "
                                    + "and only once per location.")
                    }
                }

                VStack(spacing: 14) {
                    Button {
                        Task {
                            isRequesting = true
                            await engine.requestPhotoAccess()
                            isRequesting = false
                            stage = .voice
                        }
                    } label: {
                        MeadowButtonLabel(title: isRequesting ? "One moment…" : "Use my photos",
                                          symbol: "photo.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting)

                    Button {
                        stage = .choosingPhotos
                    } label: {
                        Text("Play with the built-in photos instead")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Meadow.title)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.8), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)

                Text(ClaimLanguage.standingDisclaimer)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Meadow.body.opacity(0.85))
            }
            .padding(24)
            .readableColumn(maxWidth: 620)
        }
    }

}

/// An icon, a heading and a line of explanation — the shape the first-run screens
/// explain themselves in.
struct Bullet: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Meadow.title)
                Text(detail)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Meadow.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Nothing to play

struct NoContentView: View {

    let engine: GameEngine
    let reason: String
    let onCaregiverGate: () -> Void


    var body: some View {
        VStack(spacing: 20) {
            StickerCard(fill: Meadow.cardCream) {
                VStack(spacing: 12) {
                    IconBadge(symbol: "photo.stack.fill", tint: .hex(0xF3A05A))
                    Text("Let's find some photos")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Meadow.title)
                        .multilineTextAlignment(.center)
                    Text(reason)
                        .font(.system(size: 16, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Meadow.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                if !engine.library.access.canRead {
                    Button {
                        Task {
                            await engine.requestPhotoAccess()
                            await engine.prepare()
                        }
                    } label: {
                        MeadowButtonLabel(title: "Allow photo access", symbol: "photo.fill")
                    }
                    .buttonStyle(.plain)
                }
                secondary("Open setup", action: onCaregiverGate)
                secondary("Try again") { Task { await engine.prepare() } }
            }
        }
        .padding(28)
        .readableColumn(maxWidth: 620)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Meadow.title)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.white.opacity(0.8), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Child lock

/// Setup is reached by tapping the same spot three times, and that is the whole gate.
///
/// It used to be one tap onto a "Setting this up for someone else?" card with a Yes and a
/// No. That is a fine gate for a stranger and a poor one for the person holding the iPad:
/// it is one tap away, and it explains itself. Three deliberate taps is the pattern people
/// already know from child locks — it asks for intent rather than for an answer, and it
/// says nothing to somebody who taps it once by accident.
struct CaregiverGateSheet: View {

    let engine: GameEngine

    var body: some View {
        CaregiverHubView(engine: engine)
            .presentationDetents([.large])
            .presentationSizing(.page)
    }
}

// MARK: - Reading and answering aloud, asked once at the start

/// The two questions that decide whether somebody can play at all.
///
/// Both of these used to live in caregiver setup: behind a child lock, three screens in,
/// under a heading nobody opens unless they already know it is there. That is the right
/// place for the black-and-white lever and the wrong place for these — a person who cannot
/// read the question, or cannot reliably land a finger on a tile, does not need a setting
/// so much as they need somebody to have been asked on their behalf, once, while the game
/// was being set up.
///
/// So it is asked here, in plain words, with the answer to "no thanks" being exactly as
/// respectable as the answer to yes. Everything is still changeable later in Setup.
struct VoiceSetupView: View {

    @Bindable var engine: GameEngine
    let onDone: () -> Void

    @State private var isAsking = false

    private var bestVoice: String? {
        engine.narrator.available.first.map { "\($0.name) · \($0.quality)" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One last thing")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Meadow.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("Some people find the words harder than the photos. You can "
                       + "change any of this later.")
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(Meadow.body)
                }

                StickerCard(fill: Meadow.cardCream) {
                    VStack(alignment: .leading, spacing: 12) {
                        Bullet(symbol: "speaker.wave.2.fill", tint: .hex(0x5AA9E6),
                               title: "Read the question aloud",
                               detail: "Each round begins by reading its question out. "
                                    + "There's a big button to hear it again.")
                        Toggle(isOn: $engine.settings.narration) {
                            Text(engine.settings.narration ? "Yes, read it aloud" : "No thanks")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Meadow.title)
                        }
                        .tint(Color.hex(0x5FA86B))
                        if engine.settings.narration, let bestVoice {
                            Text("Using \(bestVoice). Setup has the other voices, and how "
                               + "to download a warmer one.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Meadow.muted)
                        }
                    }
                }

                StickerCard(fill: Meadow.cardMint) {
                    VStack(alignment: .leading, spacing: 12) {
                        Bullet(symbol: "mic.fill", tint: .hex(0x5FA86B),
                               title: "Answer out loud",
                               detail: "Every photo is numbered. Saying \"two\" picks the "
                                    + "second one — useful for hands that find tapping "
                                    + "hard. Tapping always works too.")
                        switch engine.voiceAnswers.permission {
                        case .allowed:
                            Toggle(isOn: $engine.settings.voiceAnswers) {
                                Text(engine.settings.voiceAnswers
                                     ? "Yes, let them answer out loud" : "No thanks")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(Meadow.title)
                            }
                            .tint(Color.hex(0x5FA86B))
                        case .notAsked:
                            Button {
                                Task {
                                    isAsking = true
                                    await engine.voiceAnswers.requestPermission()
                                    // Saying yes to the microphone is saying yes to the
                                    // feature — nobody grants it meaning to leave it off.
                                    if engine.voiceAnswers.permission == .allowed {
                                        engine.settings.voiceAnswers = true
                                    }
                                    isAsking = false
                                }
                            } label: {
                                MeadowButtonLabel(title: isAsking ? "One moment…"
                                                                  : "Yes, use the microphone",
                                                  symbol: "mic.fill")
                            }
                            .buttonStyle(.plain)
                            .disabled(isAsking)
                        case .refused:
                            Text("The microphone is off for Time Rolls. Settings → Privacy "
                               + "& Security → Microphone, whenever you like.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Meadow.muted)
                        case .unavailable:
                            Text("This device can't recognise speech without sending it "
                               + "away, so this stays off. Nothing said in the room leaves "
                               + "the device.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Meadow.muted)
                        }
                    }
                }

                Button {
                    engine.settings.save()
                    onDone()
                } label: {
                    MeadowButtonLabel(title: "Next", symbol: "arrow.right")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .readableColumn(maxWidth: 620)
        }
        .task {
            engine.voiceAnswers.refreshPermission()
            engine.narrator.refreshPersonalVoiceStatus()
        }
    }
}

/// How much of a day the game should ask for.
///
/// Asked during setup rather than buried in caregiver settings, because it is the one
/// number that decides what playing this game feels like. Too high and the challenge is
/// something to fail; too low and finishing means nothing. It is also the only thing in
/// the app a person can fall short of, which is why the wording never mentions failing and
/// why the smallest option is offered first and described as a real choice rather than a
/// lesser one.
struct DailyChallengeSetupView: View {

    @Bindable var engine: GameEngine
    let onDone: () -> Void

    /// Three sizes of day. Not a slider: a slider invites somebody to optimise a number
    /// that should be chosen once, by feel, and forgotten.
    private static let choices: [(cards: Int, name: String, detail: String)] = [
        (5, "A short visit", "About five minutes. A good place to start, and enough on a "
                           + "day when somebody is tired."),
        (8, "A proper sit-down", "Ten minutes or so. Long enough to settle into, short "
                               + "enough to finish."),
        (12, "A good long session", "Twenty minutes. For somebody who would rather keep "
                                  + "going than be asked to stop."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's challenge")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Meadow.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("Each day has a small challenge to finish. How many photo cards "
                       + "should it take? You can change this later, and there's no hurry "
                       + "— the day lasts as long as it lasts.")
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(Meadow.body)
                }

                ForEach(Self.choices, id: \.cards) { choice in
                    Button {
                        engine.settings.dailyCardGoal = choice.cards
                        engine.settings.save()
                    } label: {
                        StickerCard(fill: engine.settings.dailyCardGoal == choice.cards
                                    ? Meadow.cardMint : Meadow.cardCream) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: engine.settings.dailyCardGoal == choice.cards
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundStyle(engine.settings.dailyCardGoal == choice.cards
                                                     ? Color.hex(0x5FA86B) : Meadow.muted)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(choice.name) · \(choice.cards) cards")
                                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Meadow.title)
                                    Text(choice.detail)
                                        .font(.system(size: 15, design: .rounded))
                                        .foregroundStyle(Meadow.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(engine.settings.dailyCardGoal == choice.cards
                                            ? [.isButton, .isSelected] : .isButton)
                }

                Text("Finishing the challenge is the only thing the game keeps score of, "
                   + "and it can be finished across the whole day. Afterwards the game "
                   + "carries on for as long as anybody wants to play.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Meadow.muted)
                    .fixedSize(horizontal: false, vertical: true)

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
    }
}

// MARK: - Getting the photos ready

/// Shown while the first pass over a library is still running (spec §8).
///
/// Looking at a few thousand photographs takes real time on an older iPad, and until it
/// finishes the game can only draw on the part it has seen. Without this screen that looks
/// like an app with hardly any photographs in it — a much worse first impression than
/// being asked to wait, and one nobody would report as a bug because nothing is visibly
/// wrong.
///
/// It is never a wall. The button is there from the first second, because somebody who
/// wants to play now should be allowed to, and a smaller set of photographs is a real
/// game rather than a broken one.
struct GettingReadyView: View {

    let engine: GameEngine
    let onPlayAnyway: () -> Void

    private var done: Int { engine.objects.examinedThisPass }
    private var total: Int { engine.objects.stillToExamine }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("Getting your photos ready")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Meadow.title)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Looking through them here on this device, so the questions can "
                       + "be about what's actually in them. It only happens once.")
                        .font(.system(size: 17, design: .rounded))
                        .foregroundStyle(Meadow.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StickerCard(fill: Meadow.cardCream) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.hex(0x5FA86B).opacity(0.22), lineWidth: 12)
                            Circle()
                                .trim(from: 0, to: engine.objects.progress ?? 0)
                                .stroke(Color.hex(0x5FA86B),
                                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeOut(duration: 0.4),
                                           value: engine.objects.progress ?? 0)
                            VStack(spacing: 0) {
                                Text("\(Int((engine.objects.progress ?? 0) * 100))%")
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Meadow.title)
                                    .monospacedDigit()
                                if total > 0 {
                                    Text("\(done) of \(total)")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(Meadow.muted)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .frame(width: 150, height: 150)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(total > 0
                                            ? "\(done) of \(total) photos looked at"
                                            : "Getting your photos ready")

                        Text("Your photos never leave this device.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.hex(0x1F6B43))
                    }
                }

                Button(action: onPlayAnyway) {
                    MeadowButtonLabel(title: "Start playing now", symbol: "play.fill")
                }
                .buttonStyle(.plain)

                Text("You can start now — there will simply be fewer photos to choose "
                   + "from until this finishes.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Meadow.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .readableColumn(maxWidth: 560)
        }
    }
}
