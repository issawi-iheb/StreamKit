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
    /// AVPlayer presentation handle for the AVFoundation-backed public player.
    /// Injected engine instances used internally may not provide a renderer.
    let renderingPlayer: AVPlayer?
    private let snapshotBroadcaster = SnapshotBroadcaster()

    private var eventTask: Task<Void, Never>?
    private var activeLoadTask: Task<Void, Error>?

    private let audioInterruptionSource: any AudioInterruptionSource
    private let audioPlaybackFocusCoordinator: AudioPlaybackFocusCoordinator?
    private var audioInterruptionTask: Task<Void, Never>?
    private var audioInterruptionCoordinator = AudioInterruptionCoordinator()

    /// Identifies the current source-loading operation.
    private var loadGeneration: UInt64 = 0
    /// Orders app playback commands across async engine calls.
    private var playbackCommandGeneration: UInt64 = 0
    /// Prevents an older seek from committing after a newer seek completes.
    private var seekGeneration: UInt64 = 0

    private var isShutdown = false
    private var shutdownTask: Task<Void, Never>?

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
        let generation = beginLoading(presentationKind: source.presentationKind)

        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw CancellationError()
            }

            var autoplayCommandGeneration: UInt64?

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
                            duration: snapshot.duration,
                            timeline: snapshot.timeline
                        )
                    )

                    if audioInterruptionCoordinator.allowsPlaybackStart {
                        guard await acquireAudioPlaybackFocus() else { return }
                        let commandGeneration = playbackCommandGeneration
                        autoplayCommandGeneration = commandGeneration
                        try await engine.play()

                        guard !isShutdown,
                              loadGeneration == generation
                        else {
                            await reconcileTransportIntent(afterApplyingPlayback: true)
                            throw CancellationError()
                        }

                        if playbackCommandGeneration != commandGeneration
                            || snapshot.intent != .play {
                            await reconcileTransportIntent(afterApplyingPlayback: true)
                        }
                    }

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
                            duration: snapshot.duration,
                            timeline: snapshot.timeline
                        )
                    )
                }
            } catch {
                guard !isShutdown,
                      loadGeneration == generation
                else {
                    throw error
                }

                if let autoplayCommandGeneration,
                   playbackCommandGeneration != autoplayCommandGeneration
                    || snapshot.intent != .play {
                    await reconcileTransportIntent()
                    return
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
                            failure: failure,
                            timeline: snapshot.timeline
                        )
                    )
                }

                throw error
            }
        }

        activeLoadTask = task

        return LoadHandle(readiness: task)
    }

    private func beginLoading(
        presentationKind: MediaPresentationKind
    ) -> UInt64 {
        loadGeneration &+= 1
        playbackCommandGeneration &+= 1
        seekGeneration &+= 1
        let generation = loadGeneration
        audioInterruptionCoordinator.sourceLoadBegan()

        activeLoadTask?.cancel()
        activeLoadTask = nil

        let intent: PlaybackIntent = configuration.autoplay
            ? .play
            : .pause

        updateSnapshot(
            PlaybackSnapshot(
                phase: .loading,
                intent: intent,
                timeline: PlaybackTimeline(presentationKind: presentationKind)
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

        playbackCommandGeneration &+= 1
        let commandGeneration = playbackCommandGeneration

        audioInterruptionCoordinator.playbackIntentRequested()

        let shouldRestartEndedItem = snapshot.phase == .ended
            && snapshot.duration.map { $0.isFinite && $0 >= 0 } == true
        let generation = loadGeneration

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

        if audioInterruptionCoordinator.isInterrupted {
            // Keep the request. The interruption-end handler will retry if
            // the system permits automatic resumption.
            return
        }

        do {
            if shouldRestartEndedItem {
                try await engine.seek(to: 0)

                guard !isShutdown else {
                    throw shutdownFailure()
                }
                guard loadGeneration == generation else {
                    throw CancellationError()
                }
                guard playbackCommandGeneration == commandGeneration else {
                    return
                }
                guard snapshot.intent == .play else {
                    return
                }
            }

            guard await acquireAudioPlaybackFocus() else { return }

            try await engine.play()

            guard !isShutdown else {
                throw shutdownFailure()
            }
            guard loadGeneration == generation else {
                await reconcileTransportIntent(afterApplyingPlayback: true)
                throw CancellationError()
            }
            guard playbackCommandGeneration == commandGeneration else {
                // An async engine may apply its play request only when the
                // operation completes. Reassert a newer pause after that late
                // completion so transport state follows the latest intent.
                await reconcileTransportIntent(afterApplyingPlayback: true)
                return
            }
        } catch {
            guard !isShutdown else {
                throw shutdownFailure()
            }

            guard loadGeneration == generation,
                  playbackCommandGeneration == commandGeneration else {
                throw CancellationError()
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
                    failure: failure,
                    timeline: snapshot.timeline
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

        playbackCommandGeneration &+= 1
        let commandGeneration = playbackCommandGeneration

        updateIntent(.pause)
        audioPlaybackFocusCoordinator?.releaseFocus(for: self)

        await engine.pause()

        guard !isShutdown else {
            return
        }

        guard playbackCommandGeneration == commandGeneration else {
            await reconcileTransportIntent(afterApplyingPlayback: false)
            return
        }

        switch snapshot.phase {
        case .playing, .waiting, .paused:
            updateSnapshot(
                PlaybackSnapshot(
                    phase: .paused,
                    intent: .pause,
                    currentTime: snapshot.currentTime,
                    duration: snapshot.duration,
                    timeline: snapshot.timeline
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
        let seekGeneration = beginSeek()

        try await engine.seek(to: time)

        guard !isShutdown,
              loadGeneration == generation,
              self.seekGeneration == seekGeneration
        else {
            throw CancellationError()
        }

        updateSnapshot(
            PlaybackSnapshot(
                phase: snapshot.phase,
                intent: snapshot.intent,
                currentTime: time,
                duration: snapshot.duration,
                failure: snapshot.failure,
                timeline: PlaybackTimeline(
                    seekableRanges: snapshot.timeline.seekableRanges,
                    presentationKind: snapshot.timeline.presentationKind
                )
            )
        )
    }

    /// Seeks to the live edge, optionally remaining a finite number of seconds
    /// behind it. The source must have been declared with `.live`.
    public func seekToLiveEdge(offsetFromLive: TimeInterval = 0) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard snapshot.phase != .idle,
              snapshot.phase != .loading,
              snapshot.phase != .failed
        else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "A ready live media source is required to seek to the live edge."
            )
        }

        guard snapshot.timeline.presentationKind == .live else {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "Seek to live edge requires a source declared with the live presentation kind."
            )
        }

        guard offsetFromLive.isFinite, offsetFromLive >= 0 else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The live offset must be finite and non-negative."
            )
        }

        let generation = loadGeneration
        let seekGeneration = beginSeek()
        try await engine.seekToLiveEdge(offsetFromLive: offsetFromLive)

        guard !isShutdown,
              loadGeneration == generation,
              self.seekGeneration == seekGeneration
        else {
            throw CancellationError()
        }
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

    private func observeAudioSessionInterruptions() {
        let events = audioInterruptionSource.events
        audioInterruptionTask = Task { @MainActor [weak self] in
            for await interruption in events {
                guard let self else { break }
                await self.handleAudioSessionInterruption(interruption)
            }
        }
    }

    /// Applies an audio-session interruption. Kept internal so the policy can
    /// be exercised without depending on system notifications in unit tests.
    func handleAudioSessionInterruption(
        _ interruption: AudioSessionInterruption
    ) async {
        guard !isShutdown else {
            return
        }

        switch interruption {
        case .began:
            guard audioInterruptionCoordinator.interruptionBegan(for: snapshot) else {
                return
            }

            await engine.pause()

            switch snapshot.phase {
            case .playing, .waiting, .ready:
                updatePhase(.paused)
            case .idle, .loading, .paused, .ended, .failed:
                break
            }

        case let .ended(systemAllowsResume):
            let shouldResume = audioInterruptionCoordinator.interruptionEnded(
                systemAllowsResume: systemAllowsResume,
                automaticallyResumes: configuration.automaticallyResumesAfterAudioInterruption,
                snapshot: snapshot
            )
            guard shouldResume else {
                return
            }

            // If loading is still in progress, its readiness task will start
            // playback now that the interruption has ended.
            guard snapshot.phase != .loading else {
                return
            }

            guard await acquireAudioPlaybackFocus() else { return }

            let sourceGeneration = loadGeneration
            let commandGeneration = playbackCommandGeneration

            do {
                try await engine.play()

                guard !isShutdown else {
                    return
                }
                guard loadGeneration == sourceGeneration else {
                    await reconcileTransportIntent(afterApplyingPlayback: true)
                    return
                }

                guard playbackCommandGeneration == commandGeneration,
                      snapshot.intent == .play
                else {
                    await reconcileTransportIntent(afterApplyingPlayback: true)
                    return
                }
            } catch {
                guard !isShutdown,
                      loadGeneration == sourceGeneration,
                      playbackCommandGeneration == commandGeneration,
                      snapshot.intent == .play
                else {
                    return
                }

                let failure = PlaybackFailureMapping.map(error)
                updateSnapshot(
                    PlaybackSnapshot(
                        phase: .failed,
                        intent: .pause,
                        currentTime: snapshot.currentTime,
                        duration: snapshot.duration,
                        failure: failure,
                        timeline: snapshot.timeline
                    )
                )
            }
        }
    }

    private func handleEngineEvent(
        _ event: PlaybackEngineEvent
    ) {
        guard let newSnapshot = PlaybackEventReducer.reduce(event, from: snapshot) else {
            return
        }
        updateSnapshot(newSnapshot)
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
                failure: snapshot.failure,
                timeline: snapshot.timeline
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
                failure: snapshot.failure,
                timeline: snapshot.timeline
            )
        )
    }

    /// Reapplies the latest controller intent after an older transport call
    /// completes late. The loop checks generations after each async engine
    /// operation so a newer command that arrives during reconciliation wins.
    private func reconcileTransportIntent(
        afterApplyingPlayback appliedPlayback: Bool? = nil
    ) async {
        var appliedPlayback = appliedPlayback

        while !isShutdown {
            let commandGeneration = playbackCommandGeneration
            let sourceGeneration = loadGeneration
            let phaseCanPlay = [PlaybackPhase.ready, .playing, .waiting, .paused]
                .contains(snapshot.phase)
            let desiredPlayback = snapshot.intent == .play
                && phaseCanPlay
                && audioInterruptionCoordinator.allowsPlaybackStart

            if appliedPlayback == desiredPlayback {
                return
            }

            if desiredPlayback {
                guard await acquireAudioPlaybackFocus() else { return }
                do {
                    try await engine.play()
                    appliedPlayback = true
                } catch {
                    guard !isShutdown else { return }
                    guard commandGeneration == playbackCommandGeneration,
                          sourceGeneration == loadGeneration else {
                        appliedPlayback = nil
                        continue
                    }

                    guard !(error is CancellationError) else { return }

                    let failure = PlaybackFailureMapping.map(error)
                    playbackCommandGeneration &+= 1
                    updateSnapshot(
                        PlaybackSnapshot(
                            phase: .failed,
                            intent: .pause,
                            currentTime: snapshot.currentTime,
                            duration: snapshot.duration,
                            failure: failure,
                            timeline: snapshot.timeline
                        )
                    )
                    appliedPlayback = nil
                    continue
                }
            } else {
                await engine.pause()
                appliedPlayback = false
            }

            guard !isShutdown else { return }
            guard commandGeneration == playbackCommandGeneration,
                  sourceGeneration == loadGeneration else {
                continue
            }

            return
        }
    }

    private func acquireAudioPlaybackFocus() async -> Bool {
        guard let audioPlaybackFocusCoordinator else { return true }

        let previousController = audioPlaybackFocusCoordinator.requestFocus(for: self)
        if let previousController {
            await previousController.pause()
        }

        return !isShutdown && audioPlaybackFocusCoordinator.ownsFocus(self)
    }

    // MARK: - Shutdown

    private func beginSeek() -> UInt64 {
        seekGeneration &+= 1
        return seekGeneration
    }

    /// Stops playback and releases player resources.
    public func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }

        guard !isShutdown else {
            return
        }

        isShutdown = true
        audioPlaybackFocusCoordinator?.releaseFocus(for: self)
        loadGeneration &+= 1
        playbackCommandGeneration &+= 1
        seekGeneration &+= 1

        activeLoadTask?.cancel()
        activeLoadTask = nil

        eventTask?.cancel()
        eventTask = nil

        audioInterruptionTask?.cancel()
        audioInterruptionTask = nil
        audioInterruptionSource.shutdown()

        let shutdownTask = Task { @MainActor in
            await engine.shutdown()

            let finalSnapshot = PlaybackSnapshot(
                phase: .idle,
                intent: .pause
            )

            snapshot = finalSnapshot
            snapshotBroadcaster.finish(with: finalSnapshot)
        }
        self.shutdownTask = shutdownTask
        await shutdownTask.value
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
        try Task.checkCancellation()
        let generation = loadGeneration

        let tracks = try await engine.availableAudioTracks()
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }

        return tracks
    }

    /// Returns the available subtitle tracks for the current media source.
    public func availableSubtitleTracks() async throws -> [MediaTrack] {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        let tracks = try await engine.availableSubtitleTracks()
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }

        return tracks
    }

    /// Selects an audio track by its identifier.
    public func selectAudioTrack(id: String) async throws {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        try await engine.selectAudioTrack(id: id)
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }
    }

    /// Selects a subtitle track, or disables subtitles when `id` is `nil`.
    public func selectSubtitleTrack(id: String?) async throws {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        try await engine.selectSubtitleTrack(id: id)
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }
    }
}
