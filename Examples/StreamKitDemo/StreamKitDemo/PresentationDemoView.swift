import AVFAudio
import StreamKit
import SwiftUI

@MainActor
struct PresentationDemoView: View {

    let session: PresentationDemoSession

    private var controller: StreamPlayerController {
        session.playerController
    }

    private var pictureInPictureController: StreamPictureInPictureController {
        session.pictureInPictureController
    }

    @State private var snapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )

    @State private var errorMessage: String?
    @State private var usesSystemPlayer = true
    @State private var automaticallyStartsPictureInPicture = false
    @State private var isFullscreenPresented = false

    private let sourceURL = URL(
        string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    )!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if usesSystemPlayer {
                            StreamAVPlayerView(
                                controller: controller,
                                presentationController: session.systemPresentationController,
                                automaticallyStartsPictureInPictureWhenLeavingApp:
                                    automaticallyStartsPictureInPicture
                            )
                            .accessibilityIdentifier("presentation-system-player")
                        } else {
                            StreamVideoView(
                                controller: controller,
                                pictureInPictureController: pictureInPictureController
                            )
                            .accessibilityIdentifier("presentation-custom-player")
                        }
                    }

                    if !usesSystemPlayer {
                        Button {
                            isFullscreenPresented = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                        .padding(12)
                        .accessibilityLabel("Enter fullscreen")
                    }
                }
                .demoPlayerSurface()

                PlaybackDiagnosticsPanel(controller: controller)

                DemoScreenHeading(
                    eyebrow: "PRESENTATION",
                    title: "Picture in Picture",
                    subtitle: "Compare Apple’s AVKit controls with StreamKit’s custom player."
                )
                .accessibilityIdentifier("presentation-player-interface-ready")

                VStack(alignment: .leading, spacing: 12) {
                    Label("Player style", systemImage: "rectangle.on.rectangle")
                        .font(.headline)

                    Picker("Player controls", selection: $usesSystemPlayer) {
                        Text("System AVKit").tag(true)
                        Text("Custom").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("presentation-renderer-picker")
                }
                .demoCardSurface()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Playback", systemImage: "play.circle")
                        .font(.headline)

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
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await controller.pause() }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !usesSystemPlayer {
                        Button {
                            pictureInPictureController.startPictureInPicture()
                        } label: {
                            Label("Start Picture in Picture", systemImage: "pip")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!pictureInPictureController.isPictureInPicturePossible)
                        .accessibilityIdentifier("presentation-start-pip")
                    }
                }
                .demoCardSurface()

                VStack(alignment: .leading, spacing: 12) {
                    Label("PiP behavior", systemImage: "pip")
                        .font(.headline)

                    Toggle(
                        "Start PiP when leaving the app",
                        isOn: $automaticallyStartsPictureInPicture
                    )
                    .accessibilityIdentifier("presentation-automatic-pip")
                    .disabled(!usesSystemPlayer)

                    Text(usesSystemPlayer
                         ? "Available with AVKit. Start playback, then leave the app to test it."
                         : "Custom PiP starts from its button above while playback is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !usesSystemPlayer && !pictureInPictureController.isSupported {
                        Label("PiP is not supported on this device.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("presentation-pip-unsupported")
                    } else if !usesSystemPlayer && !pictureInPictureController.isPictureInPicturePossible {
                        Label("PiP is not currently available for this player.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .demoCardSurface()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Session status", systemImage: "waveform.path")
                        .font(.headline)

                    LabeledContent("Playback", value: String(describing: snapshot.phase).capitalized)
                        .accessibilityIdentifier("presentation-playback-phase")
                    Divider()
                    LabeledContent("Picture in Picture", value: activePictureInPictureState == .idle ? "Inactive" : "Active")
                        .accessibilityIdentifier("presentation-pip-state")
                }
                .demoCardSurface()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("presentation-error")
                }
            }
            .demoReadableContent(maximumWidth: 1080)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("StreamKit & PiP")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.playerInterfaceDidAppear()
        }
        .onDisappear {
            session.playerInterfaceDidDisappear(
                isFullscreenPresented: isFullscreenPresented
            )
        }
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

    private var activePictureInPictureState: StreamPictureInPictureState {
        usesSystemPlayer
            ? session.systemPresentationController.state
            : pictureInPictureController.state
    }

    private func observeSnapshots() async {
        for await newSnapshot in controller.snapshots {
            guard !Task.isCancelled else { return }
            snapshot = newSnapshot
        }
    }

    private func loadPlaybackIfNeeded() async {
        guard controller.snapshot.phase == .idle else { return }

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
