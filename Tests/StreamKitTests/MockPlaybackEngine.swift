import Foundation
@testable import StreamKit

@MainActor
final class MockPlaybackEngine: PlaybackEngine {

    let events: AsyncStream<PlaybackEngineEventEnvelope>
    private let continuation: AsyncStream<PlaybackEngineEventEnvelope>.Continuation

    private var pendingLoads: [Int: CheckedContinuation<Void, Error>] = [:]
    private var pendingSeeks: [Int: CheckedContinuation<Void, Error>] = [:]
    private var registeredSeekIDs: Set<Int> = []
    private var seekRegistrationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var nextSeekID = 0
    private(set) var seekTimes: [TimeInterval] = []
    private(set) var liveEdgeSeekOffsets: [TimeInterval] = []
    private(set) var playbackRate: Float = 1.0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var shutdownCallCount = 0
    private(set) var isPlaying = false
    private var shouldSuspendNextShutdown = false
    private var pendingShutdown: CheckedContinuation<Void, Never>?
    private var shutdownRegistrationWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldSuspendNextPlay = false
    private var pendingPlay: CheckedContinuation<Void, Error>?
    private var pendingPlayRegistrationWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var shouldSuspendNextPause = false
    private var pendingPause: CheckedContinuation<Void, Never>?
    private var pendingPauseRegistrationWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldSuspendNextAudioTrackQuery = false
    private var pendingAudioTrackQuery: CheckedContinuation<[MediaTrack], Error>?
    private var audioTrackQueryRegistrationWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var registeredLoadIDs: Set<Int> = []
    private var loadRegistrationWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    private var nextLoadID = 0
    private var loadGenerations: [Int: UInt64] = [:]
    private var queuedEvents: [PlaybackEngineEventEnvelope] = []
    private(set) var loadSources: [MediaSource] = []

    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []

    private(set) var selectedAudioTrackID: String?
    private(set) var selectedSubtitleTrackID: String?
    private(set) var subtitleSelectionWasRequested = false


    init() {
        let stream = AsyncStream<PlaybackEngineEventEnvelope>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func suspendNextShutdown() {
        shouldSuspendNextShutdown = true
    }

    func waitForShutdownCall() async {
        guard shutdownCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            shutdownRegistrationWaiters.append(continuation)
        }
    }

    func completeShutdown() {
        guard let pendingShutdown else { return }
        self.pendingShutdown = nil
        pendingShutdown.resume()
    }

    // MARK: - Event Control

    func emit(_ event: PlaybackEngineEvent, fromLoad loadID: Int) {
        guard let generation = loadGenerations[loadID] else { return }

        queuedEvents.append(
            PlaybackEngineEventEnvelope(
                generation: generation,
                event: event
            )
        )
    }

    func deliverQueuedEvents() {
        for event in queuedEvents {
            continuation.yield(event)
        }

        queuedEvents.removeAll()
    }

    // MARK: - Load Control

    func load(_ source: MediaSource, generation: UInt64) async throws {
        isPlaying = false
        nextLoadID += 1
        let loadID = nextLoadID

        loadSources.append(source)
        loadGenerations[loadID] = generation
        registeredLoadIDs.insert(loadID)

        let waiters = loadRegistrationWaiters.removeValue(forKey: loadID) ?? []
        for waiter in waiters {
            waiter.resume()
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pendingLoads[loadID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelLoad(id: loadID)
            }
        }
    }

    func waitForLoad(id: Int) async {
        guard !registeredLoadIDs.contains(id) else {
            return
        }

        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in

            loadRegistrationWaiters[id, default: []].append(continuation)
        }
    }

    func completeLoad(id: Int) {
        guard let continuation = pendingLoads.removeValue(forKey: id) else {
            return
        }

        continuation.resume()
    }

    func failLoad(id: Int, with error: Error) {
        guard let continuation = pendingLoads.removeValue(forKey: id) else {
            return
        }

        continuation.resume(throwing: error)
    }

    private func cancelLoad(id: Int) {
        guard let continuation = pendingLoads.removeValue(forKey: id) else {
            return
        }

        continuation.resume(throwing: CancellationError())
    }

    func waitForSeek(id: Int) async {
        guard !registeredSeekIDs.contains(id) else {
            return
        }

        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in

            seekRegistrationWaiters[id, default: []].append(continuation)
        }
    }

    func completeSeek(id: Int) {
        guard let continuation = pendingSeeks.removeValue(forKey: id) else {
            return
        }

        continuation.resume()
    }

    func suspendNextPlay() {
        shouldSuspendNextPlay = true
    }

    func waitForPendingPlay() async {
        guard pendingPlay == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            // Recheck after entering the continuation closure.
            // MainActor isolation makes this registration atomic
            // relative to other operations on this mock.
            guard pendingPlay == nil else {
                continuation.resume()
                return
            }

            pendingPlayRegistrationWaiters.append(continuation)
        }
    }

    func failPendingPlay(with error: Error) {
        guard let continuation = pendingPlay else {
            return
        }

        pendingPlay = nil
        continuation.resume(throwing: error)
    }

    func completePendingPlay() {
        guard let continuation = pendingPlay else {
            return
        }

        pendingPlay = nil
        continuation.resume()
    }

    func suspendNextPause() {
        shouldSuspendNextPause = true
    }

    func waitForPendingPause() async {
        guard pendingPause == nil else { return }

        await withCheckedContinuation { continuation in
            guard pendingPause == nil else {
                continuation.resume()
                return
            }

            pendingPauseRegistrationWaiters.append(continuation)
        }
    }

    func completePendingPause() {
        guard let continuation = pendingPause else { return }

        pendingPause = nil
        continuation.resume()
    }

    func suspendNextAudioTrackQuery() {
        shouldSuspendNextAudioTrackQuery = true
    }

    func waitForPendingAudioTrackQuery() async {
        guard pendingAudioTrackQuery == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            guard pendingAudioTrackQuery == nil else {
                continuation.resume()
                return
            }

            audioTrackQueryRegistrationWaiters.append(continuation)
        }
    }

    func completePendingAudioTrackQuery() {
        guard let continuation = pendingAudioTrackQuery else {
            return
        }

        pendingAudioTrackQuery = nil
        continuation.resume(returning: audioTracks)
    }

    private func cancelPendingPlay() {
        failPendingPlay(with: CancellationError())
    }

    private func resumePendingPlayRegistrationWaiters() {
        let waiters = pendingPlayRegistrationWaiters
        pendingPlayRegistrationWaiters.removeAll()

        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - PlaybackEngine

    func play() async throws {
        playCallCount += 1

        if shouldSuspendNextPlay {
            shouldSuspendNextPlay = false

            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in

                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    pendingPlay = continuation
                    resumePendingPlayRegistrationWaiters()
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelPendingPlay()
                }
            }
        }

        // Model the engine applying playback when its async request completes.
        isPlaying = true
    }

    func pause() async {
        pauseCallCount += 1

        if shouldSuspendNextPause {
            shouldSuspendNextPause = false
            await withCheckedContinuation { continuation in
                pendingPause = continuation
                let waiters = pendingPauseRegistrationWaiters
                pendingPauseRegistrationWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        isPlaying = false
    }

    func setPlaybackRate(_ rate: Float) async throws {
        playbackRate = rate
    }

    func seek(to time: TimeInterval) async throws {
        nextSeekID += 1
        let seekID = nextSeekID

        seekTimes.append(time)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                pendingSeeks[seekID] = continuation
                registeredSeekIDs.insert(seekID)

                let waiters =
                    seekRegistrationWaiters.removeValue(forKey: seekID) ?? []

                for waiter in waiters {
                    waiter.resume()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelSeek(id: seekID)
            }
        }
    }

    func seekToLiveEdge(offsetFromLive: TimeInterval) async throws {
        liveEdgeSeekOffsets.append(offsetFromLive)
    }

    private func cancelSeek(id: Int) {
        guard let continuation = pendingSeeks.removeValue(forKey: id) else {
            return
        }

        continuation.resume(throwing: CancellationError())
    }


    func shutdown() async {
        shutdownCallCount += 1
        let shutdownWaiters = shutdownRegistrationWaiters
        shutdownRegistrationWaiters.removeAll()
        for waiter in shutdownWaiters {
            waiter.resume()
        }

        isPlaying = false

        // Cancel pending play.
        cancelPendingPlay()
        resumePendingPlayRegistrationWaiters()

        // Release pending pause calls.
        completePendingPause()
        let pauseWaiters = pendingPauseRegistrationWaiters
        pendingPauseRegistrationWaiters.removeAll()
        for waiter in pauseWaiters {
            waiter.resume()
        }

        // Cancel pending loads.
        let loads = pendingLoads.values
        pendingLoads.removeAll()

        for load in loads {
            load.resume(throwing: CancellationError())
        }

        // Cancel pending seeks.
        let seeks = pendingSeeks.values
        pendingSeeks.removeAll()

        for seek in seeks {
            seek.resume(throwing: CancellationError())
        }

        // Release load-registration waiters.
        let loadWaiters = loadRegistrationWaiters.values.flatMap { $0 }
        loadRegistrationWaiters.removeAll()

        for waiter in loadWaiters {
            waiter.resume()
        }

        // Release seek-registration waiters.
        let seekWaiters = seekRegistrationWaiters.values.flatMap { $0 }
        seekRegistrationWaiters.removeAll()

        for waiter in seekWaiters {
            waiter.resume()
        }

        if shouldSuspendNextShutdown {
            shouldSuspendNextShutdown = false
            await withCheckedContinuation { continuation in
                pendingShutdown = continuation
            }
        }

        continuation.finish()
    }

    func availableAudioTracks() async throws -> [MediaTrack] {
        if shouldSuspendNextAudioTrackQuery {
            shouldSuspendNextAudioTrackQuery = false

            return try await withCheckedThrowingContinuation { continuation in
                pendingAudioTrackQuery = continuation
                let waiters = audioTrackQueryRegistrationWaiters
                audioTrackQueryRegistrationWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        return audioTracks
    }

    func availableSubtitleTracks() async throws -> [MediaTrack] {
        subtitleTracks
    }

    func selectAudioTrack(id: String) async throws {
        guard audioTracks.contains(where: { $0.id == id }) else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The requested audio track is unavailable."
            )
        }

        selectedAudioTrackID = id
    }

    func selectSubtitleTrack(id: String?) async throws {
        subtitleSelectionWasRequested = true

        if let id {
            guard subtitleTracks.contains(where: { $0.id == id }) else {
                throw PlaybackFailure(
                    code: .invalidSource,
                    message: "The requested subtitle track is unavailable."
                )
            }
        }

        selectedSubtitleTrackID = id
    }
}
