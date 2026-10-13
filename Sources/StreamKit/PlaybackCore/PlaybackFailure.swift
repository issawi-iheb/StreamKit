import Foundation

/// A failure encountered during media playback.
public struct PlaybackFailure: Error, Equatable, Sendable {

    /// The category of the playback failure.
    public enum Code: Equatable, Sendable {
        case invalidSource
        case unsupportedFormat
        case network
        case playback
        case unknown
    }

    /// A stable code identifying the category of failure.
    public let code: Code

    /// A human-readable description of the failure.
    public let message: String

    public init(
        code: Code,
        message: String
    ) {
        self.code = code
        self.message = message
    }
}
