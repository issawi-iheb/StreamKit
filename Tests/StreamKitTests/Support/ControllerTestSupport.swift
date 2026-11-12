// Shared helpers for StreamPlayerController behavior suites.

import Foundation
import Testing
@testable import StreamKit

@MainActor
func waitForPhase(
    _ expectedPhase: PlaybackPhase,
    controller: StreamPlayerController
) async {
    var snapshots = controller.snapshots.makeAsyncIterator()

    while controller.snapshot.phase != expectedPhase {
        guard let snapshot = await snapshots.next() else {
            Issue.record("Snapshot stream ended before phase \(expectedPhase)")
            return
        }

        if snapshot.phase == expectedPhase { return }
    }
}

@MainActor
func waitForCurrentTime(
    _ expectedTime: TimeInterval,
    controller: StreamPlayerController
) async {
    var snapshots = controller.snapshots.makeAsyncIterator()

    while controller.snapshot.currentTime != expectedTime {
        guard let snapshot = await snapshots.next() else {
            Issue.record("Snapshot stream ended before time \(expectedTime)")
            return
        }

        if snapshot.currentTime == expectedTime { return }
    }
}

@MainActor
func waitForPlayCallCount(
    _ expected: Int,
    engine: MockPlaybackEngine
) async {
    for _ in 0..<100 where engine.playCallCount < expected {
        await Task.yield()
    }
}

@MainActor
final class MockAudioInterruptionSource: AudioInterruptionSource {
    private let continuation: AsyncStream<AudioSessionInterruption>.Continuation
    let events: AsyncStream<AudioSessionInterruption>
    private(set) var shutdownCallCount = 0

    init() {
        var captured: AsyncStream<AudioSessionInterruption>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func send(_ event: AudioSessionInterruption) { continuation.yield(event) }

    func shutdown() {
        shutdownCallCount += 1
        continuation.finish()
    }
}
