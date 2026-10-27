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

    private let restorationCoordinator: DemoPlayerRouteRestorationCoordinator
    private var pictureInPictureObservation: AnyCancellable?

    init() {
        let restorationCoordinator = DemoPlayerRouteRestorationCoordinator()
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


    func playerInterfaceDidDisappear(isFullscreenPresented: Bool = false) {
        restorationCoordinator.playerInterfaceDidDisappear()

        // A fullscreen player is still an active playback interface.
        guard !isFullscreenPresented else { return }

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
