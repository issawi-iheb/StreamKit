//
//  PlaybackEngineEvent.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation

/// Associates an event with the load operation that produced it.
struct PlaybackEngineEventEnvelope: Sendable {
    let generation: UInt64
    let event: PlaybackEngineEvent
}

/// An event emitted by the playback engine.
enum PlaybackEngineEvent: Sendable {

    /// Playback has started or resumed.
    case playing

    case paused

    /// Playback is waiting for data or another condition.
    case waiting

    /// Playback has reached the end of the media.
    case ended

    /// The playback position or duration has changed.
    case timeUpdated(
        currentTime: TimeInterval,
        duration: TimeInterval?,
        timeline: PlaybackTimeline
    )

    /// The seekable timeline changed without a playback-time update.
    case timelineUpdated(PlaybackTimeline)

    /// A playback failure occurred.
    case failed(PlaybackFailure)
}
