import Foundation

/// A privacy-safe event describing a notable playback lifecycle transition.
///
/// Events contain normalized values only. They never include media URLs,
/// request headers, DRM payloads, provider response text, or raw AVFoundation
/// error descriptions.
public struct PlaybackDiagnosticEvent: Equatable, Sendable {
    /// The kind of playback transition represented by this event.
    public enum Kind: Equatable, Sendable {
        case loadStarted
        case ready
        case bufferingStarted
        case bufferingEnded(duration: TimeInterval)
        case loadCancelled(LoadCancellationReason)
        case playbackFailed(PlaybackFailure.Code)
        case ended
        case audioInterruptionBegan
        case audioInterruptionEnded(systemAllowsResume: Bool, resumeRequested: Bool)
        case fairPlayContentKeyResponseAccepted
        case fairPlayContentKeyRequestFailed(errorCode: Int)
    }

    /// Why the active source load was cancelled.
    public enum LoadCancellationReason: Equatable, Sendable {
        case requested
        case replacedByNewSource
        case shutdown
    }

    /// Monotonically increasing event number for this controller.
    /// A gap indicates that a bounded subscriber stream dropped events.
    public let sequence: UInt64

    /// Wall-clock time at which StreamKit published this event.
    public let timestamp: Date

    /// The source-load generation associated with this event.
    public let loadGeneration: UInt64

    /// The normalized event kind.
    public let kind: Kind

    init(
        sequence: UInt64,
        timestamp: Date,
        loadGeneration: UInt64,
        kind: Kind
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.loadGeneration = loadGeneration
        self.kind = kind
    }
}
