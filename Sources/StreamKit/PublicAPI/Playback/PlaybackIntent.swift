/// Represents the desired playback behavior requested by the application.
///
/// PlaybackIntent expresses what the application wants the player to do, not
/// what the player is currently doing. It is independent of the current
/// playback phase and does not change automatically based on buffering or
/// other transient states.
///
/// - play: Requests that the player should play the media item if it is
///   ready and able to do so.
/// - pause: Requests that the player should pause playback. The media item
///   remains loaded and ready to resume when a play request is made.
///
/// The intent can remain `.play` while the playback phase is `.waiting`
/// (e.g., during buffering). In such a case, playback will resume
/// automatically when the media becomes ready, unless a pause request has
/// been issued in the meantime.
///
/// A pause request during buffering must prevent playback from resuming
/// automatically when buffering finishes. Therefore, the playback
/// coordination logic must check the current intent when transitioning
/// from a waiting state to determine whether to resume playback.
public enum PlaybackIntent: Equatable, Sendable {
    case play
    case pause
}
