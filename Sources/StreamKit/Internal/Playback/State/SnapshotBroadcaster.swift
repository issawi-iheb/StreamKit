//
//  SnapshotBroadcaster.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation

/// Publishes playback snapshots to independent subscribers.
@MainActor
final class SnapshotBroadcaster {

    private var continuations:
        [UUID: AsyncStream<PlaybackSnapshot>.Continuation] = [:]

    private var isFinished = false

    /// Creates a stream that begins with the current snapshot.
    func makeStream(
        initialSnapshot: PlaybackSnapshot
    ) -> AsyncStream<PlaybackSnapshot> {
        let id = UUID()

        return AsyncStream(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in

            continuation.yield(initialSnapshot)

            guard !isFinished else {
                continuation.finish()
                return
            }

            continuations[id] = continuation

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.removeContinuation(id)
                }
            }
        }
    }

    /// Publishes a new snapshot to all active subscribers.
    func publish(_ snapshot: PlaybackSnapshot) {
        guard !isFinished else { return }

        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    /// Publishes the final snapshot and finishes every stream.
    func finish(with finalSnapshot: PlaybackSnapshot) {
        guard !isFinished else { return }

        isFinished = true

        for continuation in continuations.values {
            continuation.yield(finalSnapshot)
            continuation.finish()
        }

        continuations.removeAll()
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
