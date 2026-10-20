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

    private let sourceURL = URL(
        string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    )!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                Text("Audio session and interruption handling")
                    .font(.title2.bold())

                Text("The demo app configures the shared audio session for playback and enables the iOS background-audio mode. StreamKit observes audio interruptions and resumes only when playback was requested before the interruption and iOS says it may resume.")

                Text("Try starting playback, locking the device, or triggering an audio interruption. If you pause during the interruption, StreamKit keeps playback paused when it ends.")
                    .foregroundStyle(.secondary)

                LabeledContent("Playback phase", value: String(describing: snapshot.phase))
                    .accessibilityIdentifier("audio-session-playback-phase")
                LabeledContent("Playback intent", value: String(describing: snapshot.intent))

                GroupBox("Simulated interruption checks") {
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
            .padding()
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
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        }
        .task {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try await activate(session)

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

    private func activate(_ session: AVAudioSession) async throws {
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.activate(options: []) { activated, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if activated {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AudioSessionActivationError.activationFailed)
                    }
                }
            }
        } else {
            // iOS 16–26 have no asynchronous activation API. Run the legacy
            // call away from the UI thread; newer iOS uses the system async API above.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try session.setActive(true)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
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

private enum AudioSessionActivationError: Error {
    case activationFailed
}
