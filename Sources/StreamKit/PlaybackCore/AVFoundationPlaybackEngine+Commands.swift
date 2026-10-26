import AVFoundation
import Foundation

extension AVFoundationPlaybackEngine {

// MARK: - Playback Controls

    func play() async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard player.currentItem != nil else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a media source before playing."
            )
        }

        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            player.defaultRate = playbackRate
        }

        // Preserve AVPlayer's normal buffering and waiting behavior.
        player.play()
    }

    func pause() async {
        guard !isShutdown else {
            return
        }

        player.pause()
    }

    func setPlaybackRate(_ rate: Float) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard rate.isFinite, rate > 0, rate <= 32 else {
            throw PlaybackFailure(
                code: .invalidPlaybackRate,
                message: "The playback rate must be finite and greater than zero, and no greater than 32."
            )
        }

        playbackRate = rate

        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            player.defaultRate = rate
        }

        // Changing the rate must not start paused or waiting playback.
        if player.timeControlStatus == .playing {
            player.rate = rate
        }
    }

    func seek(to time: TimeInterval) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard time.isFinite, time >= 0 else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The seek position must be a finite, non-negative value."
            )
        }

        guard let item = player.currentItem else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a media source before seeking."
            )
        }

        let generation = loadGeneration

        let target = CMTime(
            seconds: time,
            preferredTimescale: 600
        )

        let completed = await player.seek(
            to: target,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )

        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard completed else {
            throw CancellationError()
        }
    }

    func seekToLiveEdge(offsetFromLive: TimeInterval) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard offsetFromLive.isFinite, offsetFromLive >= 0 else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The live offset must be finite and non-negative."
            )
        }

        guard let item = player.currentItem else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a live media source before seeking to its live edge."
            )
        }

        let generation = loadGeneration
        item.configuredTimeOffsetFromLive = CMTime(
            seconds: offsetFromLive,
            preferredTimescale: 600
        )

        let completed = await player.seek(to: .positiveInfinity)

        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard completed else {
            throw CancellationError()
        }
    }
}
