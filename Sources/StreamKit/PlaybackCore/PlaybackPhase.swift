/// Represents the current playback state of the player.
///
/// PlaybackPhase describes what the player is currently doing, not what the
/// application has requested. It is independent of playback intent and does
/// not contain detailed error information (see `PlaybackFailure` for errors).
///
/// - idle: No media item is loaded.
/// - loading: The player is loading a media item but has not yet reached
///   a state where it can play.
/// - ready: The media item is loaded and ready to play, but playback has
///   not started.
/// - playing: The media item is currently playing.
/// - paused: Playback has been explicitly paused by the user or
///   application. The media item remains loaded and ready to resume.
/// - waiting: Playback cannot currently progress and is waiting for a condition
///   that allows it to continue, such as additional media data. Unlike `paused`,
///   this state is not due to an explicit pause request.
/// - ended: The media item has played to completion.
/// - failed: An error occurred during playback or loading. The specific
///   error is not stored in this phase; check the associated failure
///   for details.
public enum PlaybackPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case waiting
    case ended
    case failed
}
