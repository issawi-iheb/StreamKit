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

    private static let maximumPlaybackRate: Float = 32.0

    // MARK: - Public API

    /// The configuration used to create this player.
    public let configuration: PlayerConfiguration

    /// The latest observable playback state.
    public private(set) var snapshot: PlaybackSnapshot

    /// A stream of playback state snapshots.
    ///
    /// Each subscriber immediately receives the current snapshot,
    /// followed by subsequent state updates.
    public var snapshots: AsyncStream<PlaybackSnapshot> {
        snapshotBroadcaster.makeStream(
            initialSnapshot: snapshot
        )
    }

    // MARK: - Private Properties

    private let engine: any PlaybackEngine
    var renderingPlayer: AVPlayer? {
        (engine as? AVFoundationPlaybackEngine)?.renderingPlayer
    }
    private let snapshotBroadcaster = SnapshotBroadcaster()

    private var eventTask: Task<Void, Never>?
    private var activeLoadTask: Task<Void, Error>?

    /// Identifies the current source-loading operation.
    private var loadGeneration: UInt64 = 0

    private var isShutdown = false

    // MARK: - Initialization

    public init(
        configuration: PlayerConfiguration = .init()
    ) {
        self.configuration = configuration
        self.engine = AVFoundationPlaybackEngine()
        self.snapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        observeEngineEvents()
    }

    internal init(
        configuration: PlayerConfiguration = .init(),
        engine: any PlaybackEngine
    ) {
        self.configuration = configuration
        self.engine = engine
        self.snapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        observeEngineEvents()
    }

    // MARK: - Loading

    /// Begins loading a media source.
    ///
    /// Returns a handle that can be used to await readiness
    /// or cancel this loading operation.
    public func load(_ source: MediaSource) -> LoadHandle {
        guard !isShutdown else {
            let task = Task<Void, Error> {
                throw shutdownFailure()
            }

            return LoadHandle(readiness: task)
        }
        let generation = beginLoading()

        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw CancellationError()
            }

            do {
                try await engine.load(source, generation: generation)

                try Task.checkCancellation()

                guard !isShutdown,
                      loadGeneration == generation
                else {
                    throw CancellationError()
                }

                if snapshot.intent == .play {
                    // The item is ready, but AVPlayer may still be buffering.
                    // Let the observed time-control status report `.playing`.
                    updateSnapshot(
                        PlaybackSnapshot(
                            phase: .ready,
                            intent: .play,
                            currentTime: snapshot.currentTime,
                            duration: snapshot.duration
                        )
                    )

                    try await engine.play()

                    guard !isShutdown,
                          loadGeneration == generation
                    else {
                        throw CancellationError()
                    }
                } else {
                    updateSnapshot(
                        PlaybackSnapshot(
                            phase: .ready,
                            intent: .pause,
                            currentTime: 0,
                            duration: snapshot.duration
                        )
                    )
                }
            } catch {
                guard !isShutdown,
                      loadGeneration == generation
                else {
                    throw error
                }

                if error is CancellationError {
                    updateSnapshot(
                        PlaybackSnapshot(
                            phase: .idle,
                            intent: .pause
                        )
                    )
                } else {
                    let failure = PlaybackFailureMapping.map(error)

                    updateSnapshot(
                        PlaybackSnapshot(
                            phase: .failed,
                            intent: .pause,
                            failure: failure
                        )
                    )
                }

                throw error
            }
        }

        activeLoadTask = task

        return LoadHandle(readiness: task)
    }

    private func beginLoading() -> UInt64 {
        loadGeneration &+= 1
        let generation = loadGeneration

        activeLoadTask?.cancel()
        activeLoadTask = nil

        let intent: PlaybackIntent = configuration.autoplay
            ? .play
            : .pause

        updateSnapshot(
            PlaybackSnapshot(
                phase: .loading,
                intent: intent
            )
        )

        return generation
    }

    // MARK: - Playback Controls

    /// Requests playback.
    public func play() async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        switch snapshot.phase {
        case .idle:
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a media source before playing."
            )

        case .loading:
            // The loading task will start playback when ready.
            updateIntent(.play)
            return

        case .failed:
            throw snapshot.failure ?? PlaybackFailure(
                code: .playback,
                message: "Playback has failed. Load a source to retry."
            )

        case .playing:
            updateIntent(.play)
            return

        case .ready, .paused, .waiting, .ended:
            updateIntent(.play)
        }

        do {
            try await engine.play()

            guard !isShutdown else {
                throw shutdownFailure()
            }
        } catch {
            guard !isShutdown else {
                throw shutdownFailure()
            }

            if error is CancellationError {
                throw error
            }

            let failure = PlaybackFailureMapping.map(error)

            updateSnapshot(
                PlaybackSnapshot(
                    phase: .failed,
                    intent: .pause,
                    currentTime: snapshot.currentTime,
                    duration: snapshot.duration,
                    failure: failure
                )
            )

            throw failure
        }
    }

    /// Requests that playback pause.
    public func pause() async {
        guard !isShutdown else {
            return
        }

        updateIntent(.pause)

        await engine.pause()

        guard !isShutdown else {
            return
        }

        switch snapshot.phase {
        case .playing, .waiting, .paused:
            updateSnapshot(
                PlaybackSnapshot(
                    phase: .paused,
                    intent: .pause,
                    currentTime: snapshot.currentTime,
                    duration: snapshot.duration
                )
            )

        case .idle, .loading, .ready, .ended, .failed:
            // Preserve the current phase.
            break
        }
    }

    /// Sets the playback rate for this player.
    ///
    /// The rate must be finite and between 0 and 32. The selected rate
    /// is retained when a new source is loaded.
    ///
    /// Changing the rate does not start playback or change playback intent.
    public func setPlaybackRate(_ rate: Float) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard rate.isFinite, rate > 0, rate <= Self.maximumPlaybackRate else {
            throw PlaybackFailure(
                code: .invalidPlaybackRate,
                message: "The playback rate must be finite and greater than zero, and no greater than 32."
            )
        }

        try await engine.setPlaybackRate(rate)

        guard !isShutdown else {
            throw shutdownFailure()
        }
    }

    /// Seeks to the specified position, in seconds.
    public func seek(to time: TimeInterval) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard snapshot.phase != .idle,
              snapshot.phase != .loading,
              snapshot.phase != .failed
        else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "A ready media source is required to seek."
            )
        }

        let generation = loadGeneration

        try await engine.seek(to: time)

        guard !isShutdown,
              loadGeneration == generation
        else {
            throw CancellationError()
        }

        updateSnapshot(
            PlaybackSnapshot(
                phase: snapshot.phase,
                intent: snapshot.intent,
                currentTime: time,
                duration: snapshot.duration,
                failure: snapshot.failure
            )
        )
    }

    // MARK: - Engine Events

    private func observeEngineEvents() {
        let events = engine.events

        eventTask = Task { @MainActor [weak self] in
            for await envelope in events {
                guard let self else { break }

                guard envelope.generation == self.loadGeneration else {
                    continue
                }

                self.handleEngineEvent(envelope.event)
            }
        }
    }

    private func handleEngineEvent(
        _ event: PlaybackEngineEvent
    ) {
        switch event {
        case .playing:
            guard snapshot.intent == .play else {
                return
            }

            updatePhase(.playing)

        case .waiting:
            guard snapshot.intent == .play else {
                return
            }

            updatePhase(.waiting)

        case .ended:
            updateSnapshot(
                PlaybackSnapshot(
                    phase: .ended,
                    intent: .pause,
                    currentTime: snapshot.currentTime,
                    duration: snapshot.duration
                )
            )

        case let .timeUpdated(currentTime, duration):
            updateSnapshot(
                PlaybackSnapshot(
                    phase: snapshot.phase,
                    intent: snapshot.intent,
                    currentTime: currentTime,
                    duration: duration ?? snapshot.duration,
                    failure: snapshot.failure
                )
            )

        case let .failed(failure):
            updateSnapshot(
                PlaybackSnapshot(
                    phase: .failed,
                    intent: .pause,
                    currentTime: snapshot.currentTime,
                    duration: snapshot.duration,
                    failure: failure
                )
            )
        case .paused:
            updatePhase(.paused)
        }
    }

    // MARK: - Snapshot Updates

    private func updateSnapshot(
        _ newSnapshot: PlaybackSnapshot
    ) {
        guard !isShutdown else {
            return
        }

        snapshot = newSnapshot
        snapshotBroadcaster.publish(newSnapshot)
    }

    private func updateIntent(
        _ intent: PlaybackIntent
    ) {
        updateSnapshot(
            PlaybackSnapshot(
                phase: snapshot.phase,
                intent: intent,
                currentTime: snapshot.currentTime,
                duration: snapshot.duration,
                failure: snapshot.failure
            )
        )
    }

    private func updatePhase(
        _ phase: PlaybackPhase
    ) {
        updateSnapshot(
            PlaybackSnapshot(
                phase: phase,
                intent: snapshot.intent,
                currentTime: snapshot.currentTime,
                duration: snapshot.duration,
                failure: snapshot.failure
            )
        )
    }

    // MARK: - Shutdown

    /// Stops playback and releases player resources.
    public func shutdown() async {
        guard !isShutdown else {
            return
        }

        isShutdown = true
        loadGeneration &+= 1

        activeLoadTask?.cancel()
        activeLoadTask = nil

        eventTask?.cancel()
        eventTask = nil

        await engine.shutdown()

        let finalSnapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        snapshot = finalSnapshot
        snapshotBroadcaster.finish(with: finalSnapshot)
    }

    // MARK: - Errors

    private func shutdownFailure() -> PlaybackFailure {
        PlaybackFailure(
            code: .playback,
            message: "The playback engine has been shut down."
        )
    }

    // MARK: - Media Tracks
    
    private func validateTrackAccess() throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard snapshot.phase != .idle,
              snapshot.phase != .loading,
              snapshot.phase != .failed
        else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "A ready media source is required to access tracks."
            )
        }
    }

    /// Returns the available audio tracks for the current media source.
    public func availableAudioTracks() async throws -> [MediaTrack] {
        try validateTrackAccess()
        let generation = loadGeneration

        let tracks = try await engine.availableAudioTracks()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }

        return tracks
    }

    /// Returns the available subtitle tracks for the current media source.
    public func availableSubtitleTracks() async throws -> [MediaTrack] {
        try validateTrackAccess()
        let generation = loadGeneration

        let tracks = try await engine.availableSubtitleTracks()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }

        return tracks
    }

    /// Selects an audio track by its identifier.
    public func selectAudioTrack(id: String) async throws {
        try validateTrackAccess()
        let generation = loadGeneration

        try await engine.selectAudioTrack(id: id)

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }
    }

    /// Selects a subtitle track, or disables subtitles when `id` is `nil`.
    public func selectSubtitleTrack(id: String?) async throws {
        try validateTrackAccess()
        let generation = loadGeneration

        try await engine.selectSubtitleTrack(id: id)

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }
    }
}
