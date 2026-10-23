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

    /// Keeps a live stream's seekable timeline fresh while playback is paused.
    /// This allows AVFoundation to use network resources while paused and can
    /// increase network and power use. Disabled by default.
    public let keepsLiveTimelineCurrentWhilePaused: Bool

    /// Creates a player configuration.
    public init(
        autoplay: Bool = false,
        automaticallyResumesAfterAudioInterruption: Bool = true,
        keepsLiveTimelineCurrentWhilePaused: Bool = false
    ) {
        self.autoplay = autoplay
        self.automaticallyResumesAfterAudioInterruption = automaticallyResumesAfterAudioInterruption
        self.keepsLiveTimelineCurrentWhilePaused = keepsLiveTimelineCurrentWhilePaused
    }
}
