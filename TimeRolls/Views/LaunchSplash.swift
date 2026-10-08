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
            // Tools/Brand/make_launch_art.py draws the icon square across the full width
            // at the bottom of a tall sky, so filling the width puts the icon's picture at
            // the bottom of every screen; an iPad, being wider, shows less of the sky.
            let picture = UIImage(named: "LaunchScene")?.size ?? CGSize(width: 1290, height: 2803)
            let scale = max(screen.width / picture.width, screen.height / picture.height)
            let size = CGSize(width: picture.width * scale, height: picture.height * scale)
            // The sky left above the icon's picture, where the name goes.
            let sky = max(screen.height - picture.width * scale, screen.height * 0.3)
            ZStack(alignment: .top) {
                Color("LaunchSky")
                Image("LaunchScene")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .position(x: screen.width / 2, y: screen.height - size.height / 2)
                    .opacity(shown ? 1 : 0)
                VStack(spacing: screen.width * 0.02) {
                    Text("Time Rolls")
                        .font(.system(size: min(screen.width * 0.17, 120), weight: .black,
                                      design: .rounded))
                        .foregroundStyle(Meadow.title)
                    Text("by Mission Peak")
                        .font(.system(size: min(screen.width * 0.065, 46), weight: .semibold,
                                      design: .rounded))
                        .foregroundStyle(Color.hex(0x35452D).opacity(0.9))
                }
                .fixedSize()
                .frame(width: screen.width, height: sky)
                // A little above the middle of the sky, clear of the status bar.
                .padding(.top, geo.safeAreaInsets.top * 0.5)
                .opacity(shown ? 1 : 0)
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
}
