//
//  ClientSideAdSession.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import Foundation

/// The result of a client-side ad break.
public enum ClientSideAdBreakOutcome: Equatable, Sendable {
    case completed
    case skipped
    case failed
}

/// Metadata describing an ad break that has started.
public struct ClientSideAdBreakInfo: Equatable, Sendable {
    /// The content time at which the break was scheduled, if known.
    public let cuePoint: TimeInterval?

    /// Whether the active ad can be skipped.
    public let isSkippable: Bool

    public init(
        cuePoint: TimeInterval? = nil,
        isSkippable: Bool = false
    ) {
        self.cuePoint = cuePoint
        self.isSkippable = isSkippable
    }
}

/// A provider-neutral classification of an advertising failure.
///
/// Vendor error messages are deliberately excluded: they may contain
/// URLs, response data, or other information that should not enter
/// StreamKit's public playback state or diagnostics.
public struct ClientSideAdFailure: Error, Equatable, Sendable {
    public enum Code: Equatable, Sendable {
        case requestFailed
        case playbackFailed
        case unsupportedConfiguration
        case timedOut
        case unknown
    }

    public let code: Code

    public init(code: Code = .unknown) {
        self.code = code
    }
}

/// Events emitted by a client-side advertising session.
///
/// Events describe the ad lifecycle, not the underlying advertising SDK.
public enum ClientSideAdEvent: Equatable, Sendable {
    /// The session has resolved whether a pre-roll is scheduled.
    case ready(hasPreRoll: Bool)

    /// An ad break has taken control of playback.
    case breakStarted(ClientSideAdBreakInfo)

    /// The active ad break has ended.
    case breakEnded(ClientSideAdBreakOutcome)

    /// No further ad breaks are expected for this content.
    case allBreaksCompleted

    /// The provider encountered an advertising failure.
    case failed(ClientSideAdFailure)
}

/// A single client-side ad session associated with one content load.
///
/// StreamKit owns content playback coordination, interruption handling,
/// and stale-session protection. The provider owns ad SDK interactions.
@MainActor
public protocol ClientSideAdSession: AnyObject {
    /// A single-consumer stream of events for this session.
    var events: AsyncStream<ClientSideAdEvent> { get }

    /// Starts the ad request and session lifecycle.
    func start()

    /// Notifies the provider that content playback has ended.
    /// Used by providers that support post-roll ads.
    func contentDidFinish()

    /// Pauses the currently active ad break.
    func pauseBreak()

    /// Resumes the currently active ad break.
    func resumeBreak()

    /// Permanently invalidates this session and finishes its event stream.
    func invalidate()
}
