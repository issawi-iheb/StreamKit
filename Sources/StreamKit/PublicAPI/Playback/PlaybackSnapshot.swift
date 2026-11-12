import Foundation

/// An immutable snapshot of the player's observable playback state.
public struct PlaybackSnapshot: Equatable, Sendable {

    /// The player's current playback phase.
    public let phase: PlaybackPhase

    /// The playback behavior currently requested by the user or application.
    public let intent: PlaybackIntent

    /// The current playback position, in seconds.
    public let currentTime: TimeInterval

    /// The total media duration, in seconds, when known.
    public let duration: TimeInterval?

    /// Seekable ranges and wall-clock mapping reported by the current media item.
    public let timeline: PlaybackTimeline

    /// The failure associated with the current playback state, if any.
    public let failure: PlaybackFailure?

    /// The ad break currently using the player's output, if any.
    public let adBreak: PlaybackAdBreakState?

    public init(
        phase: PlaybackPhase,
        intent: PlaybackIntent,
        currentTime: TimeInterval = 0,
        duration: TimeInterval? = nil,
        failure: PlaybackFailure? = nil,
        timeline: PlaybackTimeline = .init(),
        adBreak: PlaybackAdBreakState? = nil
    ) {
        self.phase = phase
        self.intent = intent
        self.currentTime = currentTime
        self.duration = duration
        self.failure = failure
        self.timeline = timeline
        self.adBreak = adBreak
    }

    func settingAdBreak(_ adBreak: PlaybackAdBreakState?) -> PlaybackSnapshot {
        PlaybackSnapshot(
            phase: phase,
            intent: intent,
            currentTime: currentTime,
            duration: duration,
            failure: failure,
            timeline: timeline,
            adBreak: adBreak
        )
    }
}
