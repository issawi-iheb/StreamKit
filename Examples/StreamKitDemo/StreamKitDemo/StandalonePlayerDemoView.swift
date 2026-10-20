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
    @State private var controller = StreamPlayerController()

    @State private var snapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )

    @State private var errorMessage: String?
    @State private var isFullscreen = false

    // Shared between embedded and fullscreen player.
    @State private var trackState = PlayerTrackState()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DemoPlayerView(
                        controller: controller,
                        snapshot: snapshot,
                        trackState: trackState,
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

                    if let errorMessage {
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
                controller: controller,
                snapshot: snapshot,
                trackState: trackState,
                isFullscreen: true,
                onFullscreen: {
                    isFullscreen = false
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        }
        .task {
            guard let url = URL(
                string: "https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8"
            ) else {
                errorMessage = "Invalid media URL."
                return
            }

            trackState.prepareForNewSource()
            let handle = controller.load(MediaSource(url: url))

            do {
                try await handle.waitUntilReady()
                try await controller.play()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .task {
            for await newSnapshot in controller.snapshots {
                snapshot = newSnapshot
            }
        }
        .task {
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(3_600))
                    } catch {
                        break
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    await controller.shutdown()
                }
            }
        }
    }
}
