//
//  LoadHandle.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation

/// Represents a specific media loading operation.
public struct LoadHandle: Sendable {

    private let readiness: Task<Void, Error>

    init(readiness: Task<Void, Error>) {
        self.readiness = readiness
    }

    /// Waits until this load operation is ready for playback.
    ///
    /// Cancelling the task awaiting this method does not automatically
    /// cancel the underlying loading operation.
    public func waitUntilReady() async throws {
        try await readiness.value
    }

    /// Cancels this loading operation.
    public func cancel() {
        readiness.cancel()
    }
}
