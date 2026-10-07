//
//  TimeRollsApp.swift
//  Time Rolls
//
//  Created by Hanna Mehraby on 9/10/26.
//

import SwiftUI

@main
struct TimeRollsApp: App {

    /// Up on every launch, first launch included, until `LaunchSplash.duration` has passed.
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Underneath, and already loading. See `LaunchSplash`.
                RootView()
                    .accessibilityHidden(showingSplash)
                if showingSplash {
                    LaunchSplash()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: LaunchSplash.duration)
                withAnimation(.easeOut(duration: 0.35)) { showingSplash = false }
            }
        }
    }
}
