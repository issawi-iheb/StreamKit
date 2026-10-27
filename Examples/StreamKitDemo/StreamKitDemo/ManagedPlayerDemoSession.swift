import Combine
import StreamKit
import SwiftUI

/// Keeps the managed playback session alive when its player route is removed
/// for Picture in Picture.
@MainActor
final class ManagedPlayerDemoSession: ObservableObject {
    @Published private(set) var playerSession: StreamPlayerSession?
    @Published var isPlayerPresented = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPreparingPlayer = false

    private let restorationCoordinator = DemoPlayerRouteRestorationCoordinator()
    private var pictureInPictureObservation: AnyCancellable?

    init() {
        restorationCoordinator.requestPlayerRoute = { [weak self] in
            guard let self, self.playerSession != nil else { return }
            self.isPlayerPresented = true
        }
    }

    func startPlayerRoute() {
        if playerSession != nil {
            isPlayerPresented = true
            return
        }
        guard !isPreparingPlayer else { return }

        isPreparingPlayer = true
        errorMessage = nil
        Task { @MainActor in
            defer { isPreparingPlayer = false }

            do {
                try await DemoPlaybackAudioSession.configureAndActivate()
            } catch {
                errorMessage = error.localizedDescription
                return
            }

            let source = MediaSource(
                url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                presentationKind: .onDemand
            )
            let restorationCoordinator = self.restorationCoordinator
            let session = StreamPlayerSession(
                source: source,
                automaticallyStartsPictureInPictureWhenLeavingApp: true,
                restorationHandler: { completion in
                    restorationCoordinator.restorePlayerInterface(completion)
                }
            )
            playerSession = session
            observePictureInPictureState(from: session)
            isPlayerPresented = true
        }
    }

    func playerInterfaceDidAppear() {
        restorationCoordinator.playerInterfaceDidAppear()
    }

    func playerInterfaceDidDisappear() {
        guard !isPlayerPresented else { return }
        restorationCoordinator.playerInterfaceDidDisappear()
    }

    func clearError() {
        errorMessage = nil
    }

    func playerRouteDidClose() {
        guard let session = playerSession else { return }
        releaseSessionIfPictureInPictureIsIdle(session)
    }

    private func observePictureInPictureState(from session: StreamPlayerSession) {
        pictureInPictureObservation = session.$pictureInPictureState
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self, weak session] state in
                guard state == .idle else { return }
                Task { @MainActor [weak self, weak session] in
                    guard let self, let session,
                          !self.isPlayerPresented,
                          self.playerSession === session else {
                        return
                    }
                    self.releaseSessionIfPictureInPictureIsIdle(session)
                }
            }
    }

    private func releaseSessionIfPictureInPictureIsIdle(
        _ session: StreamPlayerSession
    ) {
        guard !isPlayerPresented,
              session.pictureInPictureState == .idle,
              playerSession === session else { return }

        playerSession = nil
        pictureInPictureObservation = nil
        Task { @MainActor in
            try? await session.shutdown()
        }
    }
}
