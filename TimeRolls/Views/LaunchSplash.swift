//
//  LaunchSplash.swift
//  Time Rolls
//
//  The first thing anybody sees, on every launch: the app icon's own picture — the hills,
//  the sun, the film strip — across the bottom of the screen, and "Time Rolls, by Mission
//  Peak" written in the sky above it.
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
                // The picture is square. Across the bottom of a tall screen it is the
                // whole background with sky above it for the name; on a screen wider
                // than it is tall — an iPad on its side — filling the width made it
                // taller than the screen, cut off its top and bottom, and put the name
                // over the sun and the film strip. There it is the icon itself instead,
                // beside the name.
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

    private var pictureSize: CGSize {
        UIImage(named: "LaunchScene")?.size ?? CGSize(width: 2400, height: 5215)
    }

    /// Phones, and iPads upright: the icon's picture across the bottom, the name in the
    /// sky above it.
    private func tall(_ screen: CGSize) -> some View {
        let picture = pictureSize
        // Tools/Brand/make_launch_art.py draws the icon square across the full width at
        // the bottom of a tall sky, so filling the width puts the icon's picture at the
        // bottom of every screen; an iPad, being wider, shows less of the sky.
        let scale = max(screen.width / picture.width, screen.height / picture.height)
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)
        // The sky left above the icon's picture, where the name goes.
        let sky = max(screen.height - picture.width * scale, screen.height * 0.3)
        return ZStack(alignment: .top) {
            Image("LaunchScene")
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .position(x: screen.width / 2, y: screen.height - size.height / 2)
                .opacity(shown ? 1 : 0)
            name(size: min(screen.width * 0.17, 120), alignment: .center)
                .frame(width: screen.width, height: sky)
                .opacity(shown ? 1 : 0)
        }
        .frame(width: screen.width, height: screen.height)
    }

    /// Screens wider than they are tall: a wide meadow across the whole screen, from
    /// Hanna's design, with the name in the sky on the left.
    ///
    /// The square icon picture could not do this. Filled to the width of an iPad on its
    /// side it was taller than the screen, lost its top and bottom, and the name sat on
    /// the sun and the film strip. The wide picture (make_launch_art.py, `launch_wide`)
    /// is 4:3 with its meadow along the bottom, so it fills an iPad exactly and a wider
    /// screen crops only sky.
    private func wide(_ screen: CGSize) -> some View {
        let picture = UIImage(named: "LaunchWide")?.size ?? CGSize(width: 2752, height: 2064)
        let scale = max(screen.width / picture.width, screen.height / picture.height)
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)
        let left = (screen.width - size.width) / 2
        // Where the trees on the left begin, as a share of the picture's height: the name
        // sits in the sky above them, where the design has it.
        let treeline = screen.height - size.height * (1 - Self.wideTreeline)
        return ZStack(alignment: .topLeading) {
            Image("LaunchWide")
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .position(x: screen.width / 2, y: screen.height - size.height / 2)
            name(size: min(size.width * 0.08, 120), alignment: .center)
                .position(x: left + size.width * 0.256, y: treeline * 0.6)
        }
        .frame(width: screen.width, height: screen.height)
        .opacity(shown ? 1 : 0)
    }

    /// The top of the treeline on the left of the wide picture, as a share of its height.
    private static let wideTreeline: CGFloat = 0.697

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
