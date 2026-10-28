import AVFoundation
import Foundation

extension AVFoundationPlaybackEngine {

// MARK: - Loading

    func load(_ source: MediaSource, generation sourceGeneration: UInt64) async throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        try Task.checkCancellation()

        guard sourceGeneration > activeSourceGeneration else {
            throw CancellationError()
        }

        activeSourceGeneration = sourceGeneration

        loadGeneration &+= 1
        let engineGeneration = loadGeneration

        // Invalidate the previous generation before cancelling its load.
        removePlaybackObservers()
        authenticatedResourceLoader?.cancelAll()
        authenticatedResourceLoader = nil
        fairPlayContentKeySession?.invalidate()
        fairPlayContentKeySession = nil
        cancelPendingReadiness()
        player.pause()
        player.replaceCurrentItem(with: nil)

        let preparedItem = try AVFoundationPlaybackItemFactory.make(
            from: source,
            fairPlayDiagnosticHandler: { [weak self] diagnostic in
                switch diagnostic {
                case .contentKeyResponseAccepted:
                    self?.emit(
                        .fairPlayContentKeyResponseAccepted,
                        generation: sourceGeneration
                    )
                case let .contentKeyRequestFailed(_, errorCode):
                    self?.emit(
                        .fairPlayContentKeyRequestFailed(errorCode: errorCode),
                        generation: sourceGeneration
                    )
                }
            }
        )
        authenticatedResourceLoader = preparedItem.authenticatedResourceLoader
        fairPlayContentKeySession = preparedItem.fairPlayContentKeySession
        let item = preparedItem.item
        if source.presentationKind == .live,
           keepsLiveTimelineCurrentWhilePaused {
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        }
        observedItem = item
        player.replaceCurrentItem(with: item)

        installPlaybackObservers(
            for: item,
            generation: engineGeneration,
            presentationKind: source.presentationKind
        )
        if #available(macOS 15, iOS 18, *) {
            installMetricsObserver(
                for: item,
                engineGeneration: engineGeneration,
                sourceGeneration: sourceGeneration
            )
        }
        try await waitForReadiness(of: item, generation: engineGeneration)
    }

    private func waitForReadiness(of item: AVPlayerItem, generation engineGeneration: UInt64) async throws {
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
                self?.cancelLoad(for: engineGeneration)
            }
        }
    }

    private func cancelLoad(for generation: UInt64) {
        guard !isShutdown, loadGeneration == generation else {
            return
        }

        cancelPendingReadiness(for: generation)
        removePlaybackObservers()
        authenticatedResourceLoader?.cancelAll()
        authenticatedResourceLoader = nil
        fairPlayContentKeySession?.invalidate()
        fairPlayContentKeySession = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
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
            let failure = PlaybackFailureMapping.map(item.error)

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

    func cancelPendingReadiness(
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
}
