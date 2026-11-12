import Foundation
import AVFoundation

extension StreamPlayerController {

// MARK: - Transport Controls

    /// Requests playback.
    public func play() async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        playbackCommandGeneration &+= 1
        let commandGeneration = playbackCommandGeneration

        audioInterruptionCoordinator.playbackIntentRequested()
        clientSideAdCoordinator?.setUserPaused(false)

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
        // Client-side ads own the presentation while their break is active.
        // Preserve the user's play intent, but do not start the content engine.
        if snapshot.adBreak?.deliveryMode == .clientSide {
            return
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
            // Playback ownership may have changed while acquiring audio focus.
            guard !isShutdown else {
                throw shutdownFailure()
            }

            guard loadGeneration == generation else {
                throw CancellationError()
            }

            guard playbackCommandGeneration == commandGeneration else {
                return
            }

            guard snapshot.intent == .play,
                  snapshot.adBreak?.deliveryMode != .clientSide,
                  audioInterruptionCoordinator.allowsPlaybackStart else {
                return
            }
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
        clientSideAdCoordinator?.setUserPaused(true)
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

        if snapshot.adBreak?.deliveryMode == .clientSide,
           snapshot.adBreak?.requiresPreferredPlaybackRate == true,
           rate != selectedPlaybackRate {
            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "The preferred playback rate cannot be changed during this ad break."
            )
        }

        let previousRate = selectedPlaybackRate

        try await engine.setPlaybackRate(rate)

        guard !isShutdown else {
            throw shutdownFailure()
        }

        // An ad break may have started while the engine operation was suspended.
        if snapshot.adBreak?.deliveryMode == .clientSide,
           snapshot.adBreak?.requiresPreferredPlaybackRate == true,
           rate != previousRate {
            try? await engine.setPlaybackRate(previousRate)

            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "The preferred playback rate cannot be changed during this ad break."
            )
        }

        selectedPlaybackRate = rate
    }
}
