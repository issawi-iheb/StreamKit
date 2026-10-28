import Foundation

/// Publishes bounded high-volume metric history to independent subscribers.
@MainActor
final class PlaybackMetricsBroadcaster {
    private let historyLimit: Int
    private let subscriberBufferLimit: Int
    private var history: [PlaybackMetricEvent] = []
    private var continuations: [UUID: AsyncStream<PlaybackMetricEvent>.Continuation] = [:]
    private var nextSequence: UInt64 = 0
    private var isFinished = false

    init(historyLimit: Int = 128, subscriberBufferLimit: Int = 256) {
        self.historyLimit = max(1, historyLimit)
        self.subscriberBufferLimit = max(1, subscriberBufferLimit)
    }

    func makeStream() -> AsyncStream<PlaybackMetricEvent> {
        let id = UUID()
        var capturedContinuation: AsyncStream<PlaybackMetricEvent>.Continuation!
        let stream = AsyncStream<PlaybackMetricEvent>(
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

    func publish(
        timestamp: Date,
        loadGeneration: UInt64,
        kind: PlaybackMetricEvent.Kind
    ) {
        guard !isFinished else { return }

        nextSequence &+= 1
        let event = PlaybackMetricEvent(
            sequence: nextSequence,
            timestamp: timestamp,
            loadGeneration: loadGeneration,
            kind: kind
        )
        history.append(event)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }
}
