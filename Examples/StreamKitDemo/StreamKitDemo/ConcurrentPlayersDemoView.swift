//
//  ConcurrentPlayersDemoView.swift
//  StreamKitDemo
//
//  Created by Iheb on 14/10/2026.
//

import SwiftUI
import StreamKit

@MainActor
struct ConcurrentPlayersDemoView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var firstController = StreamPlayerController()
    @State private var secondController = StreamPlayerController()

    @State private var firstTrackState = PlayerTrackState()
    @State private var secondTrackState = PlayerTrackState()
    @State private var isFirstPlayerFullscreen = false
    @State private var isSecondPlayerFullscreen = false
    @State private var firstControlsVisible = true
    @State private var secondControlsVisible = true
    @State private var firstSnapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )

    @State private var secondSnapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )

    @State private var firstError: String?
    @State private var secondError: String?

    private let firstURL = URL(
        string: "https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8"
    )!

    private let secondURL = URL(
        string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    )!

    private var playerColumns: [GridItem] {
        let count = horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoScreenHeading(
                    eyebrow: "MULTI-INSTANCE",
                    title: "Concurrent players",
                    subtitle: "Two independent player controllers running side by side."
                )

                LazyVGrid(columns: playerColumns, alignment: .leading, spacing: 16) {
                    playerSection(
                        title: "Player 1",
                        controller: firstController,
                        snapshot: firstSnapshot,
                        trackState: firstTrackState,
                        errorMessage: firstError,
                        controlsVisible: $firstControlsVisible,
                        isFullscreen: $isFirstPlayerFullscreen
                    )

                    playerSection(
                        title: "Player 2",
                        controller: secondController,
                        snapshot: secondSnapshot,
                        trackState: secondTrackState,
                        errorMessage: secondError,
                        controlsVisible: $secondControlsVisible,
                        isFullscreen: $isSecondPlayerFullscreen
                    )
                }
            }
            .demoReadableContent(maximumWidth: 1200)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .navigationTitle("Concurrent Players")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFirstPlayer()
        }
        .task {
            await loadSecondPlayer()
        }
        .task {
            for await snapshot in firstController.snapshots {
                firstSnapshot = snapshot
            }
        }
        .task {
            for await snapshot in secondController.snapshots {
                secondSnapshot = snapshot
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
                    await firstController.shutdown()
                    await secondController.shutdown()
                }
            }
        }
        .fullScreenCover(isPresented: $isFirstPlayerFullscreen) {
            DemoPlayerView(
                controller: firstController,
                snapshot: firstSnapshot,
                trackState: firstTrackState,
                isFullscreen: true,
                onFullscreen: {
                    isFirstPlayerFullscreen = false
                },
                controlsVisible: $firstControlsVisible,
                isActiveSurface: !isFirstPlayerFullscreen
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea(.container, edges: .all)
        }
        .fullScreenCover(isPresented: $isSecondPlayerFullscreen) {
            DemoPlayerView(
                controller: secondController,
                snapshot: secondSnapshot,
                trackState: secondTrackState,
                isFullscreen: true,
                onFullscreen: {
                    isSecondPlayerFullscreen = false
                },
                controlsVisible: $secondControlsVisible,
                isActiveSurface: !isSecondPlayerFullscreen
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea(.container, edges: .all)
        }
    }

    private func playerSection(
        title: String,
        controller: StreamPlayerController,
        snapshot: PlaybackSnapshot,
        trackState: PlayerTrackState,
        errorMessage: String?,
        controlsVisible: Binding<Bool>,
        isFullscreen: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(String(describing: snapshot.phase).capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.phase == .playing ? Color.green : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        snapshot.phase == .playing
                            ? Color.green.opacity(0.12)
                            : Color(uiColor: .tertiarySystemFill),
                        in: Capsule()
                    )
            }

            DemoPlayerView(
                controller: controller,
                snapshot: snapshot,
                trackState: trackState,
                isFullscreen: false,
                onFullscreen: {
                    isFullscreen.wrappedValue = true
                },
                controlsVisible: controlsVisible,
                isActiveSurface: !isFullscreen.wrappedValue
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .demoCardSurface()
    }

    private func loadFirstPlayer() async {
        firstTrackState.prepareForNewSource()
        await load(
            firstURL,
            using: firstController,
            playerName: "Player 1"
        )
    }

    private func loadSecondPlayer() async {
        secondTrackState.prepareForNewSource()
        await load(
            secondURL,
            using: secondController,
            playerName: "Player 2"
        )
    }

    private func load(
        _ url: URL,
        using controller: StreamPlayerController,
        playerName: String
    ) async {
        let handle = controller.load(MediaSource(url: url))

        do {
            try await handle.waitUntilReady()
            try Task.checkCancellation()
            try await controller.play()
        } catch {
            guard !Task.isCancelled else {
                return
            }

            setError(error.localizedDescription, for: playerName)
        }
    }

    private func setError(_ message: String, for playerName: String) {
        if playerName == "Player 1" {
            firstError = message
        } else {
            secondError = message
        }
    }
}
