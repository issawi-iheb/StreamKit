//
//  StreamPlayerController.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation
import AVFoundation

/// Controls an independent StreamKit playback instance.
@MainActor
public final class StreamPlayerController {

    static let maximumPlaybackRate: Float = 32.0

    // MARK: - Public API

    /// The configuration used to create this player.
    public let configuration: PlayerConfiguration

    /// The latest observable playback state.
    public internal(set) var snapshot: PlaybackSnapshot

    /// A stream of playback state snapshots.
    ///
    /// Each subscriber immediately receives the current snapshot,
    /// followed by subsequent state updates.
    public var snapshots: AsyncStream<PlaybackSnapshot> {
        snapshotBroadcaster.makeStream(
            initialSnapshot: snapshot
        )
    }

    // MARK: - Internal State

    // These members are module-internal so the responsibility-specific
    // extensions remain one controller with one actor-isolated state owner.

    let engine: any PlaybackEngine
    /// AVPlayer presentation handle for the AVFoundation-backed public player.
    /// Injected engine instances used internally may not provide a renderer.
    let renderingPlayer: AVPlayer?
    let snapshotBroadcaster = SnapshotBroadcaster()

    var eventTask: Task<Void, Never>?
    var activeLoadTask: Task<Void, Error>?

    let audioInterruptionSource: any AudioInterruptionSource
    let audioPlaybackFocusCoordinator: AudioPlaybackFocusCoordinator?
    var audioInterruptionTask: Task<Void, Never>?
    var audioInterruptionCoordinator = AudioInterruptionCoordinator()

    /// Identifies the current source-loading operation.
    var loadGeneration: UInt64 = 0
    /// Orders app playback commands across async engine calls.
    var playbackCommandGeneration: UInt64 = 0
    /// Prevents an older seek from committing after a newer seek completes.
    var seekGeneration: UInt64 = 0

    var isShutdown = false
    var shutdownTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        configuration: PlayerConfiguration = .init(),
        audioPlaybackFocusCoordinator: AudioPlaybackFocusCoordinator? = nil
    ) {
        let engine = AVFoundationPlaybackEngine(
            keepsLiveTimelineCurrentWhilePaused: configuration.keepsLiveTimelineCurrentWhilePaused
        )
        self.configuration = configuration
        self.engine = engine
        self.renderingPlayer = engine.renderingPlayer
        self.audioInterruptionSource = SystemAudioInterruptionSource()
        self.audioPlaybackFocusCoordinator = audioPlaybackFocusCoordinator
        self.snapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        observeEngineEvents()
        observeAudioSessionInterruptions()
    }

    internal init(
        configuration: PlayerConfiguration = .init(),
        engine: any PlaybackEngine,
        audioPlaybackFocusCoordinator: AudioPlaybackFocusCoordinator? = nil
    ) {
        self.configuration = configuration
        self.engine = engine
        self.renderingPlayer = nil
        self.audioInterruptionSource = SystemAudioInterruptionSource()
        self.audioPlaybackFocusCoordinator = audioPlaybackFocusCoordinator
        self.snapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        observeEngineEvents()
        observeAudioSessionInterruptions()
    }

    internal init(
        configuration: PlayerConfiguration = .init(),
        engine: any PlaybackEngine,
        audioInterruptionSource: any AudioInterruptionSource,
        audioPlaybackFocusCoordinator: AudioPlaybackFocusCoordinator? = nil
    ) {
        self.configuration = configuration
        self.engine = engine
        self.renderingPlayer = nil
        self.audioInterruptionSource = audioInterruptionSource
        self.audioPlaybackFocusCoordinator = audioPlaybackFocusCoordinator
        self.snapshot = PlaybackSnapshot(phase: .idle, intent: .pause)

        observeEngineEvents()
        observeAudioSessionInterruptions()
    }
}
