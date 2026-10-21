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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DemoPlayerView(
                        controller: session.playerController,
                        pictureInPictureController: session.pictureInPictureController,
                        snapshot: session.snapshot,
                        trackState: session.trackState,
                        isFullscreen: false,
                        onFullscreen: {
                            isFullscreen = true
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("StreamKit Demo")
                            .font(.title2.bold())

                        Text("HLS • AVFoundation")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)

                    if let errorMessage = session.errorMessage {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 12)
            }
            .background(Color(uiColor: .systemBackground))
            //.toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            DemoPlayerView(
                controller: session.playerController,
                pictureInPictureController: session.pictureInPictureController,
                snapshot: session.snapshot,
                trackState: session.trackState,
                isFullscreen: true,
                onFullscreen: {
                    isFullscreen = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        }
        .onAppear {
            session.playerRouteDidAppear()
        }
        .onDisappear {
            if !isFullscreen {
                session.playerRouteDidDisappear()
            }
        }
    }
}
