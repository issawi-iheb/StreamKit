import AVFAudio
import StreamKit
import SwiftUI

@MainActor
struct PresentationDemoView: View {

    @State private var controller = StreamPlayerController()
    @StateObject private var pictureInPictureController =
        StreamPictureInPictureController()

    @State private var snapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )

    @State private var errorMessage: String?
    @State private var usesSystemPlayer = true
    @State private var automaticallyStartsPictureInPicture = false
    @State private var isFullscreenPresented = false
    @State private var didRestoreFromPictureInPicture = false

    private let sourceURL = URL(
        string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            ZStack(alignment: .bottomTrailing) {
                Group {
                    if usesSystemPlayer {
                        StreamAVPlayerView(
                            controller: controller,
                            automaticallyStartsPictureInPictureWhenLeavingApp:
                                automaticallyStartsPictureInPicture
                        ) { completion in
                            didRestoreFromPictureInPicture = true
                            completion(true)
                        }
                        .accessibilityIdentifier("presentation-system-player")
                    } else {
                        StreamVideoView(
                            controller: controller,
                            pictureInPictureController: pictureInPictureController
                        )
                        .accessibilityIdentifier("presentation-custom-player")
                    }
                }
                .frame(height: 240)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button {
                    isFullscreenPresented = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.65))
                        .clipShape(Circle())
                }
                .padding(12)
                .accessibilityLabel("Enter fullscreen")
            }

            Text("StreamKit Player and Picture in Picture")
                .font(.title2.bold())

            Picker("Player controls", selection: $usesSystemPlayer) {
                Text("System AVKit").tag(true)
                Text("Custom").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("presentation-renderer-picker")

            Toggle(
                "Automatically start PiP when leaving the app",
                isOn: $automaticallyStartsPictureInPicture
            )
            .accessibilityIdentifier("presentation-automatic-pip")
            .disabled(!usesSystemPlayer)

            Text(
                "Use the fullscreen button to expand the player. " +
                "Start PiP while playback is active, then switch apps."
            )
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            try await controller.play()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        do {
                            try await controller.pause()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)

                if !usesSystemPlayer {
                    Button {
                        pictureInPictureController.startPictureInPicture()
                    } label: {
                        Label("Start PiP", systemImage: "pip")
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        !pictureInPictureController.isPictureInPicturePossible
                    )
                    .accessibilityIdentifier("presentation-start-pip")
                }
            }

            if !usesSystemPlayer && !pictureInPictureController.isSupported {
                Text("Picture in Picture is not supported on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !usesSystemPlayer && !pictureInPictureController.isPictureInPicturePossible {
                Text("PiP is not currently available for this player.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LabeledContent(
                "Playback phase",
                value: String(describing: snapshot.phase)
            )
            .accessibilityIdentifier("presentation-playback-phase")

            LabeledContent(
                "PiP active",
                value: pictureInPictureController.isPictureInPictureActive
                    ? "Yes"
                    : "No"
            )

            if didRestoreFromPictureInPicture {
                Label(
                    "Returned from Picture in Picture",
                    systemImage: "pip.exit"
                )
                .font(.footnote)
                .accessibilityIdentifier("presentation-pip-restored")
            }

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("presentation-error")
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("StreamKit & PiP")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isFullscreenPresented) {
            FullscreenDemoPlayerView(
                controller: controller,
                pictureInPictureController: pictureInPictureController,
                onClose: {
                    isFullscreenPresented = false
                }
            )
        }
        .task {
            await observeSnapshots()
        }
        .task {
            await loadPlaybackIfNeeded()
        }
    }

    private func observeSnapshots() async {
        for await newSnapshot in controller.snapshots {
            guard !Task.isCancelled else { return }
            snapshot = newSnapshot
        }
    }

    private func loadPlaybackIfNeeded() async {
        guard snapshot.phase == .idle else { return }

        do {
            try await DemoPlaybackAudioSession.configureAndActivate()

            guard !Task.isCancelled else { return }

            let load = controller.load(MediaSource(url: sourceURL))
            try await load.waitUntilReady()

            guard !Task.isCancelled else { return }

            try await controller.play()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Fullscreen Player

@MainActor
private struct FullscreenDemoPlayerView: View {

    let controller: StreamPlayerController
    let pictureInPictureController: StreamPictureInPictureController
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            StreamVideoView(
                controller: controller,
                pictureInPictureController: pictureInPictureController
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.65))
                    .clipShape(Circle())
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
            .accessibilityLabel("Close fullscreen")
        }
        .statusBarHidden()
    }
}
