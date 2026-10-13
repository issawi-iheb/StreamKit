//
//  PlaybackFailureTests.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Testing
@testable import StreamKit

@Suite("PlaybackFailure")
struct PlaybackFailureTests {

    @Test("Preserves failure code and message")
    func preservesCodeAndMessage() {
        let failure = PlaybackFailure(
            code: .network,
            message: "The connection was lost."
        )

        #expect(failure.code == .network)
        #expect(failure.message == "The connection was lost.")
    }

    @Test("Failures with identical values are equal")
    func identicalFailuresAreEqual() {
        let first = PlaybackFailure(
            code: .network,
            message: "Connection lost."
        )

        let second = PlaybackFailure(
            code: .network,
            message: "Connection lost."
        )

        #expect(first == second)
    }

    @Test("Different failure codes produce unequal failures")
    func differentCodesAreUnequal() {
        let first = PlaybackFailure(
            code: .network,
            message: "Failure."
        )

        let second = PlaybackFailure(
            code: .playback,
            message: "Failure."
        )

        #expect(first != second)
    }

    @Test("Different messages produce unequal failures")
    func differentMessagesAreUnequal() {
        let first = PlaybackFailure(
            code: .network,
            message: "Connection lost."
        )

        let second = PlaybackFailure(
            code: .network,
            message: "Request timed out."
        )

        #expect(first != second)
    }
}
