import Foundation

/// Configuration for a StreamKit player instance.
public struct PlayerConfiguration: Equatable, Sendable {

    /// Whether playback should begin automatically when the media is ready.
    public let autoplay: Bool

    /// Whether playback should resume after an audio interruption when iOS
    /// indicates that resuming is appropriate and playback was active before
    /// the interruption. The host app remains responsible for configuring its
    /// process-wide audio session and enabling background audio if needed.
    public let automaticallyResumesAfterAudioInterruption: Bool

    /// Creates a player configuration.
    public init(
        autoplay: Bool = false,
        automaticallyResumesAfterAudioInterruption: Bool = true
    ) {
        self.autoplay = autoplay
        self.automaticallyResumesAfterAudioInterruption = automaticallyResumesAfterAudioInterruption
    }
}
