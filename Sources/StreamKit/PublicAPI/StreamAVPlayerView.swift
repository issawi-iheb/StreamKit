//
//  StreamAVPlayerView.swift
//  StreamKit
//

#if os(iOS)

import AVKit
import Combine
import SwiftUI
import UIKit

/// Owns AVKit presentation and restoration state for one playback session.
/// Retain it outside the player screen so it survives SwiftUI view removal.
@MainActor
public final class StreamAVPlayerPresentationController: NSObject, ObservableObject {
    @Published public private(set) var state: StreamPictureInPictureState = .idle

    public var restorationHandler: StreamPictureInPictureRestorationHandler

    private weak var mountedViewController: AVPlayerViewController?
    private weak var pendingViewController: AVPlayerViewController?
    private var retainedViewController: AVPlayerViewController?
    private var pendingPlayer: AVPlayer?
    private var hasPendingPlayer = false
    private let stopWaiters = PictureInPictureStopWaiters()
    public var dismissalBehavior: StreamPictureInPictureDismissalBehavior = .pausePlayback

    private weak var playbackController: StreamPlayerController?
    private weak var pendingPlaybackController: StreamPlayerController?
    private let isApplicationInBackground: @MainActor () -> Bool
    private var stopRequestedByHost = false

    public convenience init(
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler
    ) {
        self.init(
            restorationHandler: restorationHandler,
            isApplicationInBackground: PictureInPictureDismissalPolicy
                .systemApplicationIsInBackground
        )
    }

    init(
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler,
        isApplicationInBackground: @escaping @MainActor () -> Bool
    ) {
        self.restorationHandler = restorationHandler
        self.isApplicationInBackground = isApplicationInBackground
        super.init()
    }
    
    func bind(to controller: StreamPlayerController) {
        guard playbackController !== controller else {
            pendingPlaybackController = nil
            return
        }

        guard state == .idle else {
            pendingPlaybackController = controller
            return
        }

        playbackController = controller
    }

    /// Waits until AVKit reports that PiP has stopped or failed to start.
    /// This does not request a stop; `AVPlayerViewController` owns that action.
    /// Cancellation stops this wait and does not affect the PiP session.
    public func waitUntilStopped() async throws {
        try await stopWaiters.waitUntilStopped {
            self.state == .idle
        }
    }

    fileprivate func updatePlayer(
        _ player: AVPlayer?,
        on viewController: AVPlayerViewController
    ) {
        guard state != .idle,
              retainedViewController === viewController else {
            viewController.player = player
            return
        }

        pendingPlayer = player
        hasPendingPlayer = true
    }

    /// Call before a host-initiated PiP stop, if the host has such a stop flow.
    public func markPictureInPictureStopRequestedByHost() {
        stopRequestedByHost = true
    }

    func attach(_ viewController: AVPlayerViewController) {
        if state != .idle,
           let retainedViewController,
           retainedViewController !== viewController {
            pendingViewController = viewController
            return
        }

        mountedViewController = viewController
        retainedViewController = viewController
        viewController.delegate = self
    }

    fileprivate func detach(_ viewController: AVPlayerViewController) {
        if pendingViewController === viewController {
            pendingViewController = nil
            return
        }
        guard mountedViewController === viewController else { return }
        mountedViewController = nil
        if state == .idle {
            viewController.delegate = nil
            retainedViewController = nil
        }
    }
}

extension StreamAVPlayerPresentationController: AVPlayerViewControllerDelegate {
    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willStartPictureInPictureWith proposedViewController: UIViewController
    ) {
        guard isCurrent(playerViewController) else { return }

        stopRequestedByHost = false
        state = .starting
    }

    public func playerViewControllerDidStartPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        guard isCurrent(playerViewController) else { return }

        state = .active
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        guard isCurrent(playerViewController) else { return }

        finish(playerViewController)
    }

    public func playerViewControllerWillStopPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        guard isCurrent(playerViewController) else { return }

        state = .stopping
    }

    public func playerViewControllerDidStopPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        guard isCurrent(playerViewController) else { return }

        let shouldPause = PictureInPictureDismissalPolicy(
            behavior: dismissalBehavior,
            isApplicationInBackground: isApplicationInBackground
        )
        .shouldPausePlayback(stopRequestedByHost: stopRequestedByHost)

        let controller = playbackController

        finish(playerViewController)

        if shouldPause, let controller {
            Task { @MainActor in
                await controller.pause()
            }
        }
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        guard isCurrent(playerViewController) else {
            completionHandler(false)
            return
        }

        let gate = StreamPictureInPictureRestorationCompletion(completionHandler)
        restorationHandler { restored in gate.call(restored) }
    }

    private func isCurrent(_ viewController: AVPlayerViewController) -> Bool {
        retainedViewController === viewController
    }

    private func finish(_ viewController: AVPlayerViewController) {
        state = .idle
        stopRequestedByHost = false
        stopWaiters.resumeAll()

        if hasPendingPlayer, retainedViewController === viewController {
            viewController.player = pendingPlayer
            pendingPlayer = nil
            hasPendingPlayer = false
        }

        if let pendingPlaybackController {
            playbackController = pendingPlaybackController
            self.pendingPlaybackController = nil
        }

        if mountedViewController !== viewController {
            viewController.delegate = nil

            if retainedViewController === viewController {
                retainedViewController = nil
            }
        }

        if let pendingViewController {
            attach(pendingViewController)
            self.pendingViewController = nil
        }
    }

}

/// Presents a StreamKit player with Apple's standard AVKit controls.
/// The presentation controller must be retained for the playback session,
/// outside this view's navigation destination, so PiP restoration survives
/// removal of the source SwiftUI view.
@MainActor
public struct StreamAVPlayerView: UIViewControllerRepresentable {
    private let controller: StreamPlayerController
    private let presentationController: StreamAVPlayerPresentationController
    private let automaticallyStartsPictureInPictureWhenLeavingApp: Bool

    public init(
        controller: StreamPlayerController,
        presentationController: StreamAVPlayerPresentationController,
        automaticallyStartsPictureInPictureWhenLeavingApp: Bool = false
    ) {
        self.controller = controller
        self.presentationController = presentationController
        self.automaticallyStartsPictureInPictureWhenLeavingApp =
            automaticallyStartsPictureInPictureWhenLeavingApp
    }

    public func makeCoordinator() -> StreamAVPlayerPresentationController {
        presentationController
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let viewController = AVPlayerViewController()
        viewController.player = controller.renderingPlayer
        viewController.allowsPictureInPicturePlayback = true
        viewController.canStartPictureInPictureAutomaticallyFromInline =
            automaticallyStartsPictureInPictureWhenLeavingApp
        context.coordinator.bind(to: controller)
        context.coordinator.attach(viewController)
        return viewController
    }

    public func updateUIViewController(
        _ viewController: AVPlayerViewController,
        context: Context
    ) {
        context.coordinator.updatePlayer(controller.renderingPlayer, on: viewController)
        viewController.canStartPictureInPictureAutomaticallyFromInline =
            automaticallyStartsPictureInPictureWhenLeavingApp
        context.coordinator.bind(to: controller)
        context.coordinator.attach(viewController)
    }

    public static func dismantleUIViewController(
        _ viewController: AVPlayerViewController,
        coordinator: StreamAVPlayerPresentationController
    ) {
        coordinator.detach(viewController)
    }
}
#endif
