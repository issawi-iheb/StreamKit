import Foundation

/// Publishes bounded diagnostic history to independent subscribers.
@MainActor
final class PlaybackDiagnosticsBroadcaster {
    private let historyLimit: Int
    private let subscriberBufferLimit: Int
    private var history: [PlaybackDiagnosticEvent] = []
    private var continuations: [UUID: AsyncStream<PlaybackDiagnosticEvent>.Continuation] = [:]
    private var nextSequence: UInt64 = 0
    private var isFinished = false

    init(historyLimit: Int = 64, subscriberBufferLimit: Int = 128) {
        self.historyLimit = max(1, historyLimit)
        self.subscriberBufferLimit = max(1, subscriberBufferLimit)
    }

    func makeStream() -> AsyncStream<PlaybackDiagnosticEvent> {
        let id = UUID()
        var capturedContinuation: AsyncStream<PlaybackDiagnosticEvent>.Continuation!
        let stream = AsyncStream<PlaybackDiagnosticEvent>(
            bufferingPolicy: .bufferingNewest(subscriberBufferLimit)
        ) { continuation in
            capturedContinuation = continuation
            for event in history {
                continuation.yield(event)
            }
        }

        guard !isFinished else {
            capturedContinuation.finish()
            return stream
        }

        continuations[id] = capturedContinuation
        capturedContinuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuations.removeValue(forKey: id)
            }
        }
        return stream
    }

    @discardableResult
    func publish(
        kind: PlaybackDiagnosticEvent.Kind,
        loadGeneration: UInt64
    ) -> PlaybackDiagnosticEvent {
        nextSequence &+= 1
        let event = PlaybackDiagnosticEvent(
            sequence: nextSequence,
            timestamp: .now,
            loadGeneration: loadGeneration,
            kind: kind
        )

        guard !isFinished else { return event }

        history.append(event)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
        for continuation in continuations.values {
            continuation.yield(event)
        }
        return event
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
