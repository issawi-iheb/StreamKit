// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController load, seek, and shutdown lifecycle")
@MainActor
struct StreamPlayerControllerLifecycleTests {

    @Test("Time updates preserve an unknown duration")
    func timeUpdatesPreserveUnknownDuration() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let source = MediaSource(
            url: URL(string: "https://example.com/live.m3u8")!
        )

        let handle = controller.load(source)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        let timeline = PlaybackTimeline(
            seekableRanges: [
                PlaybackTimeRange(start: 120, end: 150),
                PlaybackTimeRange(start: 180, end: 210)
            ],
            currentDate: Date(timeIntervalSince1970: 1_798_000_000)
        )
        engine.emit(
            .timeUpdated(currentTime: 37, duration: nil, timeline: timeline),
            fromLoad: 1
        )
        engine.deliverQueuedEvents()

        await waitForCurrentTime(37, controller: controller)

        #expect(controller.snapshot.currentTime == 37)
        #expect(controller.snapshot.duration == nil)
        #expect(controller.snapshot.timeline == timeline)

        try await controller.play()
        await controller.pause()
        #expect(controller.snapshot.timeline == timeline)

        let seekTask = Task {
            try await controller.seek(to: 195)
        }
        await engine.waitForSeek(id: 1)
        engine.completeSeek(id: 1)
        try await seekTask.value
        #expect(controller.snapshot.currentTime == 195)
        #expect(controller.snapshot.timeline.seekableRanges == timeline.seekableRanges)
        #expect(controller.snapshot.timeline.currentDate == nil)

        await controller.shutdown()
    }

    @Test("Only the newest of several overlapping loads becomes ready")
    func severalOverlappingLoadsOnlyNewestBecomesReady() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let source = { (index: Int) in
            MediaSource(
                url: URL(string: "https://example.com/\(index).m3u8")!
            )
        }

        let handles = (1...5).map { index in
            controller.load(source(index))
        }

        for loadID in 1...5 {
            await engine.waitForLoad(id: loadID)
        }

        for loadID in 1...4 {
            engine.completeLoad(id: loadID)
            do {
                try await handles[loadID - 1].waitUntilReady()
                Issue.record("Superseded load \(loadID) unexpectedly succeeded.")
            } catch is CancellationError {
                // Expected: each subsequent load supersedes the prior one.
            }
        }

        #expect(controller.snapshot.phase == .loading)

        engine.completeLoad(id: 5)
        try await handles[4].waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.currentTime == 0)

        await controller.shutdown()
    }

    @Test("Repeatedly cancelled loads do not block a later load")
    func repeatedlyCancelledLoadsAllowRecovery() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        for loadID in 1...5 {
            let handle = controller.load(
                MediaSource(
                    url: URL(string: "https://example.com/cancel-\(loadID).m3u8")!
                )
            )
            await engine.waitForLoad(id: loadID)

            handle.cancel()

            do {
                try await handle.waitUntilReady()
                Issue.record("Cancelled load \(loadID) unexpectedly succeeded.")
            } catch is CancellationError {
                // Expected: cancellation resumes the pending load operation.
            }
        }

        let finalHandle = controller.load(
            MediaSource(url: URL(string: "https://example.com/recovered.m3u8")!)
        )
        await engine.waitForLoad(id: 6)
        engine.completeLoad(id: 6)
        try await finalHandle.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.failure == nil)

        await controller.shutdown()
    }

    @Test("A stale load completion must not override a newer load")
    func staleLoadCompletionDoesNotOverrideNewerLoad() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let sourceA = MediaSource(
            url: URL(string: "https://example.com/a.mp4")!
        )
        let sourceB = MediaSource(
            url: URL(string: "https://example.com/b.mp4")!
        )

        let loadA = controller.load(sourceA)
        await engine.waitForLoad(id: 1)

        #expect(controller.snapshot.phase == .loading)

        let loadB = controller.load(sourceB)
        await engine.waitForLoad(id: 2)

        #expect(controller.snapshot.phase == .loading)

        // A is now stale. Completing it must not make the controller ready.
        engine.completeLoad(id: 1)

        do {
            try await loadA.waitUntilReady()
            Issue.record("The stale load unexpectedly succeeded.")
        } catch is CancellationError {
            // Expected: load A was superseded by load B.
        }

        #expect(controller.snapshot.phase == .loading)

        // Only B may transition the controller to ready.
        engine.completeLoad(id: 2)
        try await loadB.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.currentTime == 0)

        await controller.shutdown()
    }

    @Test("A stale load failure must not override a newer load")
    func staleLoadFailureDoesNotOverrideNewerLoad() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let sourceA = MediaSource(
            url: URL(string: "https://example.com/a.mp4")!
        )
        let sourceB = MediaSource(
            url: URL(string: "https://example.com/b.mp4")!
        )

        let loadA = controller.load(sourceA)
        await engine.waitForLoad(id: 1)

        let loadB = controller.load(sourceB)
        await engine.waitForLoad(id: 2)

        #expect(controller.snapshot.phase == .loading)

        // Fail A after B has superseded it.
        engine.failLoad(
            id: 1,
            with: PlaybackFailure(
                code: .playback,
                message: "Stale load failure"
            )
        )
        _ = try? await loadA.waitUntilReady()

        // A's failure must not overwrite B's loading state.
        #expect(controller.snapshot.phase == .loading)
        #expect(controller.snapshot.failure == nil)

        engine.completeLoad(id: 2)
        try await loadB.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.failure == nil)

        await controller.shutdown()
    }

    @Test("A seek interrupted by a new load must not update the snapshot")
    func seekInterruptedByNewLoadDoesNotUpdateSnapshot() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let sourceA = MediaSource(
            url: URL(string: "https://example.com/a.mp4")!
        )
        let sourceB = MediaSource(
            url: URL(string: "https://example.com/b.mp4")!
        )

        // Load A and wait until it is ready.
        let loadA = controller.load(sourceA)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await loadA.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)

        // Suspend a seek on A.
        let seekTask = Task {
            try await controller.seek(to: 42)
        }

        await engine.waitForSeek(id: 1)
        #expect(engine.seekTimes == [42])

        // Loading B changes the generation while the seek is suspended.
        let loadB = controller.load(sourceB)
        await engine.waitForLoad(id: 2)

        #expect(controller.snapshot.phase == .loading)

        // Allow the old seek to return. Its generation is now stale.
        engine.completeSeek(id: 1)

        do {
            try await seekTask.value
            Issue.record("The seek unexpectedly succeeded after a new load started.")
        } catch is CancellationError {
            // Expected: the seek belongs to the previous load generation.
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }

        // The stale seek must not update the new source's snapshot.
        #expect(controller.snapshot.phase == .loading)
        #expect(controller.snapshot.currentTime == 0)

        engine.completeLoad(id: 2)
        try await loadB.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.currentTime == 0)

        await controller.shutdown()
    }

    @Test("An older seek cannot overwrite a newer seek on the same source")
    func olderSeekCannotOverwriteNewerSeek() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.mp4")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        let earlierSeek = Task {
            try await controller.seek(to: 42)
        }
        await engine.waitForSeek(id: 1)

        let laterSeek = Task {
            try await controller.seek(to: 84)
        }
        await engine.waitForSeek(id: 2)

        // Force the later request to complete first, then let the earlier
        // operation return after it has already been superseded.
        engine.completeSeek(id: 2)
        try await laterSeek.value
        #expect(controller.snapshot.currentTime == 84)

        engine.completeSeek(id: 1)
        do {
            try await earlierSeek.value
            Issue.record("The earlier seek unexpectedly succeeded after being superseded.")
        } catch is CancellationError {
            // Expected: only the most recently requested seek may commit.
        }

        #expect(controller.snapshot.currentTime == 84)
        await controller.shutdown()
    }

    @Test("Shutdown during loading leaves the controller idle")
    func shutdownDuringLoadingLeavesControllerIdle() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        // Start loading and leave the engine operation pending.
        let load = controller.load(source)
        await engine.waitForLoad(id: 1)

        #expect(controller.snapshot.phase == .loading)

        // Shutdown invalidates and cancels the active load.
        await controller.shutdown()

        #expect(controller.snapshot.phase == .idle)
        #expect(controller.snapshot.intent == .pause)
        #expect(controller.snapshot.failure == nil)

        // The pending load must not report success after shutdown.
        do {
            try await load.waitUntilReady()
            Issue.record("The load unexpectedly succeeded after shutdown.")
        } catch {
            // Expected: shutdown prevents the pending load from succeeding.
        }

        // Completing or failing the old load must not change the final snapshot.
        engine.completeLoad(id: 1)

        #expect(controller.snapshot.phase == .idle)
        #expect(controller.snapshot.intent == .pause)

        // Shutdown should remain safe when called more than once.
        await controller.shutdown()

        #expect(controller.snapshot.phase == .idle)
    }

    @Test("Concurrent shutdown callers wait for the same engine cleanup")
    func concurrentShutdownWaitsForEngineCleanup() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.mp4")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()
        #expect(controller.snapshot.phase == .ready)

        engine.suspendNextShutdown()
        var firstReturned = false
        var secondReturned = false

        let firstShutdown = Task {
            await controller.shutdown()
            firstReturned = true
        }
        await engine.waitForShutdownCall()

        let secondShutdown = Task {
            await controller.shutdown()
            secondReturned = true
        }
        await Task.yield()

        #expect(!firstReturned)
        #expect(!secondReturned)
        #expect(engine.shutdownCallCount == 1)
        #expect(controller.snapshot.phase == .ready)

        engine.completeShutdown()
        await firstShutdown.value
        await secondShutdown.value

        #expect(firstReturned)
        #expect(secondReturned)
        #expect(controller.snapshot.phase == .idle)
        #expect(controller.snapshot.intent == .pause)
    }

    @Test("Shutdown cancels a suspended seek")
    func shutdownDuringSuspendedSeekCancelsSeek() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.mp4")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        let seekTask = Task {
            try await controller.seek(to: 42)
        }

        await engine.waitForSeek(id: 1)
        #expect(engine.seekTimes == [42])

        await controller.shutdown()

        do {
            try await seekTask.value
            Issue.record("The seek unexpectedly succeeded after shutdown.")
        } catch is CancellationError {
            // Expected: shutdown cancelled the pending seek.
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }

        #expect(controller.snapshot.phase == .idle)
        #expect(controller.snapshot.intent == .pause)
    }
}
