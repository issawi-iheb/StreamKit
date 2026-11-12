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

        if activeAdBreakState?.requiresPreferredPlaybackRate == true,
           rate != playbackRate {
            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "The preferred playback rate cannot be changed during this ad break."
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

        try validateInterstitialSeek(to: time, in: item)

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

    private func validateInterstitialSeek(
        to targetTime: TimeInterval,
        in item: AVPlayerItem
    ) throws {
        let currentTime = player.currentTime().seconds
        guard currentTime.isFinite, targetTime > currentTime else { return }

        if PlaybackInterstitialSeekPolicy.activeBreakRestrictsForwardSeek(
            from: currentTime,
            to: targetTime,
            restrictsForwardSeeking: activeAdBreakState?.restrictsForwardSeeking == true
        ) {
            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "Forward seeking is restricted during this ad break."
            )
        }

        let currentDate = item.currentDate()
        let targetDate = currentDate?.addingTimeInterval(targetTime - currentTime)

        if PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: currentTime,
            to: targetTime,
            currentDate: currentDate,
            targetDate: targetDate,
            scheduledRestrictions: restrictedInterstitialSeekRestrictions()
        ) {
            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "This seek would skip a required ad break."
            )
        }
    }

    private func restrictedInterstitialSeekRestrictions() -> [PlaybackInterstitialSeekRestriction] {
        guard let interstitialMonitor else { return [] }

        return interstitialMonitor.events.compactMap { event in
            guard event.restrictions.contains(.constrainsSeekingForwardInPrimaryContent) else {
                return nil
            }

            let time = event.time.isNumeric && event.time.seconds.isFinite
                ? event.time.seconds
                : nil
            let restriction = PlaybackInterstitialSeekRestriction(
                time: time,
                date: event.date
            )
            return restriction.time == nil && restriction.date == nil
                ? nil
                : restriction
        }
    }

    private func validateLiveEdgeSeek(in item: AVPlayerItem) throws {
        let currentTime = player.currentTime().seconds
        let liveEdgeTime = item.seekableTimeRanges
            .map { CMTimeRangeGetEnd($0.timeRangeValue).seconds }
            .filter(\.isFinite)
            .max()

        guard let currentTime = currentTime.isFinite ? currentTime : nil,
              let liveEdgeTime,
              liveEdgeTime > currentTime else {
            return
        }

        if PlaybackInterstitialSeekPolicy.activeBreakRestrictsForwardSeek(
            from: currentTime,
            to: liveEdgeTime,
            restrictsForwardSeeking: activeAdBreakState?.restrictsForwardSeeking == true
        ) {
            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "Seeking to the live edge is restricted during this ad break."
            )
        }

        let currentDate = item.currentDate()
        let liveEdgeDate = currentDate?.addingTimeInterval(liveEdgeTime - currentTime)

        if PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: currentTime,
            to: liveEdgeTime,
            currentDate: currentDate,
            targetDate: liveEdgeDate,
            scheduledRestrictions: restrictedInterstitialSeekRestrictions()
        ) {
            throw PlaybackFailure(
                code: .adPlaybackRestricted,
                message: "Seeking to the live edge would skip a required ad break."
            )
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

        try validateLiveEdgeSeek(in: item)

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
