import Combine
import StreamKit
import SwiftUI

/// Owns the standalone player while its route is visible or custom PiP is active.
@MainActor
final class StandalonePlayerDemoSession: ObservableObject {
    @Published private(set) var playerController = StreamPlayerController()
    @Published private(set) var pictureInPictureController:
        StreamPictureInPictureController
    @Published private(set) var snapshot = PlaybackSnapshot(phase: .idle, intent: .pause)
    @Published private(set) var errorMessage: String?
    private let restorationCoordinator = PresentationDemoRestorationCoordinator()

    let trackState = PlayerTrackState()

    private let sourceURL = URL(
        string: "https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8"
    )!
    private var isPlayerRouteVisible = false
    private var hasPresentedPlayerRoute = false
    private var isShutdown = false
    private var isShuttingDown = false
    private var sessionGeneration = UUID()
    private var loadHandle: LoadHandle?
    private var loadTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    var requestPlayerRoute: (@MainActor () -> Void)?

    init() {
        let restorationCoordinator = self.restorationCoordinator

        self.pictureInPictureController = StreamPictureInPictureController(
            restorationHandler: { completion in
                restorationCoordinator.restorePlayerInterface(completion)
            }
        )

        restorationCoordinator.requestPlayerRoute = { [weak self] in
            self?.requestPlayerRoute?()
        }
    }

    func playerRouteDidAppear() {
        isPlayerRouteVisible = true
        hasPresentedPlayerRoute = true

        if isShutdown || isShuttingDown {
            createFreshSession()
        }

        observeSnapshots()
        loadAndPlayIfNeeded()
    }

    func playerRouteDidDisappear() {
        isPlayerRouteVisible = false

        // Keep the playback controller alive while PiP or restoration
        // may still depend on the existing playback session.
        guard pictureInPictureController.state == .idle else { return }

        Task { @MainActor [weak self] in
            guard let self,
                  !self.isPlayerRouteVisible,
                  self.pictureInPictureController.state == .idle
            else {
                return
            }

            await self.playerController.pause()
        }
    }

    private func observeSnapshots() {
        guard snapshotTask == nil else { return }
        let controller = playerController
        let generation = sessionGeneration
        snapshotTask = Task { [weak self] in
            for await snapshot in controller.snapshots {
                guard !Task.isCancelled,
                      let self,
                      self.sessionGeneration == generation else { return }
                self.snapshot = snapshot
            }
        }
    }

    private func loadAndPlayIfNeeded() {
        guard loadTask == nil,
              playerController.snapshot.phase == .idle else { return }

        let controller = playerController
        let sourceURL = sourceURL
        let generation = sessionGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.sessionGeneration == generation {
                    self.loadTask = nil
                }
            }

            do {
                try await DemoPlaybackAudioSession.configureAndActivate()
                guard !Task.isCancelled else { return }

                self.trackState.prepareForNewSource()
                let handle = controller.load(MediaSource(url: sourceURL))
                guard self.sessionGeneration == generation else {
                    handle.cancel()
                    return
                }
                self.loadHandle = handle
                defer {
                    if self.sessionGeneration == generation {
                        self.loadHandle = nil
                    }
                }
                try await handle.waitUntilReady()

                guard !Task.isCancelled,
                      self.sessionGeneration == generation else { return }
                try await controller.play()
            } catch {
                guard !Task.isCancelled,
                      self.sessionGeneration == generation else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func shutdownIfRouteAndPiPAreInactive() async {
        guard !isPlayerRouteVisible,
              pictureInPictureController.state == .idle,
              !isShutdown,
              !isShuttingDown else { return }

        isShuttingDown = true
        let generation = sessionGeneration
        let controller = playerController
        loadTask?.cancel()
        loadHandle?.cancel()
        await controller.shutdown()
        guard sessionGeneration == generation else { return }
        snapshotTask?.cancel()
        snapshotTask = nil
        isShutdown = true
        isShuttingDown = false
    }

    private func createFreshSession() {
        sessionGeneration = UUID()

        snapshotTask?.cancel()
        loadTask?.cancel()
        loadHandle?.cancel()

        snapshotTask = nil
        loadTask = nil
        loadHandle = nil

        playerController = StreamPlayerController()
        pictureInPictureController = makePictureInPictureController()

        snapshot = PlaybackSnapshot(phase: .idle, intent: .pause)
        errorMessage = nil
        trackState.prepareForNewSource()

        isShutdown = false
        isShuttingDown = false
    }

    func playerInterfaceDidAppear() {
        restorationCoordinator.playerInterfaceDidAppear()
    }

    func playerInterfaceDidDisappear() {
        restorationCoordinator.playerInterfaceDidDisappear()
    }

    private func makePictureInPictureController()
        -> StreamPictureInPictureController {
        let coordinator = restorationCoordinator

        return StreamPictureInPictureController(
            restorationHandler: { completion in
                coordinator.restorePlayerInterface(completion)
            }
        )
    }
}
