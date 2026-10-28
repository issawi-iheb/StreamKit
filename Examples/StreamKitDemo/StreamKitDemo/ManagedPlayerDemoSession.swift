import Combine
import StreamKit
import SwiftUI

/// Keeps the managed playback session alive when its player route is removed
/// for Picture in Picture.
@MainActor
final class ManagedPlayerDemoSession: ObservableObject {
    private enum RouteTransitionState {
        case stable
        case preparing
        case shuttingDown
    }

    typealias AudioSessionConfigurer = @MainActor () async throws -> Void
    typealias SessionFactory = @MainActor (DemoPlayerRouteRestorationCoordinator) -> StreamPlayerSession
    typealias SessionShutdown = @MainActor (StreamPlayerSession) async throws -> Void

    @Published private(set) var playerSession: StreamPlayerSession?
    @Published var isPlayerPresented = false
    @Published private(set) var errorMessage: String?
    @Published private var routeTransitionState: RouteTransitionState = .stable

    var canOpenPlayer: Bool {
        routeTransitionState == .stable
    }

    var playerEntryStatusLabel: String {
        switch routeTransitionState {
        case .stable:
            "Ready"
        case .preparing:
            "Opening"
        case .shuttingDown:
            "Closing"
        }
    }

    private let restorationCoordinator = DemoPlayerRouteRestorationCoordinator()
    private var pictureInPictureObservation: AnyCancellable?
    private let configureAudioSession: AudioSessionConfigurer
    private let makePlayerSession: SessionFactory
    private let shutdownPlayerSession: SessionShutdown

    init(
        configureAudioSession: @escaping AudioSessionConfigurer = {
            try await DemoPlaybackAudioSession.configureAndActivate()
        },
        makePlayerSession: @escaping SessionFactory = { restorationCoordinator in
            let source = MediaSource(
                url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
                presentationKind: .onDemand
            )
            return StreamPlayerSession(
                source: source,
                configuration: PlayerConfiguration(autoplay: true),
                automaticallyStartsPictureInPictureWhenLeavingApp: true,
                restorationHandler: { completion in
                    restorationCoordinator.restorePlayerInterface(completion)
                }
            )
        },
        shutdownPlayerSession: @escaping SessionShutdown = { session in
            try await session.shutdown()
        }
    ) {
        self.configureAudioSession = configureAudioSession
        self.makePlayerSession = makePlayerSession
        self.shutdownPlayerSession = shutdownPlayerSession

        restorationCoordinator.requestPlayerRoute = { [weak self] in
            guard let self, self.playerSession != nil else { return }
            self.isPlayerPresented = true
        }
    }

    func startPlayerRoute() {
        guard canOpenPlayer else { return }

        if playerSession != nil {
            isPlayerPresented = true
            return
        }

        routeTransitionState = .preparing
        errorMessage = nil
        Task { @MainActor in
            defer {
                if routeTransitionState == .preparing {
                    routeTransitionState = .stable
                }
            }

            do {
                try await configureAudioSession()
            } catch {
                errorMessage = error.localizedDescription
                return
            }

            let session = makePlayerSession(restorationCoordinator)
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
              session.presentationController.state == .idle,
              routeTransitionState != .shuttingDown,
              playerSession === session else { return }

        routeTransitionState = .shuttingDown
        playerSession = nil
        pictureInPictureObservation = nil
        Task { @MainActor in
            defer { routeTransitionState = .stable }
            do {
                try await shutdownPlayerSession(session)
            } catch {
                errorMessage = error.localizedDescription
                playerSession = session
                observePictureInPictureState(from: session)
            }
        }
    }
}
