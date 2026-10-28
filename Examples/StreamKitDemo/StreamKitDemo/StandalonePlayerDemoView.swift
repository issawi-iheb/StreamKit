//
//  ContentView.swift
//  StreamKitDemo
//
//  Created by Iheb on 13/10/2026.
//

import SwiftUI
import StreamKit

// MARK: - Content View

@MainActor
struct StandalonePlayerDemoView: View {
    @ObservedObject var session: StandalonePlayerDemoSession
    @State private var isFullscreen = false
    @State private var controlsVisible = true

    var body: some View {
        DemoScrollContainer {
            DemoScreenHeading(
                eyebrow: "CUSTOM CONTROLS",
                title: "Build your player",
                subtitle: "StreamKit playback with app-owned controls, seeking, tracks, and fullscreen."
            )

            DemoPlayerView(
                controller: session.playerController,
                pictureInPictureController: session.pictureInPictureController,
                snapshot: session.snapshot,
                trackState: session.trackState,
                isFullscreen: false,
                onFullscreen: {
                    isFullscreen = true
                },
                controlsVisible: $controlsVisible,
                isActiveSurface: !isFullscreen
            )

            PlaybackDiagnosticsPanel(controller: session.playerController)

            if let errorMessage = session.errorMessage {
                DemoInlineNotice(errorMessage)
            }
        }
        .navigationTitle("Custom player")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isFullscreen) {
            DemoPlayerView(
                controller: session.playerController,
                pictureInPictureController: session.pictureInPictureController,
                snapshot: session.snapshot,
                trackState: session.trackState,
                isFullscreen: true,
                onFullscreen: {
                    isFullscreen = false
                },
                controlsVisible: $controlsVisible,
                isActiveSurface: !isFullscreen
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        }
        .onAppear {
            session.playerRouteDidAppear()
            session.playerInterfaceDidAppear()
        }
        .onDisappear {
            guard !isFullscreen else { return }

            session.playerInterfaceDidDisappear()
            session.playerRouteDidDisappear()
        }
    }
}
