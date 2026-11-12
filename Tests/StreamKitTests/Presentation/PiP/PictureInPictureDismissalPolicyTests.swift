//
//  PictureInPictureDismissalPolicyTests.swift
//  StreamKit
//
//  Created by Iheb on 23/10/2026.
//

#if os(iOS)

import Testing
import AVKit
import UIKit
@testable import StreamKit

@MainActor
@Suite("PictureInPictureDismissalPolicy")
struct PictureInPictureDismissalPolicyTests {
    private func policy(
        _ behavior: StreamPictureInPictureDismissalBehavior = .pausePlayback,
        background: Bool
    ) -> PictureInPictureDismissalPolicy {
        PictureInPictureDismissalPolicy(
            behavior: behavior,
            isApplicationInBackground: { background }
        )
    }

    @Test("PiP ending in the background pauses by default")
    func pausesInBackground() {
        #expect(policy(background: true).shouldPausePlayback(stopRequestedByHost: false))
    }

    @Test("PiP ending in the foreground does not pause")
    func doesNotPauseInForeground() {
        #expect(!policy(background: false).shouldPausePlayback(stopRequestedByHost: false))
    }

    @Test("continuePlayback never pauses")
    func continuePlayback() {
        #expect(!policy(.continuePlayback, background: true)
            .shouldPausePlayback(stopRequestedByHost: false))
    }

    @Test("A stop requested by the host is not treated as a dismissal")
    func hostRequestedStop() {
        #expect(!policy(background: true).shouldPausePlayback(stopRequestedByHost: true))
    }

    @Test("Standard AVKit PiP wait finishes after the stop callback")
    func waitUntilStoppedCompletesAfterStop() async throws {
        let coordinator = StreamAVPlayerPresentationController(
            restorationHandler: { completion in completion(false) },
            isApplicationInBackground: { false }
        )
        let viewController = AVPlayerViewController()
        coordinator.attach(viewController)
        coordinator.playerViewController(
            viewController,
            willStartPictureInPictureWith: UIViewController()
        )

        let waiter = Task {
            try await coordinator.waitUntilStopped()
        }
        await Task.yield()

        coordinator.playerViewControllerDidStopPictureInPicture(viewController)
        try await waiter.value

        #expect(coordinator.state == .idle)
    }

    @Test("Cancelling standard AVKit PiP wait does not claim PiP stopped")
    func cancellingWaitPreservesActiveState() async {
        let coordinator = StreamAVPlayerPresentationController(
            restorationHandler: { completion in completion(false) },
            isApplicationInBackground: { false }
        )
        let viewController = AVPlayerViewController()
        coordinator.attach(viewController)
        coordinator.playerViewController(
            viewController,
            willStartPictureInPictureWith: UIViewController()
        )

        let waiter = Task {
            try await coordinator.waitUntilStopped()
        }
        await Task.yield()
        waiter.cancel()

        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        #expect(coordinator.state == .starting)
    }

    @Test("Cancelling a custom PiP stop wait throws without undoing the stop request")
    func cancellingCustomStopWaitThrows() async {
        let waiters = PictureInPictureStopWaiters()
        var stopWasRequested = false

        let waiter = Task {
            try await waiters.waitUntilStopped(
                isStopped: { false },
                onWaitStart: { stopWasRequested = true }
            )
        }
        await Task.yield()

        #expect(stopWasRequested)
        waiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        #expect(stopWasRequested)
    }
}

#endif
