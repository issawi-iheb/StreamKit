import Foundation
import AVFoundation

extension StreamPlayerController {

// MARK: - Snapshot Updates

    func updateSnapshot(
        _ newSnapshot: PlaybackSnapshot
    ) {
        guard !isShutdown else {
            return
        }

        let previousPhase = snapshot.phase
        snapshot = newSnapshot
        snapshotBroadcaster.publish(newSnapshot)

        if previousPhase != .waiting, newSnapshot.phase == .waiting {
            bufferingStartUptime = ProcessInfo.processInfo.systemUptime
            bufferingStartLoadGeneration = loadGeneration
            publishDiagnostic(.bufferingStarted)
        } else if previousPhase == .waiting, newSnapshot.phase != .waiting {
            let start = bufferingStartUptime ?? ProcessInfo.processInfo.systemUptime
            let sourceGeneration = bufferingStartLoadGeneration ?? loadGeneration
            bufferingStartUptime = nil
            bufferingStartLoadGeneration = nil
            let duration = max(0, ProcessInfo.processInfo.systemUptime - start)
            publishDiagnostic(
                .bufferingEnded(duration: duration),
                loadGeneration: sourceGeneration
            )
        }

        if previousPhase != .ready, newSnapshot.phase == .ready {
            publishDiagnostic(.ready)
        }
        if previousPhase != .failed, newSnapshot.phase == .failed {
            publishDiagnostic(.playbackFailed(newSnapshot.failure?.code ?? .unknown))
        }
        if previousPhase != .ended, newSnapshot.phase == .ended {
            publishDiagnostic(.ended)
        }
    }

    func updateIntent(
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

    func updatePhase(
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
    func reconcileTransportIntent(
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

    func acquireAudioPlaybackFocus() async -> Bool {
        guard let audioPlaybackFocusCoordinator else { return true }

        let previousController = audioPlaybackFocusCoordinator.requestFocus(for: self)
        if let previousController {
            await previousController.pause()
        }

        return !isShutdown && audioPlaybackFocusCoordinator.ownsFocus(self)
    }
}
