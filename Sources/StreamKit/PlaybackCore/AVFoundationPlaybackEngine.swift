//
//  AVFoundationPlaybackEngine.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

import AVFoundation
import Foundation

/// AVFoundation-backed playback engine for a single player instance.
///
/// All player coordination is isolated to the main actor.
/// Each instance owns its own AVPlayer and playback resources.
@MainActor
final class AVFoundationPlaybackEngine: PlaybackEngine {

    // MARK: - Properties

    private let player: AVPlayer

    private let eventStream: AsyncStream<PlaybackEngineEventEnvelope>
    private var eventContinuation: AsyncStream<PlaybackEngineEventEnvelope>.Continuation?

    // Item readiness observation.
    private var itemStatusObservation: NSKeyValueObservation?

    // Playback observations.
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?

    // Current item identity and generation.
    private var observedItem: AVPlayerItem?
    private var loadGeneration: UInt64 = 0
    private var activeSourceGeneration: UInt64 = 0

    // Pending load readiness.
    private var pendingReadiness: CheckedContinuation<Void, Error>?
    private var pendingLoadGeneration: UInt64?

    private var isShutdown = false

    var events: AsyncStream<PlaybackEngineEventEnvelope> {
        eventStream
    }

    // MARK: - Initialization

    init() {
        let stream = AsyncStream<PlaybackEngineEventEnvelope>.makeStream(
            bufferingPolicy: .unbounded
        )

        self.player = AVPlayer()
        self.eventStream = stream.stream
        self.eventContinuation = stream.continuation
    }

    // MARK: - Loading

    func load(_ source: MediaSource, generation sourceGeneration: UInt64) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        activeSourceGeneration = sourceGeneration

        loadGeneration &+= 1
        let engineGeneration = loadGeneration

        // Invalidate the previous generation before cancelling its load.
        removePlaybackObservers()
        loadGeneration = engineGeneration
        cancelPendingReadiness()

        let asset = AVURLAsset(url: source.url)
        let item = AVPlayerItem(asset: asset)

        observedItem = item
        player.replaceCurrentItem(with: item)

        installPlaybackObservers(for: item, generation: engineGeneration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                guard !Task.isCancelled else {
                    continuation.resume(
                        throwing: CancellationError()
                    )
                    return
                }

                guard !isShutdown,
                      loadGeneration == engineGeneration,
                      player.currentItem === item else {
                    continuation.resume(
                        throwing: CancellationError()
                    )
                    return
                }

                pendingReadiness = continuation
                pendingLoadGeneration = engineGeneration

                itemStatusObservation = item.observe(
                    \.status,
                    options: [.initial, .new]
                ) { [weak self, weak item] _, _ in
                    guard let item else { return }

                    Task { @MainActor [weak self, weak item] in
                        guard let self, let item else { return }

                        self.handleItemStatus(
                            item,
                            generation: engineGeneration
                        )
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingReadiness(for: engineGeneration)
            }
        }
    }

    private func handleItemStatus(
        _ item: AVPlayerItem,
        generation: UInt64
    ) {
        guard !isShutdown,
              loadGeneration == generation,
              observedItem === item,
              player.currentItem === item else {
            return
        }

        guard pendingLoadGeneration == generation else {
            return
        }

        switch item.status {
        case .unknown:
            break

        case .readyToPlay:
            completeReadiness(
                with: nil,
                generation: generation
            )

        case .failed:
            let failure = PlaybackFailure(
                code: .playback,
                message: item.error?.localizedDescription
                    ?? "The media item failed to load."
            )

            completeReadiness(
                with: failure,
                generation: generation
            )

        @unknown default:
            let failure = PlaybackFailure(
                code: .unknown,
                message: "The media item entered an unknown state."
            )

            completeReadiness(
                with: failure,
                generation: generation
            )
        }
    }

    private func completeReadiness(
        with error: Error?,
        generation: UInt64
    ) {
        guard pendingLoadGeneration == generation else {
            return
        }

        let continuation = pendingReadiness

        pendingReadiness = nil
        pendingLoadGeneration = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    private func cancelPendingReadiness(
        for generation: UInt64? = nil
    ) {
        guard let pendingGeneration = pendingLoadGeneration else {
            return
        }

        if let generation, generation != pendingGeneration {
            return
        }

        let continuation = pendingReadiness

        pendingReadiness = nil
        pendingLoadGeneration = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        continuation?.resume(
            throwing: CancellationError()
        )
    }

    // MARK: - Playback Observers

    private func installPlaybackObservers(
        for item: AVPlayerItem,
        generation: UInt64
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
            let duration = item.duration.seconds

            Task { @MainActor [weak self, weak item] in
                guard let self, let item,
                      self.isCurrentItem(item, generation: generation),
                      currentTime.isFinite,
                      currentTime >= 0 else {
                    return
                }

                let validDuration: TimeInterval? =
                    duration.isFinite && duration >= 0
                    ? duration
                    : nil

                self.emit(
                    .timeUpdated(
                        currentTime: currentTime,
                        duration: validDuration
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
        guard isCurrentItem(item, generation: generation) else {
            return
        }

        switch status {
        case .playing:
            emit(.playing)

        case .waitingToPlayAtSpecifiedRate:
            emit(.waiting)

        case .paused:
            // Pause is initiated explicitly through pause().
            // No paused event exists in PlaybackEngineEvent.
            break

        @unknown default:
            break
        }
    }

    private func isCurrentItem(
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
        let failure = PlaybackFailure(
            code: .playback,
            message: error?.localizedDescription ?? fallbackMessage
        )

        emit(.failed(failure))
    }

    // MARK: - Observer Cleanup

    private func removePlaybackObservers() {
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

        player.play()
    }

    func pause() async {
        guard !isShutdown else {
            return
        }

        player.pause()
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

        guard player.currentItem != nil else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a media source before seeking."
            )
        }

        let target = CMTime(
            seconds: time,
            preferredTimescale: 600
        )

        let completed = await player.seek(
            to: target,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )

        guard completed else {
            throw CancellationError()
        }
    }

    // MARK: - Shutdown

    func shutdown() async {
        guard !isShutdown else {
            return
        }

        isShutdown = true
        loadGeneration &+= 1

        cancelPendingReadiness()
        removePlaybackObservers()

        player.pause()
        player.replaceCurrentItem(with: nil)

        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func shutdownFailure() -> PlaybackFailure {
        PlaybackFailure(
            code: .playback,
            message: "The playback engine has been shut down."
        )
    }
}
