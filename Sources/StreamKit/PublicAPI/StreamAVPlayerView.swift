//
//  StreamAVPlayerView.swift
//  StreamKit
//

#if os(iOS)

import AVKit
import SwiftUI

/// Restores an app's player interface after a user closes Picture in Picture.
/// Call the completion with `true` after the interface is available again.
public typealias StreamAVPlayerRestorationHandler =
    @MainActor (@escaping @Sendable (Bool) -> Void) -> Void

/// Presents a StreamKit player with Apple's standard AVKit controls.
///
/// The system controls provide familiar playback, full-screen, AirPlay, and
/// Picture in Picture affordances where the OS and device support them. The
/// host application still owns audio-session configuration and the background
/// audio capability required for background playback and Picture in Picture.
/// Removing this view does not stop playback; the controller owns its lifetime.
@MainActor
public struct StreamAVPlayerView: UIViewControllerRepresentable {
    private let controller: StreamPlayerController
    private let automaticallyStartsPictureInPictureWhenLeavingApp: Bool
    private let restorationHandler: StreamAVPlayerRestorationHandler

    /// Creates an AVKit-backed player interface for a StreamKit controller.
    ///
    /// - Parameters:
    ///   - controller: The playback controller whose player AVKit presents.
    ///   - automaticallyStartsPictureInPictureWhenLeavingApp: Whether AVKit may
    ///     automatically enter Picture in Picture when this inline player is
    ///     playing and the app leaves the foreground. Defaults to `false`.
    ///   - restorationHandler: Restores the app's player interface when the
    ///     user returns from PiP. The default assumes this view remains visible.
    public init(
        controller: StreamPlayerController,
        automaticallyStartsPictureInPictureWhenLeavingApp: Bool = false,
        restorationHandler: @escaping StreamAVPlayerRestorationHandler = { completion in
            completion(true)
        }
    ) {
        self.controller = controller
        self.automaticallyStartsPictureInPictureWhenLeavingApp =
            automaticallyStartsPictureInPictureWhenLeavingApp
        self.restorationHandler = restorationHandler
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(restorationHandler: restorationHandler)
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.player = controller.renderingPlayer
        playerViewController.allowsPictureInPicturePlayback = true
        playerViewController.canStartPictureInPictureAutomaticallyFromInline =
            automaticallyStartsPictureInPictureWhenLeavingApp
        playerViewController.delegate = context.coordinator
        context.coordinator.attach(playerViewController)
        return playerViewController
    }

    public func updateUIViewController(
        _ playerViewController: AVPlayerViewController,
        context: Context
    ) {
        if playerViewController.player !== controller.renderingPlayer {
            playerViewController.player = controller.renderingPlayer
        }
        context.coordinator.restorationHandler = restorationHandler
        playerViewController.canStartPictureInPictureAutomaticallyFromInline =
            automaticallyStartsPictureInPictureWhenLeavingApp
        context.coordinator.attach(playerViewController)
    }

    public static func dismantleUIViewController(
        _ playerViewController: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        coordinator.detach(playerViewController)
    }

    @MainActor
    public final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var restorationHandler: StreamAVPlayerRestorationHandler

        private weak var attachedViewController: AVPlayerViewController?

        init(restorationHandler: @escaping StreamAVPlayerRestorationHandler) {
            self.restorationHandler = restorationHandler
        }

        func attach(_ viewController: AVPlayerViewController) {
            attachedViewController = viewController
        }

        func detach(_ viewController: AVPlayerViewController) {
            guard attachedViewController === viewController else { return }

            viewController.delegate = nil
            attachedViewController = nil
        }

        public func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
        ) {
            guard attachedViewController === playerViewController else {
                completionHandler(false)
                return
            }

            let completion = StreamAVPlayerRestorationCompletion(completionHandler)

            restorationHandler { restored in
                completion.call(restored)
            }
        }
    }
}
private final class StreamAVPlayerRestorationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false
    private let completion: @Sendable (Bool) -> Void

    init(_ completion: @escaping @Sendable (Bool) -> Void) {
        self.completion = completion
    }

    func call(_ restored: Bool) {
        lock.lock()

        guard !hasCompleted else {
            lock.unlock()
            return
        }

        hasCompleted = true
        lock.unlock()

        completion(restored)
    }
}
#endif
