//
//  ContentView.swift
//  StreamKitDemo
//
//  Created by Iheb on 13/10/2026.
//

import SwiftUI
import StreamKit

@MainActor
struct ContentView: View {
    @State private var controller = StreamPlayerController()

    @State private var snapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )

    @State private var errorMessage: String?
    @State private var isFullscreen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PlayerScreen(
                        controller: controller,
                        snapshot: snapshot,
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            PlayerScreen(
                controller: controller,
                snapshot: snapshot,
                isFullscreen: true,
                onFullscreen: {
                    isFullscreen = false
                }
            )
            .background(.black)
        }
        .task {
            let url = URL(
                string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
            )!

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
    }
}

// MARK: - Player Screen

@MainActor
private struct PlayerScreen: View {
    let controller: StreamPlayerController
    let snapshot: PlaybackSnapshot
    let isFullscreen: Bool
    let onFullscreen: () -> Void

    @State private var controlsVisible = true
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    private var duration: Double {
        max(snapshot.duration ?? 0, 1)
    }

    private var isPlaying: Bool {
        snapshot.phase == .playing || snapshot.phase == .waiting
    }

    var body: some View {
        Group {
            if isFullscreen {
                playerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                playerContent
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .background(.black)
        .onChange(of: snapshot.currentTime) { _, newTime in
            guard !isSeeking else { return }
            seekPosition = newTime
        }
        .onChange(of: snapshot.duration) { _, newDuration in
            guard !isSeeking, let newDuration else { return }
            seekPosition = min(snapshot.currentTime, newDuration)
        }
        .task(id: controlsVisible && isPlaying) {
            guard controlsVisible, isPlaying else { return }

            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }

    private var playerContent: some View {
        ZStack {
            Color.black

            StreamVideoView(controller: controller)
            if snapshot.phase == .waiting {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
                    .accessibilityLabel("Buffering")
                    .zIndex(1)
            }

            if controlsVisible {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.75), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            // Tap the video to show or hide the controls.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible.toggle()
                    }
                }
                .zIndex(1)

            if controlsVisible {
                controlsOverlay
                    .zIndex(2)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: snapshot.phase)
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Top controls
            HStack {
                if isFullscreen {
                    Button(action: onFullscreen) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Exit full screen")
                }

                Spacer()

                Text("STREAMKIT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 0)

            // Center playback controls
            HStack(spacing: 34) {
                skipButton(
                    seconds: -10,
                    symbol: "gobackward.10",
                    label: "Skip backward 10 seconds"
                )

                Button {
                    togglePlayback()
                } label: {
                    Image(
                        systemName: isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 28, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 66, height: 66)
                    .background(.white.opacity(0.2), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                skipButton(
                    seconds: 10,
                    symbol: "goforward.10",
                    label: "Skip forward 10 seconds"
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Bottom playback controls
            VStack(spacing: 8) {
                Slider(
                    value: $seekPosition,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isSeeking = editing

                        guard !editing else { return }

                        let target = seekPosition

                        Task {
                            do {
                                try await controller.seek(to: target)
                            } catch {
                                seekPosition = snapshot.currentTime
                            }
                        }
                    }
                )
                .tint(.red)
                .disabled(
                    snapshot.duration == nil ||
                    snapshot.phase == .idle ||
                    snapshot.phase == .loading
                )
                .accessibilityLabel("Playback position")

                HStack(spacing: 12) {
                    Text(
                        "\(formatTime(isSeeking ? seekPosition : snapshot.currentTime)) / \(formatTime(snapshot.duration ?? 0))"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)

                    Spacer()

                    if !isFullscreen {
                        Button(action: onFullscreen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Enter full screen")
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.clear)
    }

    private func skipButton(
        seconds: Double,
        symbol: String,
        label: String
    ) -> some View {
        Button {
            let target = min(
                max(snapshot.currentTime + seconds, 0),
                snapshot.duration ?? .greatestFiniteMagnitude
            )

            Task {
                do {
                    try await controller.seek(to: target)
                } catch {
                    // The current snapshot remains authoritative.
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .medium))
                .frame(width: 44, height: 50)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .disabled(
            snapshot.phase == .idle ||
            snapshot.phase == .loading
        )
    }

    private func togglePlayback() {
        Task {
            do {
                if isPlaying {
                    await controller.pause()
                } else {
                    try await controller.play()
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible = true
                }
            } catch {
                // Playback errors are reported through the controller.
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
