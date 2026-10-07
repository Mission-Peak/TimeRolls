//
//  MeadowTheme.swift
//  Time Rolls
//
//  The illustrated "meadow" look: a painted sky-and-hills page with a film strip running
//  through it, sticker cards on warm off-white with soft shadows, rounded-heavy headings
//  in deep sage, and badge icons that sit on the card like stickers.
//
//  Muted on purpose. The first meadow was sky blue, grass green and orange — bright enough
//  to tire the eyes over a long sitting, and loud enough to read as a children's game. This
//  one is the app icon's palette: off-white tile, deep sage, petal blush, terracotta clay,
//  walnut and charcoal. Softer glare, text that still clears contrast comfortably, and a
//  page that sits behind old photographs instead of competing with them.
//
//  Drawn rather than shipped as art, so the scene here is built from SwiftUI shapes and
//  SF Symbols. It gets the colour, the depth and the layout; it cannot get the brush.
//

import SwiftUI

enum Meadow {

    // MARK: Sky and land

    static let skyTop = Color.hex(0xE4E9DD)
    static let skyBottom = Color.hex(0xF9F4E8)
    static let cloud = Color.white.opacity(0.75)
    /// The icon's clay sun, held well back so it is a glow rather than a light.
    static let sun = Color.hex(0xC19A83).opacity(0.35)

    static let hillFar = Color.hex(0xC9D1BA)
    static let hillMid = Color.hex(0x8E9F7E)
    static let hillNear = Color.hex(0x5E7353)
    static let filmStrip = Color.hex(0x5E7353).opacity(0.5)
    static let tree = Color.hex(0x5E7353)
    static let treeDark = Color.hex(0x46593D)

    // MARK: Cards

    static let cardCream = Color.hex(0xF9F4E8)
    static let cardLavender = Color.hex(0xF4E8E5)   // petal blush, softened
    static let cardMint = Color.hex(0xEAEFE2)       // sage, softened
    static let cardSky = Color.hex(0xF2EEE4)        // warm stone
    static let cardRim = Color.white.opacity(0.75)

    // MARK: Ink

    static let title = Color.hex(0x2E3B29)
    static let body = Color.hex(0x4F5450)
    static let muted = Color.hex(0x676B65)
    /// Icons and button text on a light fill.
    static let accentInk = Color.hex(0x46593D)

    // MARK: Controls

    /// Everything pressable: deep sage with off-white lettering.
    static let button = Color.hex(0x46593D)
    static let buttonEdge = Color.hex(0x35452D)
    static let buttonInk = Color.hex(0xF9F4E8)
    static let buttonGradient = [Color.hex(0x55694C), Color.hex(0x46593D)]
    static let sparkle = Color.hex(0xD4A24C)
    /// The right answer, toggles, progress and ticks.
    static let on = Color.hex(0x5E7353)
    static let onInk = Color.hex(0x35452D)
    static let onWash = Color.hex(0xDDE4D2)

    // MARK: Earth accents

    static let flame = Color.hex(0xC9714A)
    static let clay = Color.hex(0xA9744E)
    static let walnut = Color.hex(0x715B4A)
    static let blush = Color.hex(0xE6CFCF)
    static let hintWash = Color.hex(0xF1E6DC)

    // MARK: Badges and bands
    //
    // The sticker badges carry a white glyph, so each tint is deep enough to hold one.
    // One per family the old candy colours came in, so a screen keeps its variety.

    static let badgeSage = Color.hex(0x5E7353)      // was green
    static let badgeOlive = Color.hex(0x7D8A5E)     // was mint
    static let badgeSlate = Color.hex(0x5F6B66)     // was sky blue
    static let badgeCharcoal = Color.hex(0x4F5450)  // was blue
    static let badgeWalnut = Color.hex(0x715B4A)    // was periwinkle
    static let badgeMauve = Color.hex(0x8A6F6A)     // was lavender
    static let badgeClay = Color.hex(0xA9744E)      // was orange
    static let badgeOchre = Color.hex(0xAE8746)     // was yellow
    static let badgeRose = Color.hex(0xA8737A)      // was pink

    static let bandSand = Color.hex(0xF1E9D8)
    static let bandSage = Color.hex(0xE6EBDD)
    static let bandBlush = Color.hex(0xF2E3E1)

    static let radius: CGFloat = 26
}

// MARK: - Backdrop

/// Sky, a low sun, clouds, three ridges of hill, a film strip and a line of trees.
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

                    context.fill(Circle().path(in: CGRect(x: w * 0.70, y: h * 0.05,
                                                          width: 78, height: 78)),
                                 with: .color(Meadow.sun))

                    for cloud in [(0.12, 0.05, 1.0), (0.46, 0.10, 0.7), (0.86, 0.15, 0.85)] {
                        context.fill(puff(at: CGPoint(x: w * cloud.0, y: h * cloud.1),
                                          scale: cloud.2),
                                     with: .color(Meadow.cloud))
                    }

                    // Three ridges, far to near, so the land has depth.
                    context.fill(ridge(w: w, h: h, top: 0.30, crest: 0.30, lift: 0.055),
                                 with: .color(Meadow.hillFar))

                    // The film strip from the icon, running behind the middle hill the
                    // way the river used to.
                    filmStrip(in: context,
                              from: CGPoint(x: -w * 0.1, y: h * 0.40),
                              control: CGPoint(x: w * 0.45, y: h * 0.18),
                              to: CGPoint(x: w * 1.1, y: h * 0.33))

                    context.fill(ridge(w: w, h: h, top: 0.36, crest: 0.72, lift: 0.070),
                                 with: .color(Meadow.hillMid))

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

    /// A band along a quadratic curve with a row of sprocket holes down each edge.
    private func filmStrip(in context: GraphicsContext, from start: CGPoint,
                           control: CGPoint, to end: CGPoint) {
        let half: CGFloat = 16
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                           y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
        }
        func normal(_ t: CGFloat) -> CGVector {
            let dx = 2 * (1 - t) * (control.x - start.x) + 2 * t * (end.x - control.x)
            let dy = 2 * (1 - t) * (control.y - start.y) + 2 * t * (end.y - control.y)
            let length = max(hypot(dx, dy), 0.001)
            return CGVector(dx: -dy / length, dy: dx / length)
        }

        let steps = 60
        var band = Path()
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = point(t), n = normal(t)
            let edge = CGPoint(x: p.x + n.dx * half, y: p.y + n.dy * half)
            if i == 0 { band.move(to: edge) } else { band.addLine(to: edge) }
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            let p = point(t), n = normal(t)
            band.addLine(to: CGPoint(x: p.x - n.dx * half, y: p.y - n.dy * half))
        }
        band.closeSubpath()
        context.fill(band, with: .color(Meadow.filmStrip))

        // Holes punched out of the band, evenly spaced by eye rather than by arc length;
        // the curve is shallow enough that nobody can tell.
        let holes = 34
        for i in 0..<holes {
            let t = (CGFloat(i) + 0.5) / CGFloat(holes)
            let p = point(t), n = normal(t)
            let angle = Angle(radians: atan2(n.dx, -n.dy))
            for side in [-1.0, 1.0] as [CGFloat] {
                var hole = context
                hole.translateBy(x: p.x + n.dx * (half - 6) * side,
                                 y: p.y + n.dy * (half - 6) * side)
                hole.rotate(by: angle)
                hole.fill(RoundedRectangle(cornerRadius: 1.5)
                            .path(in: CGRect(x: -3.5, y: -2.5, width: 7, height: 5)),
                          with: .color(Meadow.skyBottom.opacity(0.85)))
            }
        }
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

/// The big press-me button — the deep sage capsule from the end of a session, so the one
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
        .foregroundStyle(Meadow.buttonInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(
            LinearGradient(colors: Meadow.buttonGradient,
                           startPoint: .top, endPoint: .bottom),
            in: Capsule())
        .overlay { Capsule().strokeBorder(Meadow.buttonEdge, lineWidth: 3) }
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
