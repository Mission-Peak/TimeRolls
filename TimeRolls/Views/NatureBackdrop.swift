//
//  NatureBackdrop.swift
//  Time Rolls
//
//  The Sage & Cream botanical motif: a soft hill ridge under the top bar, two hills
//  rising from the bottom, and a two-leaf sprig in each corner.
//
//  Held at the quiet end of the range the design file allows — hills at 10%, leaves at
//  12% rather than 16% — because in this app the photographs are the content and
//  everything else is wallpaper. Decoration that competes with a photograph of somebody's
//  mother is decoration in the wrong place, and the audience is the one least able to
//  tell the wallpaper from the picture.
//
//  Purely decorative, and marked as such so VoiceOver never announces it.
//

import SwiftUI

struct NatureBackdrop: View {

    var body: some View {
        Canvas { context, size in
            // A ridge hanging from the top, and two rising from the bottom, so the
            // page reads as a shallow landscape rather than a flat wash.
            context.fill(ridge(in: size, from: .top, crest: 0.16, depth: 0.09),
                         with: .color(Palette.olive.opacity(0.10)))
            context.fill(ridge(in: size, from: .bottom, crest: 0.30, depth: 0.15),
                         with: .color(Palette.olive.opacity(0.11)))
            context.fill(ridge(in: size, from: .bottom, crest: 0.72, depth: 0.10),
                         with: .color(Palette.accent.opacity(0.10)))

            // Small, and well inside the edges. At thirty points from a twenty-six point
            // inset they ran off the screen and read as smudges rather than leaves —
            // and the top pair sat under the clock.
            for corner in Corner.allCases {
                context.fill(sprig(in: size, corner: corner, inset: 46, length: 20),
                             with: .color(Palette.accent.opacity(0.13)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private enum Corner: CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    /// A smooth quadratic crest filled down to the edge it hangs from.
    private func ridge(in size: CGSize, from edge: Edge, crest: CGFloat, depth: CGFloat) -> Path {
        let height = size.height
        return Path { path in
            let base = edge == .top ? 0 : height
            let reach = edge == .top ? height * depth : -height * depth
            path.move(to: CGPoint(x: 0, y: base))
            path.addQuadCurve(to: CGPoint(x: size.width, y: base + reach * 0.35),
                              control: CGPoint(x: size.width * crest, y: base + reach * 1.6))
            path.addLine(to: CGPoint(x: size.width, y: base))
            path.closeSubpath()
        }
    }

    /// Two mirrored quadratic curves meeting at a tip — a pointed oval, bulging at the
    /// sides — drawn twice from a shared stem.
    private func sprig(in size: CGSize, corner: Corner, inset: CGFloat, length: CGFloat) -> Path {
        let origin: CGPoint
        let flipX: CGFloat
        let flipY: CGFloat
        switch corner {
        case .topLeading:     origin = CGPoint(x: inset, y: inset);                     flipX = 1;  flipY = 1
        case .topTrailing:    origin = CGPoint(x: size.width - inset, y: inset);        flipX = -1; flipY = 1
        case .bottomLeading:  origin = CGPoint(x: inset, y: size.height - inset);       flipX = 1;  flipY = -1
        case .bottomTrailing: origin = CGPoint(x: size.width - inset, y: size.height - inset); flipX = -1; flipY = -1
        }
        return Path { path in
            for angle in [0.35, 0.95] as [CGFloat] {
                let tip = CGPoint(x: origin.x + cos(angle) * length * flipX,
                                  y: origin.y + sin(angle) * length * flipY)
                let mid = CGPoint(x: (origin.x + tip.x) / 2, y: (origin.y + tip.y) / 2)
                // Narrower than a third of the length, or the pointed oval fattens into
                // a circle and stops looking like a leaf at all.
                let across = CGPoint(x: -(tip.y - origin.y) * 0.22, y: (tip.x - origin.x) * 0.22)
                path.move(to: origin)
                path.addQuadCurve(to: tip,
                                  control: CGPoint(x: mid.x + across.x, y: mid.y + across.y))
                path.addQuadCurve(to: origin,
                                  control: CGPoint(x: mid.x - across.x, y: mid.y - across.y))
                path.closeSubpath()
            }
        }
    }
}
