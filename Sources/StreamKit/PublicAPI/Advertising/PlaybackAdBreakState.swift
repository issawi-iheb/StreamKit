import Foundation

/// The delivery path for an active ad break.
public enum PlaybackAdDeliveryMode: Equatable, Sendable {
    /// The HLS presentation schedules an interstitial in its media playlist.
    case hlsInterstitial

    /// The host application's client-side ad provider is playing an ad.
    case clientSide
}

/// Provider-neutral state for the ad break currently taking the player's output.
public struct PlaybackAdBreakState: Equatable, Sendable {
    /// The ad delivery path that owns the active break.
    public let deliveryMode: PlaybackAdDeliveryMode

    /// A per-controller sequence number that distinguishes consecutive breaks.
    public let sequence: UInt64

    /// Whether playback must not seek forward across this break.
    public let restrictsForwardSeeking: Bool

    /// Whether playback must remain at the media's preferred playback rate.
    public let requiresPreferredPlaybackRate: Bool

    init(
        deliveryMode: PlaybackAdDeliveryMode,
        sequence: UInt64,
        restrictsForwardSeeking: Bool,
        requiresPreferredPlaybackRate: Bool
    ) {
        self.deliveryMode = deliveryMode
        self.sequence = sequence
        self.restrictsForwardSeeking = restrictsForwardSeeking
        self.requiresPreferredPlaybackRate = requiresPreferredPlaybackRate
    }
}
