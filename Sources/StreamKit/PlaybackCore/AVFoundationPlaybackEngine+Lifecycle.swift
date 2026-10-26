import AVFoundation
import Foundation

extension AVFoundationPlaybackEngine {

// MARK: - Shutdown

    func shutdown() async {
        guard !isShutdown else {
            return
        }

        isShutdown = true
        loadGeneration &+= 1

        cancelPendingReadiness()
        // Keep shutdown cleanup complete even if readiness state and the
        // observation ever become temporarily out of sync.
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        removePlaybackObservers()
        authenticatedResourceLoader?.cancelAll()
        authenticatedResourceLoader = nil
        fairPlayContentKeySession?.invalidate()
        fairPlayContentKeySession = nil

        player.pause()
        player.replaceCurrentItem(with: nil)

        eventContinuation?.finish()
        eventContinuation = nil
    }

    func shutdownFailure() -> PlaybackFailure {
        PlaybackFailure(
            code: .playback,
            message: "The playback engine has been shut down."
        )
    }
}
