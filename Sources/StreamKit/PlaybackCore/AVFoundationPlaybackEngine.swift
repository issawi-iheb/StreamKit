//
//  AVFoundationPlaybackEngine.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

import AVFoundation
import Foundation

/// AVFoundation-backed playback engine for a single player instance.
///
/// All player coordination is isolated to the main actor.
/// Each instance owns its own AVPlayer and playback resources.
@MainActor
final class AVFoundationPlaybackEngine: PlaybackEngine {

    // MARK: - Internal State

    // These members are module-internal so the responsibility-specific
    // extensions remain one engine with one actor-isolated resource owner.

    let player: AVPlayer
    var renderingPlayer: AVPlayer {
        player
    }

    let eventStream: AsyncStream<PlaybackEngineEventEnvelope>
    var eventContinuation: AsyncStream<PlaybackEngineEventEnvelope>.Continuation?

    // Item readiness observation.
    var itemStatusObservation: NSKeyValueObservation?

    // Playback observations.
    var timeControlStatusObservation: NSKeyValueObservation?
    var timeObserverToken: Any?
    var itemEndObserver: NSObjectProtocol?
    var itemFailureObserver: NSObjectProtocol?
    var pausedLiveTimelineTimer: Timer?

    // Current item identity and generation.
    var observedItem: AVPlayerItem?
    var authenticatedResourceLoader: AuthenticatedMediaResourceLoader?
    var fairPlayContentKeySession: FairPlayContentKeySession?
    var loadGeneration: UInt64 = 0
    var activeSourceGeneration: UInt64 = 0

    // Pending load readiness.
    var pendingReadiness: CheckedContinuation<Void, Error>?
    var pendingLoadGeneration: UInt64?

    var isShutdown = false
    var playbackRate: Float = 1.0
    let keepsLiveTimelineCurrentWhilePaused: Bool

    var events: AsyncStream<PlaybackEngineEventEnvelope> {
        eventStream
    }

    // MARK: - Initialization

    init(keepsLiveTimelineCurrentWhilePaused: Bool = false) {
        let stream = AsyncStream<PlaybackEngineEventEnvelope>.makeStream(
            bufferingPolicy: .unbounded
        )

        self.player = AVPlayer()
        self.eventStream = stream.stream
        self.eventContinuation = stream.continuation
        self.keepsLiveTimelineCurrentWhilePaused = keepsLiveTimelineCurrentWhilePaused
    }
}
