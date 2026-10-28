import Foundation
import AVFoundation

extension StreamPlayerController {

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
                    publishDiagnostic(.loadCancelled(.requested))
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
        if snapshot.phase == .loading {
            publishDiagnostic(.loadCancelled(.replacedByNewSource))
        }
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
        publishDiagnostic(.loadStarted)

        return generation
    }
}
