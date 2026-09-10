//
//  PackArtRenderer.swift
//  Photo Chronology
//
//  Draws the bundled pack artwork. Placeholder era art stands in for licensed
//  historical photography, which is an open sourcing item (spec §6.2, §12).
//  Output is deterministic per item, so a photo looks the same every time it appears.
//

import UIKit

enum PackArtRenderer {

    private static let cache = NSCache<NSString, UIImage>()

    static func image(for item: PackItem, size: CGSize) -> UIImage {
        let key = "\(item.id)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let palette = Palette(year: Calendar.current.component(.year, from: item.date))
        var rng = SeededGenerator(seed: stableHash(item.id))

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            switch item.motif {
            case .mountains: drawMountains(ctx, rect, palette, &rng)
            case .seaside: drawSeaside(ctx, rect, palette, &rng)
            case .cityscape: drawCityscape(ctx, rect, palette, &rng)
            case .celebration: drawCelebration(ctx, rect, palette, &rng)
            case .portrait: drawPortrait(ctx, rect, palette, &rng)
            case .roadTrip: drawRoadTrip(ctx, rect, palette, &rng)
            case .kitchen: drawKitchen(ctx, rect, palette, &rng)
            case .garden: drawGarden(ctx, rect, palette, &rng)
            }

            applyEraFinish(ctx, rect, palette)
        }

        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Era palettes
    //
    // Every palette keeps a wide luminance range: the mono difficulty lever must stay
    // crisp rather than faded, per the accessibility guardrail in spec §7.1.

    private struct Palette {
        var skyTop: UIColor
        var skyBottom: UIColor
        var mid: UIColor
        var dark: UIColor
        var accent: UIColor
        var light: UIColor
        var grain: CGFloat

        init(year: Int) {
            switch year {
            case ..<1960:
                skyTop = .rgb(228, 214, 186); skyBottom = .rgb(243, 233, 210)
                mid = .rgb(146, 124, 92); dark = .rgb(52, 40, 28)
                accent = .rgb(178, 96, 52); light = .rgb(252, 247, 234)
                grain = 0.10
            case 1960..<1980:
                skyTop = .rgb(74, 146, 168); skyBottom = .rgb(226, 196, 140)
                mid = .rgb(196, 118, 54); dark = .rgb(46, 46, 40)
                accent = .rgb(212, 74, 50); light = .rgb(250, 240, 216)
                grain = 0.07
            case 1980..<2000:
                skyTop = .rgb(96, 132, 180); skyBottom = .rgb(206, 214, 226)
                mid = .rgb(120, 138, 130); dark = .rgb(38, 44, 54)
                accent = .rgb(196, 84, 116); light = .rgb(244, 246, 250)
                grain = 0.04
            default:
                skyTop = .rgb(84, 150, 208); skyBottom = .rgb(214, 232, 244)
                mid = .rgb(92, 146, 116); dark = .rgb(28, 36, 44)
                accent = .rgb(232, 152, 60); light = .rgb(252, 253, 255)
                grain = 0.02
            }
        }
    }

    // MARK: - Motifs

    private static func drawMountains(_ ctx: CGContext, _ rect: CGRect,
                                      _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.skyTop, p.skyBottom)
        disk(ctx, center: CGPoint(x: rect.width * rng.double(0.2, 0.8), y: rect.height * 0.22),
             radius: rect.width * 0.09, color: p.light.withAlphaComponent(0.9))

        let ridges: [(CGFloat, UIColor)] = [(0.52, p.mid.blended(with: p.light, 0.45)),
                                            (0.62, p.mid),
                                            (0.72, p.dark.blended(with: p.mid, 0.35))]
        for (baseline, color) in ridges {
            let path = CGMutablePath()
            let y = rect.height * baseline
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: y + rect.height * 0.08))
            var x: CGFloat = 0
            while x < rect.width {
                let step = rect.width * rng.cgFloat(0.16, 0.30)
                let peak = y - rect.height * rng.cgFloat(0.02, 0.10)
                path.addLine(to: CGPoint(x: x + step / 2, y: peak))
                path.addLine(to: CGPoint(x: x + step, y: y + rect.height * rng.cgFloat(0.0, 0.05)))
                x += step
            }
            path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
            path.closeSubpath()
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        band(ctx, rect, from: 0.86, to: 1.0, color: p.dark)
    }

    private static func drawSeaside(_ ctx: CGContext, _ rect: CGRect,
                                    _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.skyTop, p.skyBottom)
        disk(ctx, center: CGPoint(x: rect.width * 0.72, y: rect.height * 0.20),
             radius: rect.width * 0.11, color: p.light.withAlphaComponent(0.95))
        band(ctx, rect, from: 0.52, to: 0.74, color: p.skyTop.blended(with: p.dark, 0.35))
        for i in 0..<9 {
            let y = rect.height * (0.55 + CGFloat(i) * 0.02)
            let inset = rect.width * rng.cgFloat(0.05, 0.35)
            ctx.setStrokeColor(p.light.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(rect.height * 0.006)
            ctx.strokeLineSegments(between: [CGPoint(x: inset, y: y),
                                             CGPoint(x: inset + rect.width * 0.4, y: y)])
        }
        band(ctx, rect, from: 0.74, to: 1.0, color: p.skyBottom.blended(with: p.mid, 0.45))
        // Beach umbrella.
        let ux = rect.width * rng.cgFloat(0.2, 0.7), uy = rect.height * 0.82
        ctx.setStrokeColor(p.dark.cgColor)
        ctx.setLineWidth(rect.width * 0.012)
        ctx.strokeLineSegments(between: [CGPoint(x: ux, y: uy), CGPoint(x: ux, y: uy + rect.height * 0.08)])
        let dome = CGMutablePath()
        dome.addArc(center: CGPoint(x: ux, y: uy), radius: rect.width * 0.11,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        ctx.setFillColor(p.accent.cgColor)
        ctx.addPath(dome)
        ctx.fillPath()
    }

    private static func drawCityscape(_ ctx: CGContext, _ rect: CGRect,
                                      _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.skyTop, p.skyBottom)
        var x: CGFloat = -rect.width * 0.05
        while x < rect.width {
            let w = rect.width * rng.cgFloat(0.10, 0.22)
            let h = rect.height * rng.cgFloat(0.20, 0.48)
            let top = rect.height * 0.80 - h
            let shade = p.dark.blended(with: p.mid, rng.cgFloat(0.05, 0.5))
            ctx.setFillColor(shade.cgColor)
            ctx.fill(CGRect(x: x, y: top, width: w, height: h + rect.height * 0.2))
            // Lit windows.
            let cols = max(2, Int(w / (rect.width * 0.045)))
            let rows = max(3, Int(h / (rect.height * 0.055)))
            for c in 0..<cols {
                for r in 0..<rows where rng.double(0, 1) > 0.45 {
                    let wx = x + rect.width * 0.014 + CGFloat(c) * (w / CGFloat(cols))
                    let wy = top + rect.height * 0.02 + CGFloat(r) * (h / CGFloat(rows))
                    ctx.setFillColor(p.light.withAlphaComponent(0.85).cgColor)
                    ctx.fill(CGRect(x: wx, y: wy, width: w / CGFloat(cols) * 0.45,
                                    height: h / CGFloat(rows) * 0.4))
                }
            }
            x += w + rect.width * 0.015
        }
        band(ctx, rect, from: 0.88, to: 1.0, color: p.dark)
    }

    private static func drawCelebration(_ ctx: CGContext, _ rect: CGRect,
                                        _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.mid.blended(with: p.dark, 0.45), p.mid.blended(with: p.light, 0.25))
        // Bunting.
        var bx: CGFloat = 0
        while bx < rect.width {
            let w = rect.width * 0.11
            let flag = CGMutablePath()
            flag.move(to: CGPoint(x: bx, y: rect.height * 0.06))
            flag.addLine(to: CGPoint(x: bx + w, y: rect.height * 0.06))
            flag.addLine(to: CGPoint(x: bx + w / 2, y: rect.height * 0.17))
            flag.closeSubpath()
            ctx.setFillColor((rng.double(0, 1) > 0.5 ? p.accent : p.light).cgColor)
            ctx.addPath(flag)
            ctx.fillPath()
            bx += w + rect.width * 0.02
        }
        // Table.
        band(ctx, rect, from: 0.68, to: 1.0, color: p.light.blended(with: p.mid, 0.2))
        // Cake.
        let cake = CGRect(x: rect.width * 0.28, y: rect.height * 0.46,
                          width: rect.width * 0.44, height: rect.height * 0.22)
        ctx.setFillColor(p.light.cgColor)
        ctx.addPath(CGPath(roundedRect: cake, cornerWidth: rect.width * 0.03,
                           cornerHeight: rect.width * 0.03, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(p.accent.cgColor)
        ctx.fill(CGRect(x: cake.minX, y: cake.minY, width: cake.width, height: cake.height * 0.22))
        // Candles.
        for i in 0..<4 {
            let cx = cake.minX + cake.width * (0.18 + CGFloat(i) * 0.22)
            ctx.setFillColor(p.dark.cgColor)
            ctx.fill(CGRect(x: cx, y: cake.minY - rect.height * 0.07,
                            width: rect.width * 0.018, height: rect.height * 0.07))
            disk(ctx, center: CGPoint(x: cx + rect.width * 0.009, y: cake.minY - rect.height * 0.082),
                 radius: rect.width * 0.02, color: p.accent.blended(with: p.light, 0.4))
        }
    }

    private static func drawPortrait(_ ctx: CGContext, _ rect: CGRect,
                                     _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.mid.blended(with: p.light, 0.5), p.mid.blended(with: p.dark, 0.3))
        let shoulders = CGMutablePath()
        shoulders.addArc(center: CGPoint(x: rect.midX, y: rect.height * 1.12),
                         radius: rect.width * 0.52, startAngle: .pi, endAngle: 0, clockwise: false)
        ctx.setFillColor(p.dark.blended(with: p.accent, rng.cgFloat(0.05, 0.35)).cgColor)
        ctx.addPath(shoulders)
        ctx.fillPath()
        disk(ctx, center: CGPoint(x: rect.midX, y: rect.height * 0.46),
             radius: rect.width * 0.21, color: p.light.blended(with: p.accent, 0.28))
        // Hair.
        let hair = CGMutablePath()
        hair.addArc(center: CGPoint(x: rect.midX, y: rect.height * 0.44),
                    radius: rect.width * 0.22, startAngle: .pi, endAngle: 0, clockwise: false)
        ctx.setFillColor(p.dark.cgColor)
        ctx.addPath(hair)
        ctx.fillPath()
        // Collar.
        let collar = CGMutablePath()
        collar.move(to: CGPoint(x: rect.midX - rect.width * 0.13, y: rect.height * 0.66))
        collar.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.78))
        collar.addLine(to: CGPoint(x: rect.midX + rect.width * 0.13, y: rect.height * 0.66))
        collar.closeSubpath()
        ctx.setFillColor(p.light.cgColor)
        ctx.addPath(collar)
        ctx.fillPath()
    }

    private static func drawRoadTrip(_ ctx: CGContext, _ rect: CGRect,
                                     _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.skyTop, p.skyBottom)
        // Distant mesa.
        let mesa = CGMutablePath()
        mesa.move(to: CGPoint(x: rect.width * 0.05, y: rect.height * 0.55))
        mesa.addLine(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.40))
        mesa.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.40))
        mesa.addLine(to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.55))
        mesa.closeSubpath()
        ctx.setFillColor(p.accent.blended(with: p.dark, 0.35).cgColor)
        ctx.addPath(mesa)
        ctx.fillPath()
        band(ctx, rect, from: 0.55, to: 1.0, color: p.mid.blended(with: p.light, 0.3))
        // Road.
        let road = CGMutablePath()
        road.move(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.55))
        road.addLine(to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.55))
        road.addLine(to: CGPoint(x: rect.width * 1.05, y: rect.maxY))
        road.addLine(to: CGPoint(x: rect.width * -0.05, y: rect.maxY))
        road.closeSubpath()
        ctx.setFillColor(p.dark.cgColor)
        ctx.addPath(road)
        ctx.fillPath()
        var y = rect.height * 0.60
        var w = rect.width * 0.012
        while y < rect.maxY {
            ctx.setFillColor(p.light.cgColor)
            ctx.fill(CGRect(x: rect.midX - w / 2, y: y, width: w, height: rect.height * 0.035))
            y += rect.height * 0.09
            w *= 1.45
        }
        _ = rng.double(0, 1)
    }

    private static func drawKitchen(_ ctx: CGContext, _ rect: CGRect,
                                    _ p: Palette, _ rng: inout SeededGenerator) {
        ctx.setFillColor(p.light.blended(with: p.mid, 0.25).cgColor)
        ctx.fill(rect)
        // Window with daylight.
        let window = CGRect(x: rect.width * 0.14, y: rect.height * 0.12,
                            width: rect.width * 0.5, height: rect.height * 0.34)
        gradient(ctx, window, p.skyTop, p.skyBottom)
        ctx.setStrokeColor(p.dark.cgColor)
        ctx.setLineWidth(rect.width * 0.02)
        ctx.stroke(window)
        ctx.strokeLineSegments(between: [CGPoint(x: window.midX, y: window.minY),
                                         CGPoint(x: window.midX, y: window.maxY),
                                         CGPoint(x: window.minX, y: window.midY),
                                         CGPoint(x: window.maxX, y: window.midY)])
        // Counter.
        band(ctx, rect, from: 0.62, to: 0.68, color: p.dark.blended(with: p.accent, 0.3))
        band(ctx, rect, from: 0.68, to: 1.0, color: p.mid.blended(with: p.dark, 0.25))
        // Kettle and cups.
        let kettle = CGRect(x: rect.width * 0.18, y: rect.height * 0.48,
                            width: rect.width * 0.22, height: rect.height * 0.14)
        ctx.setFillColor(p.accent.cgColor)
        ctx.addPath(CGPath(roundedRect: kettle, cornerWidth: rect.width * 0.04,
                           cornerHeight: rect.width * 0.04, transform: nil))
        ctx.fillPath()
        for i in 0..<3 {
            let cup = CGRect(x: rect.width * (0.50 + CGFloat(i) * 0.14), y: rect.height * 0.545,
                             width: rect.width * 0.10, height: rect.height * 0.075)
            ctx.setFillColor(p.light.cgColor)
            ctx.addPath(CGPath(roundedRect: cup, cornerWidth: rect.width * 0.015,
                               cornerHeight: rect.width * 0.015, transform: nil))
            ctx.fillPath()
        }
        _ = rng.double(0, 1)
    }

    private static func drawGarden(_ ctx: CGContext, _ rect: CGRect,
                                   _ p: Palette, _ rng: inout SeededGenerator) {
        gradient(ctx, rect, p.skyTop, p.skyBottom)
        band(ctx, rect, from: 0.42, to: 0.58, color: p.mid.blended(with: p.dark, 0.45))
        band(ctx, rect, from: 0.58, to: 1.0, color: p.mid)
        // Path.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.60, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.14, y: rect.maxY))
        path.closeSubpath()
        ctx.setFillColor(p.light.blended(with: p.mid, 0.35).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        // Flowers.
        for _ in 0..<14 {
            let fx = rect.width * rng.cgFloat(0.04, 0.96)
            let fy = rect.height * rng.cgFloat(0.62, 0.95)
            ctx.setStrokeColor(p.dark.blended(with: p.mid, 0.5).cgColor)
            ctx.setLineWidth(rect.width * 0.008)
            ctx.strokeLineSegments(between: [CGPoint(x: fx, y: fy),
                                             CGPoint(x: fx, y: fy + rect.height * 0.05)])
            disk(ctx, center: CGPoint(x: fx, y: fy), radius: rect.width * 0.022,
                 color: rng.double(0, 1) > 0.5 ? p.accent : p.light)
        }
    }

    // MARK: - Finishing

    /// Vignette plus a light grain that is heavier on older eras. Keeps the darks dark so
    /// the mono lever stays high-contrast rather than washed out.
    private static func applyEraFinish(_ ctx: CGContext, _ rect: CGRect, _ p: Palette) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.28).cgColor]
        if let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0.55, 1.0]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: rect.midX, y: rect.midY),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: rect.midX, y: rect.midY),
                                   endRadius: max(rect.width, rect.height) * 0.75,
                                   options: [])
        }
        guard p.grain > 0.01 else { return }
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<Int(rect.width * rect.height / 900) {
            let x = rect.width * rng.cgFloat(0, 1)
            let y = rect.height * rng.cgFloat(0, 1)
            ctx.setFillColor(UIColor.white.withAlphaComponent(p.grain * rng.cgFloat(0.2, 0.8)).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
        }
    }

    // MARK: - Drawing helpers

    private static func gradient(_ ctx: CGContext, _ rect: CGRect, _ top: UIColor, _ bottom: UIColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let g = CGGradient(colorsSpace: space,
                                 colors: [top.cgColor, bottom.cgColor] as CFArray,
                                 locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g,
                               start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [])
        ctx.restoreGState()
    }

    private static func band(_ ctx: CGContext, _ rect: CGRect,
                             from: CGFloat, to: CGFloat, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.height * from,
                        width: rect.width, height: rect.height * (to - from)))
    }

    private static func disk(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
    }

    /// Process-stable string hash — `Hasher` is seeded per launch and would reshuffle art.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }
}

/// Deterministic little LCG so each pack item's artwork is stable.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }

    private mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func double(_ lower: Double, _ upper: Double) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return lower + unit * (upper - lower)
    }

    mutating func cgFloat(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        CGFloat(double(Double(lower), Double(upper)))
    }
}

private extension UIColor {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    func blended(with other: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = amount.clamped(to: 0...1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}
