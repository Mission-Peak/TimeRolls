//
//  MeadowTheme.swift
//  Time Rolls
//
//  The illustrated "meadow" look: a painted sky-and-hills page, sticker cards in pastel
//  fills with soft shadows, rounded-heavy headings in deep navy, and badge icons that sit
//  on the card like stickers.
//
//  Drawn rather than shipped as art. The reference is painted — hand-lettered headings,
//  illustrated camera and paw stickers, a wooden Done button — and none of that art
//  exists in the project, so the scene here is built from SwiftUI shapes and SF Symbols.
//  It gets the colour, the depth and the layout; it cannot get the brush.
//

import SwiftUI

enum Meadow {

    // MARK: Sky and land

    static let skyTop = Color.hex(0x6FC2EC)
    static let skyBottom = Color.hex(0xCFEAF8)
    static let cloud = Color.white.opacity(0.92)
    static let sun = Color.hex(0xFFD34E)

    static let hillFar = Color.hex(0x9FD98A)
    static let hillMid = Color.hex(0x74C55A)
    static let hillNear = Color.hex(0x53AC46)
    static let river = Color.hex(0x6BC3E8)
    static let tree = Color.hex(0x3F9A45)
    static let treeDark = Color.hex(0x2F7D38)

    // MARK: Cards

    static let cardCream = Color.hex(0xFDF7E8)
    static let cardLavender = Color.hex(0xEFE9FC)
    static let cardMint = Color.hex(0xE2F5E9)
    static let cardSky = Color.hex(0xE2F0FC)
    static let cardRim = Color.white.opacity(0.9)

    // MARK: Ink

    static let title = Color.hex(0x1B3A6B)
    static let body = Color.hex(0x35455C)
    static let muted = Color.hex(0x6D7E95)

    // MARK: Controls

    static let wood = Color.hex(0xF2C368)
    static let woodEdge = Color.hex(0xC2903B)
    static let woodInk = Color.hex(0x6A4718)
    static let sparkle = Color.hex(0xFFC93C)
    static let on = Color.hex(0x3DBE6E)

    static let radius: CGFloat = 26
}

// MARK: - Backdrop

/// Sky, sun, clouds, three ridges of hill, a river and a line of trees.
struct MeadowBackdrop: View {

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [Meadow.skyTop, Meadow.skyBottom],
                               startPoint: .top, endPoint: .bottom)

                Canvas { context, canvas in
                    let w = canvas.width
                    let h = canvas.height

                    context.fill(Circle().path(in: CGRect(x: w * 0.72, y: h * 0.055,
                                                          width: 46, height: 46)),
                                 with: .color(Meadow.sun))
                    for ray in 0..<8 {
                        let angle = Double(ray) / 8 * 2 * .pi
                        let centre = CGPoint(x: w * 0.72 + 23, y: h * 0.055 + 23)
                        var mark = Path()
                        mark.move(to: CGPoint(x: centre.x + cos(angle) * 32,
                                              y: centre.y + sin(angle) * 32))
                        mark.addLine(to: CGPoint(x: centre.x + cos(angle) * 42,
                                                 y: centre.y + sin(angle) * 42))
                        context.stroke(mark, with: .color(Meadow.sun),
                                       style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }

                    for cloud in [(0.12, 0.05, 1.0), (0.46, 0.10, 0.7), (0.86, 0.15, 0.85)] {
                        context.fill(puff(at: CGPoint(x: w * cloud.0, y: h * cloud.1),
                                          scale: cloud.2),
                                     with: .color(Meadow.cloud))
                    }

                    // Three ridges, far to near, so the land has depth.
                    context.fill(ridge(w: w, h: h, top: 0.30, crest: 0.30, lift: 0.055),
                                 with: .color(Meadow.hillFar))
                    context.fill(ridge(w: w, h: h, top: 0.36, crest: 0.72, lift: 0.070),
                                 with: .color(Meadow.hillMid))

                    // The river runs down out of the far hills.
                    var water = Path()
                    water.move(to: CGPoint(x: w * 0.80, y: h * 0.33))
                    water.addQuadCurve(to: CGPoint(x: w * 1.02, y: h * 0.48),
                                       control: CGPoint(x: w * 0.86, y: h * 0.42))
                    context.stroke(water, with: .color(Meadow.river),
                                   style: StrokeStyle(lineWidth: 12, lineCap: .round))

                    context.fill(ridge(w: w, h: h, top: 0.86, crest: 0.42, lift: 0.055),
                                 with: .color(Meadow.hillNear))

                    for spot in [(0.70, 0.315), (0.79, 0.300), (0.88, 0.318), (0.95, 0.305)] {
                        context.fill(conifer(at: CGPoint(x: w * spot.0, y: h * spot.1),
                                             height: 34),
                                     with: .color(Meadow.tree))
                    }
                    for spot in [(0.06, 0.885), (0.18, 0.900)] {
                        context.fill(conifer(at: CGPoint(x: w * spot.0, y: h * spot.1),
                                             height: 26),
                                     with: .color(Meadow.treeDark))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ridge(w: CGFloat, h: CGFloat, top: CGFloat,
                       crest: CGFloat, lift: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: h * top))
            path.addQuadCurve(to: CGPoint(x: w, y: h * (top - lift * 0.4)),
                              control: CGPoint(x: w * crest, y: h * (top - lift)))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
    }

    private func puff(at centre: CGPoint, scale: CGFloat) -> Path {
        Path { path in
            for blob in [(-26.0, 4.0, 20.0), (0.0, -6.0, 26.0), (26.0, 4.0, 18.0)] {
                let r = blob.2 * scale
                path.addEllipse(in: CGRect(x: centre.x + blob.0 * scale - r,
                                           y: centre.y + blob.1 * scale - r,
                                           width: r * 2, height: r * 2))
            }
        }
    }

    private func conifer(at base: CGPoint, height: CGFloat) -> Path {
        Path { path in
            for tier in 0..<3 {
                let shrink = CGFloat(tier) * 0.22
                let width = height * (0.62 - shrink * 0.5)
                let top = base.y - height * (0.42 + CGFloat(tier) * 0.26)
                let bottom = base.y - height * CGFloat(tier) * 0.26
                path.move(to: CGPoint(x: base.x - width / 2, y: bottom))
                path.addLine(to: CGPoint(x: base.x, y: top))
                path.addLine(to: CGPoint(x: base.x + width / 2, y: bottom))
                path.closeSubpath()
            }
        }
    }
}

// MARK: - Pieces

/// A card that sits on the meadow like a sticker: pastel fill, white rim, soft shadow.
struct StickerCard<Content: View>: View {
    var fill: Color = Meadow.cardCream
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Meadow.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Meadow.radius, style: .continuous)
                    .strokeBorder(Meadow.cardRim, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.13), radius: 10, y: 5)
    }
}

/// The rounded-square icon sticker that leads every row and banner.
struct IconBadge: View {
    let symbol: String
    var tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(tint)
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

/// A section heading: badge, title, and a tinted band behind them.
struct SectionBanner: View {
    let symbol: String
    let title: String
    var tint: Color
    var band: Color

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(Meadow.title)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(band, in: Capsule())
    }
}

/// The frame the pushed screens share: painted meadow, a big rounded heading, and a
/// column of sticker cards. Setup, Photo sources and How's it going were three
/// different-looking screens before this existed — a List with grey system rows behind
/// a hand-painted hub.
struct MeadowScreen<Content: View>: View {

    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            MeadowBackdrop()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Meadow.title)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Meadow.title.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .readableColumn(maxWidth: 620)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        // The meadow runs under the bar; the back button keeps its place on top of it.
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// The big press-me button — the orange capsule from the end of a session, so the one
/// obvious action looks the same wherever it turns up.
struct MeadowButtonLabel: View {

    let title: String
    var symbol: String?

    @Environment(\.photoTextScale) private var textScale

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20 * textScale, weight: .black))
            }
            Text(title)
                .font(.system(size: 24 * textScale, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(
            LinearGradient(colors: [Color.hex(0xFFC44D), Color.hex(0xF0A020)],
                           startPoint: .top, endPoint: .bottom),
            in: Capsule())
        .overlay { Capsule().strokeBorder(Meadow.woodEdge, lineWidth: 3) }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
    }
}

/// A quiet line of small print, the one every card ends with.
struct MeadowNote: View {

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundStyle(Meadow.sparkle)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Meadow.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.white.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
