import Combine
import StreamKit
import SwiftUI

/// Keeps playback and presentation owners alive while the player route is absent.
@MainActor
final class PresentationDemoSession: ObservableObject {
    let playerController: StreamPlayerController
    let pictureInPictureController: StreamPictureInPictureController
    let systemPresentationController: StreamAVPlayerPresentationController

    @Published var isPlayerPresented = false
    @Published private(set) var pictureInPictureState: StreamPictureInPictureState = .idle

    private let restorationCoordinator: PresentationDemoRestorationCoordinator
    private var pictureInPictureObservation: AnyCancellable?

    init() {
        let restorationCoordinator = PresentationDemoRestorationCoordinator()
        self.restorationCoordinator = restorationCoordinator
        self.playerController = StreamPlayerController()
        self.pictureInPictureController = StreamPictureInPictureController(
            restorationHandler: { completion in
                restorationCoordinator.restorePlayerInterface(completion)
            }
        )
        self.systemPresentationController = StreamAVPlayerPresentationController(
            restorationHandler: { completion in
                restorationCoordinator.restorePlayerInterface(completion)
            }
        )

        restorationCoordinator.requestPlayerRoute = { [weak self] in
            self?.isPlayerPresented = true
        }
        pictureInPictureObservation = pictureInPictureController.$state
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.pictureInPictureState = state
                }
            }
    }

    func playerInterfaceDidAppear() {
        restorationCoordinator.playerInterfaceDidAppear()
    }

    func playerInterfaceDidDisappear() {
        restorationCoordinator.playerInterfaceDidDisappear()

        // Keep playback alive only while either PiP implementation owns the
        // presentation. Leaving the demo route for the menu should stop the
        // underlying stream once there is no PiP session to preserve.
        Task { [weak self] in
            guard let self else { return }
            guard pictureInPictureController.state == .idle,
                  systemPresentationController.state == .idle else {
                return
            }
            await playerController.pause()
        }
    }

    func playerInterfaceRestorationFailed() {
        restorationCoordinator.playerInterfaceRestorationFailed()
    }
}

/// Delays AVKit's success response until SwiftUI has shown the player route.
@MainActor
final class PresentationDemoRestorationCoordinator {
    var requestPlayerRoute: (@MainActor () -> Void)?

    private(set) var isPlayerInterfaceAvailable = false
    private var pendingCompletions: [@Sendable (Bool) -> Void] = []

    func restorePlayerInterface(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard !isPlayerInterfaceAvailable else {
            completion(true)
            return
        }

        let shouldRequestRoute = pendingCompletions.isEmpty
        pendingCompletions.append(completion)
        guard let requestPlayerRoute else {
            let completions = pendingCompletions
            pendingCompletions.removeAll()
            completions.forEach { $0(false) }
            return
        }
        if shouldRequestRoute {
            requestPlayerRoute()
        }
    }

    func playerInterfaceDidAppear() {
        isPlayerInterfaceAvailable = true
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        completions.forEach { $0(true) }
    }

    func playerInterfaceDidDisappear() {
        isPlayerInterfaceAvailable = false
    }

    func playerInterfaceRestorationFailed() {
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        completions.forEach { $0(false) }
    }
}
