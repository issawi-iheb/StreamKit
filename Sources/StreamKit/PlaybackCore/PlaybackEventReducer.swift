import Foundation

/// Applies engine events to playback snapshots without side effects.
enum PlaybackEventReducer {

    static func reduce(
        _ event: PlaybackEngineEvent,
        from snapshot: PlaybackSnapshot
    ) -> PlaybackSnapshot? {
        switch event {
        case .playing:
            guard snapshot.intent == .play else { return nil }
            return changingPhase(to: .playing, from: snapshot)

        case .waiting:
            guard snapshot.intent == .play else { return nil }
            return changingPhase(to: .waiting, from: snapshot)

        case .ended:
            return PlaybackSnapshot(
                phase: .ended,
                intent: .pause,
                currentTime: snapshot.currentTime,
                duration: snapshot.duration,
                timeline: snapshot.timeline
            )

        case let .timeUpdated(currentTime, duration, timeline):
            return PlaybackSnapshot(
                phase: snapshot.phase,
                intent: snapshot.intent,
                currentTime: currentTime,
                duration: duration ?? snapshot.duration,
                failure: snapshot.failure,
                timeline: timeline
            )

        case let .timelineUpdated(timeline):
            return PlaybackSnapshot(
                phase: snapshot.phase,
                intent: snapshot.intent,
                currentTime: snapshot.currentTime,
                duration: snapshot.duration,
                failure: snapshot.failure,
                timeline: timeline
            )

        case let .failed(failure):
            return PlaybackSnapshot(
                phase: .failed,
                intent: .pause,
                currentTime: snapshot.currentTime,
                duration: snapshot.duration,
                failure: failure,
                timeline: snapshot.timeline
            )

        case .paused:
            guard [.ready, .playing, .waiting, .paused].contains(snapshot.phase) else {
                return nil
            }
            return changingPhase(to: .paused, from: snapshot)

        case .fairPlayContentKeyResponseAccepted,
             .fairPlayContentKeyRequestFailed,
             .metric:
            return nil
        }
    }

    private static func changingPhase(
        to phase: PlaybackPhase,
        from snapshot: PlaybackSnapshot
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            phase: phase,
            intent: snapshot.intent,
            currentTime: snapshot.currentTime,
            duration: snapshot.duration,
            timeline: snapshot.timeline
        )
    }
}
