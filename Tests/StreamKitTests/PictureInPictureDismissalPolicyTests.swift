//
//  PictureInPictureDismissalPolicyTests.swift
//  StreamKit
//
//  Created by Iheb on 23/10/2026.
//

#if os(iOS)

import Testing
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
}

#endif
