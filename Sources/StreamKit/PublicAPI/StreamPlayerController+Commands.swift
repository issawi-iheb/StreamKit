import Foundation
import AVFoundation

extension StreamPlayerController {

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
}
