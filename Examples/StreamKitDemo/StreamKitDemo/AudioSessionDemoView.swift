import AVFAudio
import StreamKit
import SwiftUI

@MainActor
struct AudioSessionDemoView: View {
    @State private var controller = StreamPlayerController(
        configuration: PlayerConfiguration(
            automaticallyResumesAfterAudioInterruption: true
        )
    )
    @State private var snapshot = PlaybackSnapshot(
        phase: .idle,
        intent: .pause
    )
    @State private var trackState = PlayerTrackState()
    @State private var errorMessage: String?
    @State private var isFullscreen = false
    @State private var controlsVisible = true

    private let sourceURL = URL(
        string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    )!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoScreenHeading(
                    eyebrow: "AUDIO",
                    title: "Sessions & interruptions",
                    subtitle: "See how playback intent and iOS interruption signals work together."
                )

                DemoPlayerView(
                    controller: controller,
                    snapshot: snapshot,
                    trackState: trackState,
                    isFullscreen: false,
                    onFullscreen: {
                        isFullscreen = true
                    },
                    controlsVisible: $controlsVisible,
                    isActiveSurface: !isFullscreen
                )

                DemoPanel("Resume policy", symbol: "waveform") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The demo configures the shared audio session for playback and enables iOS background audio. StreamKit resumes only when playback was requested before the interruption and iOS permits it.")
                        Text("Try playback, lock the device, or trigger an interruption. If you pause during it, playback stays paused when it ends.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }

                LabeledContent("Playback phase", value: String(describing: snapshot.phase))
                    .accessibilityIdentifier("audio-session-playback-phase")
                LabeledContent("Playback intent", value: String(describing: snapshot.intent))

                DemoPanel("Simulated interruption checks", symbol: "waveform") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("These controls send test notifications to StreamKit. They verify its pause/resume policy, not a real system interruption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Simulate interruption began") {
                            postInterruption(.began)
                        }
                        .buttonStyle(.bordered)

                        Button("End interruption — resume allowed") {
                            postInterruption(.ended, options: [.shouldResume])
                        }
                        .buttonStyle(.bordered)

                        Button("End interruption — resume not allowed") {
                            postInterruption(.ended)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .demoReadableContent(maximumWidth: 920)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .navigationTitle("Audio Session")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isFullscreen) {
            DemoPlayerView(
                controller: controller,
                snapshot: snapshot,
                trackState: trackState,
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
        .task {
            do {
                try await DemoPlaybackAudioSession.configureAndActivate()

                trackState.prepareForNewSource()
                let handle = controller.load(MediaSource(url: sourceURL))
                try await handle.waitUntilReady()
                try await controller.play()
            } catch {
                guard !Task.isCancelled else { return }
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

    private func postInterruption(
        _ type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions = []
    ) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: type.rawValue
        ]
        if type == .ended {
            userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }
}
