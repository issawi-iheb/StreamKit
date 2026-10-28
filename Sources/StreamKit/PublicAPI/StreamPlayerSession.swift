#if os(iOS)

import Combine
import Foundation

/// A managed playback session for the simple SwiftUI integration.
///
/// The session loads its initial source and owns the playback and AVKit
/// presentation controllers. Retain it above the player route when playback
/// or Picture in Picture must continue after that route is removed.
@MainActor
public final class StreamPlayerSession: ObservableObject {

    /// The controller used by the managed view. Access it for advanced controls
    /// that the session does not wrap, such as track selection.
    public let controller: StreamPlayerController

    /// A bounded stream of diagnostic events from the managed session's player.
    /// Recent events include startup activity that occurred during initialization.
    public var diagnosticEvents: AsyncStream<PlaybackDiagnosticEvent> {
        controller.diagnosticEvents
    }

    /// AVFoundation performance metrics, including request and session summary
    /// values. See `StreamPlayerController.metrics` for buffering semantics.
    public var metrics: AsyncStream<PlaybackMetricEvent> {
        controller.metrics
    }

    /// AVKit presentation and Picture in Picture lifecycle for this session.
    public let presentationController: StreamAVPlayerPresentationController

    /// Whether AVKit should start PiP automatically when the app backgrounds.
    public let automaticallyStartsPictureInPictureWhenLeavingApp: Bool

    /// The latest playback state.
    @Published public private(set) var snapshot: PlaybackSnapshot

    /// The source currently assigned to this session.
    @Published public private(set) var source: MediaSource

    /// The current AVKit Picture in Picture lifecycle state.
    @Published public private(set) var pictureInPictureState: StreamPictureInPictureState

    private var snapshotTask: Task<Void, Never>?
    private var pictureInPictureStateObservation: AnyCancellable?

    /// Creates a session and begins loading its initial source.
    ///
    /// FairPlay and bearer credentials remain part of `source`'s request
    /// configuration and are supplied by the host app. The session uses
    /// AVKit's standard controls, including its Picture in Picture affordance.
    public init(
        source: MediaSource,
        configuration: PlayerConfiguration = .init(),
        automaticallyStartsPictureInPictureWhenLeavingApp: Bool = false,
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler = { completion in
            completion(false)
        },
        audioPlaybackFocusCoordinator: AudioPlaybackFocusCoordinator? = nil
    ) {
        let controller = StreamPlayerController(
            configuration: configuration,
            audioPlaybackFocusCoordinator: audioPlaybackFocusCoordinator
        )
        self.controller = controller
        let presentationController = StreamAVPlayerPresentationController(
            restorationHandler: restorationHandler
        )
        self.presentationController = presentationController
        self.automaticallyStartsPictureInPictureWhenLeavingApp =
            automaticallyStartsPictureInPictureWhenLeavingApp
        self.snapshot = controller.snapshot
        self.source = source
        self.pictureInPictureState = presentationController.state

        observeSnapshots(from: controller)
        observePictureInPictureState(from: presentationController)
        _ = controller.load(source)
    }

    /// Loads a replacement VOD or live source into this session.
    @discardableResult
    public func load(_ source: MediaSource) -> LoadHandle {
        self.source = source
        return controller.load(source)
    }

    /// Starts or resumes playback.
    public func play() async throws {
        try await controller.play()
    }

    /// Pauses playback.
    public func pause() async {
        await controller.pause()
    }

    /// Seeks to a position in seconds.
    public func seek(to time: TimeInterval) async throws {
        try await controller.seek(to: time)
    }

    /// Seeks to the live edge or to an offset behind it.
    public func seekToLiveEdge(offsetFromLive: TimeInterval = 0) async throws {
        try await controller.seekToLiveEdge(offsetFromLive: offsetFromLive)
    }

    /// Waits for AVKit to report that Picture in Picture has stopped.
    public func waitUntilPictureInPictureStops() async throws {
        try await presentationController.waitUntilStopped()
    }

    /// Waits for AVKit to finish Picture in Picture, then releases playback.
    /// If the wait is cancelled, the session remains alive and playback is not
    /// shut down.
    public func shutdown() async throws {
        try await presentationController.waitUntilStopped()
        snapshotTask?.cancel()
        snapshotTask = nil
        pictureInPictureStateObservation?.cancel()
        pictureInPictureStateObservation = nil
        await controller.shutdown()
    }

    private func observeSnapshots(from controller: StreamPlayerController) {
        let snapshots = controller.snapshots
        snapshotTask = Task { [weak self] in
            for await snapshot in snapshots {
                guard let self else { return }
                self.snapshot = snapshot
            }
        }
    }

    private func observePictureInPictureState(
        from presentationController: StreamAVPlayerPresentationController
    ) {
        pictureInPictureStateObservation = presentationController.$state
            .removeDuplicates()
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.pictureInPictureState = state
                }
            }
    }
}

#endif
