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
    private(set) var playbackRate: Float = 1.0
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

    // MARK: - PlaybackEngine

    func play() async throws {
        // Intentionally emit no event.
        // Tests must explicitly control when playback events occur.
    }

    func pause() async {}

    func setPlaybackRate(_ rate: Float) async throws {
        playbackRate = rate
    }

    func seek(to time: TimeInterval) async throws {
        nextSeekID += 1
        let seekID = nextSeekID

        seekTimes.append(time)
        registeredSeekIDs.insert(seekID)

        let waiters = seekRegistrationWaiters.removeValue(forKey: seekID) ?? []
        for waiter in waiters {
            waiter.resume()
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            pendingSeeks[seekID] = continuation
        }
    }

    func shutdown() async {
        for continuation in pendingLoads.values {
            continuation.resume(throwing: CancellationError())
        }

        pendingLoads.removeAll()
        continuation.finish()

        for waiters in loadRegistrationWaiters.values {
            for waiter in waiters {
                waiter.resume()
            }
        }

        loadRegistrationWaiters.removeAll()
    }

    func availableAudioTracks() async throws -> [MediaTrack] {
        audioTracks
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
