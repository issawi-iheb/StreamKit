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
    var renderingPlayer: AVPlayer {
        player
    }

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
    private var authenticatedResourceLoader: AuthenticatedMediaResourceLoader?
    private var fairPlayContentKeySession: FairPlayContentKeySession?
    private var loadGeneration: UInt64 = 0
    private var activeSourceGeneration: UInt64 = 0

    // Pending load readiness.
    private var pendingReadiness: CheckedContinuation<Void, Error>?
    private var pendingLoadGeneration: UInt64?

    private var isShutdown = false
    private var playbackRate: Float = 1.0

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

        if source.requestConfiguration.fairPlay != nil,
           source.url.scheme?.lowercased() != "https" {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "FairPlay-protected media must use HTTPS."
            )
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
        loadGeneration = engineGeneration
        cancelPendingReadiness()
        player.pause()
        player.replaceCurrentItem(with: nil)

        var assetOptions: [String: Any] = [:]
        let request = source.requestConfiguration
        if let userAgent = request.userAgent, !userAgent.isEmpty {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
                assetOptions[AVURLAssetHTTPUserAgentKey] = userAgent
            } else {
                throw PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "A custom User-Agent requires a newer operating system."
                )
            }
        }
        if !request.cookies.isEmpty {
            let cookies = request.cookies.compactMap { value in
                HTTPCookie(properties: [
                    .name: value.name,
                    .value: value.value,
                    .domain: value.domain,
                    .path: value.path,
                    .secure: value.isSecure ? "TRUE" : "FALSE"
                ])
            }
            guard cookies.count == request.cookies.count else {
                throw PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "One or more media cookies are invalid."
                )
            }
            assetOptions[AVURLAssetHTTPCookiesKey] = cookies
        }

        let assetURL: URL
        if let authentication = request.bearerAuthentication {
            guard authentication.trusts(source.url) else {
                throw PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "Bearer authentication must trust the media URL host."
                )
            }
            assetURL = try AuthenticatedMediaResourceLoader.assetURL(for: source.url)
            let resourceLoader = AuthenticatedMediaResourceLoader(
                authentication: authentication,
                cookies: request.cookies,
                userAgent: request.userAgent
            )
            authenticatedResourceLoader = resourceLoader
            let asset = AVURLAsset(url: assetURL, options: assetOptions)
            asset.resourceLoader.setDelegate(resourceLoader, queue: resourceLoader.delegateQueue)
            let item = AVPlayerItem(asset: asset)
            configureFairPlay(for: asset, configuration: request.fairPlay)
            observedItem = item
            player.replaceCurrentItem(with: item)

            installPlaybackObservers(for: item, generation: engineGeneration)
            try await waitForReadiness(of: item, generation: engineGeneration)
            return
        } else {
            assetURL = source.url
        }

        let asset = AVURLAsset(url: assetURL, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        configureFairPlay(for: asset, configuration: request.fairPlay)

        observedItem = item
        player.replaceCurrentItem(with: item)

        installPlaybackObservers(for: item, generation: engineGeneration)
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

    private func configureFairPlay(
        for asset: AVURLAsset,
        configuration: FairPlayConfiguration?
    ) {
        guard let configuration else { return }
        let contentKeySession = FairPlayContentKeySession(configuration: configuration)
        fairPlayContentKeySession = contentKeySession
        contentKeySession.addRecipient(asset)
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
        // Apply the selected rate once playback has actually started.
        // This also supports platforms where defaultRate is unavailable.
            if player.rate != playbackRate {
                player.rate = playbackRate
            }

            emit(.playing)

        case .waitingToPlayAtSpecifiedRate:
            emit(.waiting)

        case .paused:
            emit(.paused)

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
        let mappedFailure = PlaybackFailureMapping.map(error)
        let failure = error == nil
            ? PlaybackFailure(code: .playback, message: fallbackMessage)
            : mappedFailure

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
    
    // MARK: - Media Tracks

    func availableAudioTracks() async throws -> [MediaTrack] {
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .audible)

        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            return []
        }

        return group.options.enumerated().map { index, option in
            MediaTrack(
                id: "audio:\(index)",
                type: .audio,
                name: option.displayName,
                languageCode: option.locale?.identifier
            )
        }
    }

    func availableSubtitleTracks() async throws -> [MediaTrack] {
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .legible)

        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            return []
        }

        return group.options.enumerated().map { index, option in
            MediaTrack(
                id: "subtitle:\(index)",
                type: .subtitle,
                name: option.displayName,
                languageCode: option.locale?.identifier
            )
        }
    }

    func selectAudioTrack(id: String) async throws {
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .audible)

        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            throw invalidTrackFailure("No audio tracks are available.")
        }

        guard id.hasPrefix("audio:"),
              let index = Int(id.dropFirst("audio:".count)),
              group.options.indices.contains(index) else {
            throw invalidTrackFailure(
                "The requested audio track is unavailable."
            )
        }

        item.select(group.options[index], in: group)
    }

    func selectSubtitleTrack(id: String?) async throws {
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .legible)

        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            if id == nil {
                return
            }

            throw invalidTrackFailure("No subtitle tracks are available.")
        }

        guard let id else {
            item.select(nil, in: group)
            return
        }

        guard id.hasPrefix("subtitle:"),
              let index = Int(id.dropFirst("subtitle:".count)),
              group.options.indices.contains(index) else {
            throw invalidTrackFailure(
                "The requested subtitle track is unavailable."
            )
        }

        item.select(group.options[index], in: group)
    }
    private func currentTrackItem() throws -> AVPlayerItem {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard let item = player.currentItem,
              observedItem === item else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a media source before accessing its tracks."
            )
        }

        return item
    }

    private func invalidTrackFailure(_ message: String) -> PlaybackFailure {
        PlaybackFailure(
            code: .invalidSource,
            message: message
        )
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

    private func shutdownFailure() -> PlaybackFailure {
        PlaybackFailure(
            code: .playback,
            message: "The playback engine has been shut down."
        )
    }
}
