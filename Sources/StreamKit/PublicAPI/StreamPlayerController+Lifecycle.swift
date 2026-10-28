import Foundation
import AVFoundation

extension StreamPlayerController {

// MARK: - Shutdown

    func beginSeek() -> UInt64 {
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
        if snapshot.phase == .loading {
            publishDiagnostic(.loadCancelled(.shutdown))
        }
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
            diagnosticsBroadcaster.finish()
            metricsBroadcaster.finish()
        }
        self.shutdownTask = shutdownTask
        await shutdownTask.value
    }

    // MARK: - Errors

    func shutdownFailure() -> PlaybackFailure {
        PlaybackFailure(
            code: .playback,
            message: "The playback engine has been shut down."
        )
    }
}
