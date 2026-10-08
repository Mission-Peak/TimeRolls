//
//  LaunchSplash.swift
//  Time Rolls
//
//  The first thing anybody sees, on every launch: a meadow with a sun and a winding film
//  strip across the bottom of the screen — Hanna's launch designs, one tall and one wide —
//  and "Time Rolls, by Mission Peak" written in the sky above it.
//
//  iOS shows a static launch screen while the app loads, and cannot be told how long to
//  show it. That screen is the sky's colour alone (Info.plist), so the picture and the name
//  fade in on the very sky that was already there, then hold for a moment before the game.
//
//  The game is not waiting on it. RootView sits underneath and starts loading straight
//  away, so the splash is time the app was going to spend getting ready anyway.
//

import SwiftUI
import UIKit

struct LaunchSplash: View {

    /// How long the splash stays up once the app is running.
    static let duration: Duration = .seconds(1.5)

    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let screen = geo.size
            ZStack {
                Color("LaunchSky")
                // Two of Hanna's designs: a tall one for phones and iPads upright, a
                // wide one for screens on their side.
                if screen.width > screen.height * 0.9 {
                    wide(screen)
                } else {
                    tall(screen)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time Rolls, by Mission Peak")
        .accessibilityAddTraits(.isModal)
    }

    /// Phones, and iPads upright: the tall design, its meadow along the bottom and the
    /// name in the sky above it.
    private func tall(_ screen: CGSize) -> some View {
        scene("LaunchScene", screen, artTop: Self.tallArtTop,
              fallback: CGSize(width: 2064, height: 4690),
              nameSize: min(screen.width * 0.17, 120))
    }

    /// Screens wider than they are tall: the wide design. It is 4:3 like an iPad on its
    /// side; an iPhone on its side is wider still and shows the picture's mirrored edges,
    /// which make_launch_art.py adds for it.
    private func wide(_ screen: CGSize) -> some View {
        scene("LaunchWide", screen, artTop: Self.wideArtTop,
              fallback: CGSize(width: 4607, height: 2064),
              nameSize: min(screen.width * 0.08, screen.height * 0.11, 120))
    }

    /// Where the art begins — the top of the sun — as a share of each picture's height,
    /// measured on the designs by Tools/Brand/make_launch_art.py's layout. The name sits a
    /// little above the middle of the sky over it, where the designs put it.
    private static let tallArtTop: CGFloat = 0.574
    private static let wideArtTop: CGFloat = 0.344

    /// The picture filling the screen, its meadow at the bottom, the name in its sky.
    private func scene(_ image: String, _ screen: CGSize, artTop: CGFloat, fallback: CGSize,
                       nameSize: CGFloat) -> some View {
        let picture = UIImage(named: image)?.size ?? fallback
        let scale = max(screen.width / picture.width, screen.height / picture.height)
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)
        let artTopOnScreen = screen.height - size.height * (1 - artTop)
        return ZStack {
            Image(image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .position(x: screen.width / 2, y: screen.height - size.height / 2)
            name(size: nameSize, alignment: .center)
                .position(x: screen.width / 2, y: artTopOnScreen * 0.53)
        }
        .frame(width: screen.width, height: screen.height)
        .opacity(shown ? 1 : 0)
    }

    private func name(size: CGFloat, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: size * 0.12) {
            Text("Time Rolls")
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(Meadow.title)
            Text("by Mission Peak")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.hex(0x35452D).opacity(0.9))
        }
        .fixedSize()
    }
}
