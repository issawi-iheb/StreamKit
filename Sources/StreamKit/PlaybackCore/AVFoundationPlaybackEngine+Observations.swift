import AVFoundation
import Foundation

extension AVFoundationPlaybackEngine {

// MARK: - Playback Observers

    func installPlaybackObservers(
        for item: AVPlayerItem,
        generation: UInt64,
        presentationKind: MediaPresentationKind
    ) {
        // Observe AVPlayer playback state.
        timeControlStatusObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self, weak item] player, _ in
            guard let item else { return }

            // Read the AVPlayer status while handling the callback,
            // then hop to the main actor for event delivery.
            let status = player.timeControlStatus

            Task { @MainActor [weak self, weak item] in
                guard let self, let item else { return }

                self.handleTimeControlStatus(
                    status,
                    for: item,
                    generation: generation
                )
            }
        }

        // Publish the current playback position periodically.
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(
                seconds: 0.5,
                preferredTimescale: 600
            ),
            queue: .main
        ) { [weak self, weak item] time in
            guard let item else { return }

            let currentTime = time.seconds

            Task { @MainActor [weak self, weak item] in
                guard let self, let item,
                      self.isCurrentItem(item, generation: generation),
                      currentTime.isFinite,
                      currentTime >= 0 else {
                    return
                }

                let duration = item.duration.seconds
                let validDuration: TimeInterval? =
                    duration.isFinite && duration >= 0
                    ? duration
                    : nil
                let timeline = self.timeline(
                    for: item,
                    presentationKind: presentationKind
                )

                self.emit(
                    .timeUpdated(
                        currentTime: currentTime,
                        duration: validDuration,
                        timeline: timeline
                    )
                )
            }
        }

        // Detect normal playback completion.
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item,
                      self.isCurrentItem(item, generation: generation) else {
                    return
                }

                self.emit(.ended)
            }
        }

        // Detect asynchronous item playback failures.
        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] notification in
            let error = notification.userInfo?[
                AVPlayerItemFailedToPlayToEndTimeErrorKey
            ] as? Error

            Task { @MainActor [weak self, weak item] in
                guard let self, let item,
                      self.isCurrentItem(item, generation: generation) else {
                    return
                }

                self.emitFailure(
                    error ?? item.error,
                    fallbackMessage: "Playback failed before reaching the end."
                )
            }
        }
    }

    private func handleTimeControlStatus(
        _ status: AVPlayer.TimeControlStatus,
        for item: AVPlayerItem,
        generation: UInt64
    ) {
        guard isCurrentItem(item, generation: generation),
              player.timeControlStatus == status else {
            return
        }

        switch status {
        case .playing:
            stopPausedLiveTimelineUpdates()
        // Apply the selected rate once playback has actually started.
        // This also supports platforms where defaultRate is unavailable.
            if player.rate != playbackRate {
                player.rate = playbackRate
            }

            emit(.playing)

        case .waitingToPlayAtSpecifiedRate:
            stopPausedLiveTimelineUpdates()
            emit(.waiting)

        case .paused:
            // AVPlayer begins in `.paused` while a new item is still loading.
            // Do not publish that transport state until readiness is known.
            guard item.status == .readyToPlay else { return }
            emit(.paused)
            startPausedLiveTimelineUpdates(for: item, generation: generation)

        @unknown default:
            break
        }
    }

    private func startPausedLiveTimelineUpdates(
        for item: AVPlayerItem,
        generation: UInt64
    ) {
        guard keepsLiveTimelineCurrentWhilePaused,
              item.canUseNetworkResourcesForLiveStreamingWhilePaused,
              pausedLiveTimelineTimer == nil else {
            return
        }

        pausedLiveTimelineTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item,
                      self.player.timeControlStatus == .paused,
                      self.isCurrentItem(item, generation: generation) else {
                    return
                }

                self.emit(.timelineUpdated(self.timeline(for: item, presentationKind: .live)))
            }
        }
    }

    func stopPausedLiveTimelineUpdates() {
        pausedLiveTimelineTimer?.invalidate()
        pausedLiveTimelineTimer = nil
    }

    private func timeline(
        for item: AVPlayerItem,
        presentationKind: MediaPresentationKind
    ) -> PlaybackTimeline {
        let seekableRanges = item.seekableTimeRanges.compactMap { value -> PlaybackTimeRange? in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds

            guard start.isFinite, end.isFinite, end >= start else { return nil }
            return PlaybackTimeRange(start: start, end: end)
        }
        return PlaybackTimeline(
            seekableRanges: seekableRanges,
            currentDate: item.currentDate(),
            presentationKind: presentationKind
        )
    }

    func isCurrentItem(
        _ item: AVPlayerItem,
        generation: UInt64
    ) -> Bool {
        !isShutdown
            && loadGeneration == generation
            && observedItem === item
            && player.currentItem === item
    }

    // MARK: - Event Delivery

    private func emit(_ event: PlaybackEngineEvent) {
        guard !isShutdown else { return }

        eventContinuation?.yield(
            PlaybackEngineEventEnvelope(
                generation: activeSourceGeneration,
                event: event
            )
        )
    }

    private func emitFailure(
        _ error: Error?,
        fallbackMessage: String
    ) {
        let mappedFailure = PlaybackFailureMapping.map(error)
        let failure = error == nil
            ? PlaybackFailure(code: .playback, message: fallbackMessage)
            : mappedFailure

        emit(.failed(failure))
    }

    // MARK: - Observer Cleanup

    func removePlaybackObservers() {
        stopPausedLiveTimelineUpdates()
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil

        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }

        if let itemFailureObserver {
            NotificationCenter.default.removeObserver(itemFailureObserver)
            self.itemFailureObserver = nil
        }

        observedItem = nil
    }
}
