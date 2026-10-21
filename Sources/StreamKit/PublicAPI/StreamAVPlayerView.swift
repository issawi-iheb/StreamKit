//
//  StreamAVPlayerView.swift
//  StreamKit
//

#if os(iOS)

import AVKit
import Combine
import SwiftUI

/// Owns AVKit presentation and restoration state for one playback session.
/// Retain it outside the player screen so it survives SwiftUI view removal.
@MainActor
public final class StreamAVPlayerPresentationController: NSObject, ObservableObject {
    @Published public private(set) var state: StreamPictureInPictureState = .idle

    public var restorationHandler: StreamPictureInPictureRestorationHandler

    private weak var mountedViewController: AVPlayerViewController?
    private weak var pendingViewController: AVPlayerViewController?
    private var retainedViewController: AVPlayerViewController?

    public init(
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler
    ) {
        self.restorationHandler = restorationHandler
        super.init()
    }

    fileprivate func attach(_ viewController: AVPlayerViewController) {
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
        state = .starting
    }

    public func playerViewControllerDidStartPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        state = .active
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        finish(playerViewController)
    }

    public func playerViewControllerWillStopPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        state = .stopping
    }

    public func playerViewControllerDidStopPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        finish(playerViewController)
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        let gate = StreamPictureInPictureRestorationCompletion(completionHandler)
        restorationHandler { restored in gate.call(restored) }
    }

    private func finish(_ viewController: AVPlayerViewController) {
        state = .idle
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
        context.coordinator.attach(viewController)
        return viewController
    }

    public func updateUIViewController(
        _ viewController: AVPlayerViewController,
        context: Context
    ) {
        if viewController.player !== controller.renderingPlayer {
            viewController.player = controller.renderingPlayer
        }
        viewController.canStartPictureInPictureAutomaticallyFromInline =
            automaticallyStartsPictureInPictureWhenLeavingApp
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
