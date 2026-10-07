//
//  LaunchSplash.swift
//  Time Rolls
//
//  The first thing anybody sees, on every launch: the logo, and under it "by Mission Peak".
//
//  iOS shows a static launch screen while the app loads — the logo alone on the icon's
//  blush sky, from Info.plist — and cannot be told how long to show it. This draws the same
//  logo in exactly the same place and adds the line beneath it, so the two read as one
//  screen, then holds it for a moment before fading into the game.
//
//  The game is not waiting on it. RootView sits underneath and starts loading straight
//  away, so the splash is time the app was going to spend getting ready anyway.
//

import SwiftUI
import UIKit

struct LaunchSplash: View {

    /// How long the splash stays up once the app is running.
    static let duration: Duration = .seconds(1.5)

    /// The logo's size on screen, in points. The launch image is made at exactly these
    /// sizes — see `LaunchMark.imageset` — so the two must stay the same or the logo jumps
    /// as one screen gives way to the other. A phone-sized logo on an iPad was a small
    /// square in a lot of sky.
    private static var logoSize: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 380 : 210
    }
    /// The launch image carries the logo's soft shadow, so it is this much bigger than
    /// the logo on every side.
    private static let shadowRoom: CGFloat = 0.14

    @State private var sceneShown = false

    /// Where the tops of the hills are in the picture, as a share of its height, and where
    /// they should sit on screen.
    ///
    /// The picture is drawn by Tools/Brand/make_launch_art.py from the app icon's own
    /// colours, with its hilltops at exactly this height.
    ///
    /// The picture was painted for a phone. Stretched across an iPad it grew two and a
    /// half times and the hills took the bottom half of the screen, with "by Mission Peak"
    /// sitting on the film strip. So the horizon is held at the same height on every
    /// screen, and whatever does not fit comes off the bottom — the nearest bushes —
    /// rather than off the sky. On a phone that works out to no change at all.
    private static let horizonInPicture: CGFloat = 0.698
    private static let horizonOnScreen: CGFloat = 0.68

    private var scene: some View {
        GeometryReader { geo in
            let screen = geo.size
            let picture = UIImage(named: "LaunchScene")?.size ?? CGSize(width: 1290, height: 2803)
            let scale = max(screen.width / picture.width, screen.height / picture.height)
            let size = CGSize(width: picture.width * scale, height: picture.height * scale)
            // How far below its bottom-aligned place the picture has to drop for its
            // horizon to land where it should. Never upwards, which would leave a gap.
            let drop = max(0, size.height * (1 - Self.horizonInPicture)
                              - screen.height * (1 - Self.horizonOnScreen))
            Image("LaunchScene")
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .position(x: screen.width / 2,
                          y: screen.height - size.height / 2 + drop)
        }
        .clipped()
    }

    var body: some View {
        let logo = Self.logoSize
        let canvas = logo * (1 + 2 * Self.shadowRoom)
        ZStack {
            // What the static launch screen shows: the sky's colour behind the logo.
            Color("LaunchSky")
            // The sky and the hills fade in around a logo that has not moved.
            scene
                .opacity(sceneShown ? 1 : 0)
            // Centred on the whole screen, safe areas ignored, because that is where the
            // static launch screen puts it. The line hangs below the logo rather than
            // sharing a stack with it; stacking them would move the logo up by half the
            // line's height and it would visibly jump.
            Image("LaunchMark")
                .resizable()
                .frame(width: canvas, height: canvas)
                .overlay(alignment: .bottom) {
                    Text("by Mission Peak")
                        .font(.system(size: logo * 0.11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.hex(0x35452D).opacity(0.9))
                        .fixedSize()
                        // Below the logo itself, not below its shadow.
                        .alignmentGuide(.bottom) {
                            $0[.top] - (logo * 0.1 - logo * Self.shadowRoom)
                        }
                }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { sceneShown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time Rolls, by Mission Peak")
        .accessibilityAddTraits(.isModal)
    }
}
