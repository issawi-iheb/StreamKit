//
//  PlaybackFailureTests.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Testing
import AVFoundation
import Foundation
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

    @Test("Maps URL loading errors as network failures")
    func mapsURLLoadingError() {
        let failure = PlaybackFailureMapping.map(URLError(.timedOut))
        #expect(failure.code == .network)
        #expect(!failure.message.contains("https://"))
    }

    @Test("Maps unsupported AVFoundation formats")
    func mapsUnsupportedFormat() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.formatUnsupported.rawValue
        )
        #expect(PlaybackFailureMapping.map(error).code == .unsupportedFormat)
    }

    @Test("Finds network errors wrapped by AVFoundation")
    func mapsWrappedNetworkError() {
        let underlying = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
        let wrapped = NSError(
            domain: AVFoundationErrorDomain,
            code: -11800,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        #expect(PlaybackFailureMapping.map(wrapped).code == .network)
    }

    @Test("Preserves authentication failures wrapped by AVFoundation")
    func mapsWrappedAuthenticationError() {
        let authentication = PlaybackFailureMapping.authenticationNSError(
            message: "A private credential message."
        )
        let wrapped = NSError(
            domain: AVFoundationErrorDomain,
            code: -11800,
            userInfo: [NSUnderlyingErrorKey: authentication]
        )

        let failure = PlaybackFailureMapping.map(wrapped)
        #expect(failure.code == .authentication)
        #expect(failure.message == "The media server rejected the supplied credentials.")
        #expect(!failure.message.contains("private credential"))
    }
}
