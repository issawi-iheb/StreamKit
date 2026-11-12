import Foundation

/// Tracks cancellable waits for a PiP coordinator to return to its idle state.
@MainActor
final class PictureInPictureStopWaiters {
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    func waitUntilStopped(
        isStopped: @escaping @MainActor () -> Bool,
        onWaitStart: @escaping @MainActor () -> Void = {}
    ) async throws {
        try Task.checkCancellation()
        guard !isStopped() else { return }

        let waiterID = UUID()
        try await withTaskCancellationHandler(
            operation: {
                try await self.registerWaiter(
                    waiterID,
                    isStopped: isStopped,
                    onWaitStart: onWaitStart
                )
            },
            onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancel(waiterID)
                }
            }
        )
    }

    func resumeAll() {
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func registerWaiter(
        _ waiterID: UUID,
        isStopped: @escaping @MainActor () -> Bool,
        onWaitStart: @escaping @MainActor () -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            guard !Task.isCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }

            guard !isStopped() else {
                continuation.resume()
                return
            }

            continuations[waiterID] = continuation
            onWaitStart()
        }
    }

    private func cancel(_ waiterID: UUID) {
        guard let continuation = continuations.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume(throwing: CancellationError())
    }
}
