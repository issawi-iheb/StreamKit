import Foundation
import AVFoundation

extension StreamPlayerController {

// MARK: - Seeking

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
        let seekStartTime = snapshot.currentTime
        let adBreakGenerationAtStart = clientSideAdBreakGeneration
        try validateClientSideForwardSeek(from: seekStartTime, to: time)
        let generation = loadGeneration
        let seekGeneration = beginSeek()

        try await engine.seek(to: time)

        guard !isShutdown,
              loadGeneration == generation,
              self.seekGeneration == seekGeneration
        else {
            throw CancellationError()
        }

        try await revalidateClientSideSeekAfterAwait(
            from: seekStartTime,
            to: time,
            adBreakGenerationAtStart: adBreakGenerationAtStart,
            loadGeneration: generation,
            seekGeneration: seekGeneration
        )

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

        let seekStartTime = snapshot.currentTime
        let targetTime = snapshot.timeline.latestSeekableTime
            .map { $0 - offsetFromLive }
        let adBreakGenerationAtStart = clientSideAdBreakGeneration

        if snapshot.adBreak?.deliveryMode == .clientSide,
           snapshot.adBreak?.restrictsForwardSeeking == true {
            guard let targetTime else {
                throw PlaybackFailure(
                    code: .adPlaybackRestricted,
                    message: "Seeking to the live edge is restricted during this ad break."
                )
            }

            try validateClientSideForwardSeek(
                from: seekStartTime,
                to: targetTime
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

        let observedTargetTime = snapshot.currentTime != seekStartTime
            ? snapshot.currentTime
            : targetTime
        try await revalidateClientSideSeekAfterAwait(
            from: seekStartTime,
            to: observedTargetTime,
            adBreakGenerationAtStart: adBreakGenerationAtStart,
            loadGeneration: generation,
            seekGeneration: seekGeneration,
            assumeForwardWhenTargetIsUnknown: true
        )
    }

    private func validateClientSideForwardSeek(
        from currentTime: TimeInterval,
        to targetTime: TimeInterval
    ) throws {
        guard let adBreak = snapshot.adBreak,
              adBreak.deliveryMode == .clientSide,
              adBreak.restrictsForwardSeeking
        else {
            return
        }

        guard PlaybackInterstitialSeekPolicy.activeBreakRestrictsForwardSeek(
            from: currentTime,
            to: targetTime,
            restrictsForwardSeeking: true
        ) else {
            return
        }

        throw PlaybackFailure(
            code: .adPlaybackRestricted,
            message: "Forward seeking is restricted during this ad break."
        )
    }

    private func revalidateClientSideSeekAfterAwait(
        from safeTime: TimeInterval,
        to targetTime: TimeInterval?,
        adBreakGenerationAtStart: UInt64,
        loadGeneration: UInt64,
        seekGeneration: UInt64,
        assumeForwardWhenTargetIsUnknown: Bool = false
    ) async throws {
        let breakStartedDuringSeek =
            clientSideAdBreakGeneration != adBreakGenerationAtStart

        do {
            if let targetTime {
                if breakStartedDuringSeek, targetTime > safeTime {
                    throw PlaybackFailure(
                        code: .adPlaybackRestricted,
                        message: "Forward seeking is restricted when an ad break starts during the seek."
                    )
                }

                try validateClientSideForwardSeek(
                    from: safeTime,
                    to: targetTime
                )
            } else if breakStartedDuringSeek,
                      assumeForwardWhenTargetIsUnknown {
                throw PlaybackFailure(
                    code: .adPlaybackRestricted,
                    message: "Seeking to the live edge is restricted when an ad break starts during the seek."
                )
            }
        } catch let failure as PlaybackFailure
            where failure.code == .adPlaybackRestricted {
            do {
                try await engine.seek(to: safeTime)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard !isShutdown,
                      self.loadGeneration == loadGeneration,
                      self.seekGeneration == seekGeneration else {
                    throw CancellationError()
                }

                await engine.pause()
                throw PlaybackFailure(
                    code: .adPlaybackRestricted,
                    message: "Forward seeking is restricted during the ad break, and the previous content position could not be restored."
                )
            }

            guard !isShutdown,
                  self.loadGeneration == loadGeneration,
                  self.seekGeneration == seekGeneration else {
                throw CancellationError()
            }

            updateSnapshotCurrentTime(safeTime)
            await reconcileTransportIntent()
            throw failure
        }
    }

    private func updateSnapshotCurrentTime(_ currentTime: TimeInterval) {
        updateSnapshot(
            PlaybackSnapshot(
                phase: snapshot.phase,
                intent: snapshot.intent,
                currentTime: currentTime,
                duration: snapshot.duration,
                failure: snapshot.failure,
                timeline: snapshot.timeline
            )
        )
    }
}
