import Foundation

/// Configuration for a StreamKit player instance.
public struct PlayerConfiguration: Equatable, Sendable {

    /// Whether playback should begin automatically when the media is ready.
    public let autoplay: Bool

    /// Creates a player configuration.
    public init(
        autoplay: Bool = false
    ) {
        self.autoplay = autoplay
    }
}
