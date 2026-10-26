import Foundation
import AVFoundation

extension StreamPlayerController {

// MARK: - Engine Events

    func observeEngineEvents() {
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

    func observeAudioSessionInterruptions() {
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
}
