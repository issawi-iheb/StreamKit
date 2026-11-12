import Foundation

/// Tracks audio interruption policy independently from engine command execution.
struct AudioInterruptionCoordinator {

    private(set) var isInterrupted = false
    private var wasPlayingBeforeInterruption = false
    private var requiresExplicitPlayAfterInterruption = false

    var allowsPlaybackStart: Bool {
        !isInterrupted && !requiresExplicitPlayAfterInterruption
    }

    /// Returns true only for the first began event in an interruption interval.
    mutating func interruptionBegan(for snapshot: PlaybackSnapshot) -> Bool {
        guard !isInterrupted else { return false }

        isInterrupted = true
        wasPlayingBeforeInterruption = snapshot.intent == .play && [
            .loading, .ready, .playing, .waiting
        ].contains(snapshot.phase)
        return true
    }

    /// Returns whether policy allows automatic resumption after an interruption.
    mutating func interruptionEnded(
        systemAllowsResume: Bool,
        automaticallyResumes: Bool,
        snapshot: PlaybackSnapshot
    ) -> Bool {
        guard isInterrupted else { return false }

        isInterrupted = false
        let shouldResume = systemAllowsResume
            && automaticallyResumes
            && wasPlayingBeforeInterruption
            && snapshot.intent == .play
        requiresExplicitPlayAfterInterruption = snapshot.intent == .play && !shouldResume
        wasPlayingBeforeInterruption = false
        return shouldResume
    }

    mutating func playbackIntentRequested() {
        if isInterrupted {
            wasPlayingBeforeInterruption = true
        } else {
            requiresExplicitPlayAfterInterruption = false
        }
    }

    mutating func sourceLoadBegan() {
        requiresExplicitPlayAfterInterruption = false
    }
}
