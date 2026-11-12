// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController transport")
@MainActor
struct StreamPlayerControllerTransportTests {

    @Test("Live-edge seek forwards the requested behind-live offset")
    func forwardsLiveEdgeOffset() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(
                url: URL(string: "https://example.com/live.m3u8")!,
                presentationKind: .live
            )
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        try await controller.seekToLiveEdge(offsetFromLive: 12)

        #expect(engine.liveEdgeSeekOffsets == [12])
        await controller.shutdown()
    }

    @Test("Live-edge seek rejects a source without explicit live semantics")
    func rejectsLiveEdgeSeekForUnspecifiedSource() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        do {
            try await controller.seekToLiveEdge()
            Issue.record("Expected live-edge seek to reject an unclassified source.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .unsupportedConfiguration)
        }

        #expect(engine.liveEdgeSeekOffsets.isEmpty)
        await controller.shutdown()
    }

    @Test("A superseded play failure cannot replace the latest paused state")
    func supersededPlayFailureDoesNotReplacePausedState() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        engine.suspendNextPlay()
        let playTask = Task { try await controller.play() }
        await engine.waitForPendingPlay()
        #expect(engine.playCallCount == 1)

        await controller.pause()
        engine.failPendingPlay(
            with: PlaybackFailure(code: .playback, message: "Late play failure")
        )

        var wasCancelled = false
        do {
            try await playTask.value
        } catch is CancellationError {
            wasCancelled = true
        } catch {
            Issue.record("Expected a superseded play request to cancel: \(error)")
        }

        #expect(wasCancelled)
        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .pause)
        await controller.shutdown()
    }

    @Test("Waiting for pending play resumes when play registers")
    func waitForPendingPlayResumesAfterRegistration() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        engine.suspendNextPlay()

        let playTask = Task {
            try await controller.play()
        }

        await engine.waitForPendingPlay()

        #expect(engine.playCallCount == 1)

        engine.completePendingPlay()
        try await playTask.value

        await controller.shutdown()
    }

    @Test("A late play completion cannot undo a newer pause")
    func latePlayCompletionCannotUndoPause() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        engine.suspendNextPlay()
        let playTask = Task {
            try await controller.play()
        }
        await engine.waitForPendingPlay()

        await controller.pause()
        #expect(!engine.isPlaying)

        // The mock applies the delayed play when it completes, modeling an
        // engine whose async play operation can take effect after suspension.
        engine.completePendingPlay()
        try await playTask.value

        #expect(!engine.isPlaying)
        #expect(controller.snapshot.intent == .pause)
        await controller.shutdown()
    }

    @Test("Shutdown cancels a pending play and leaves the engine idle")
    func shutdownDuringPendingPlayLeavesEngineIdle() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        engine.suspendNextPlay()
        let playTask = Task {
            try await controller.play()
        }
        await engine.waitForPendingPlay()

        await controller.shutdown()

        do {
            try await playTask.value
            Issue.record("The pending play unexpectedly succeeded after shutdown.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .playback)
        }

        #expect(!engine.isPlaying)
        #expect(controller.snapshot.phase == .idle)
    }

    @Test("A late play failure from a replaced source cannot fail the new source")
    func latePlayFailureDoesNotFailReplacementSource() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let firstLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/first.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await firstLoad.waitUntilReady()

        engine.suspendNextPlay()
        let playTask = Task { try await controller.play() }
        await engine.waitForPendingPlay()

        let replacementLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/replacement.m3u8")!)
        )
        await engine.waitForLoad(id: 2)
        engine.completeLoad(id: 2)
        try await replacementLoad.waitUntilReady()

        engine.failPendingPlay(
            with: PlaybackFailure(code: .playback, message: "Late old-source failure")
        )
        var wasCancelled = false
        do {
            try await playTask.value
        } catch is CancellationError {
            wasCancelled = true
        } catch {
            Issue.record("Expected replaced play request to cancel: \(error)")
        }

        #expect(wasCancelled)
        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .pause)
        await controller.shutdown()
    }

    @Test("A late play from a replaced source does not start the replacement")
    func latePlayCompletionDoesNotStartReplacementSource() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let firstLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/first.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await firstLoad.waitUntilReady()

        engine.suspendNextPlay()
        let playTask = Task {
            try await controller.play()
        }
        await engine.waitForPendingPlay()

        let replacementLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/replacement.m3u8")!)
        )
        await engine.waitForLoad(id: 2)
        engine.completeLoad(id: 2)
        try await replacementLoad.waitUntilReady()

        engine.completePendingPlay()
        do {
            try await playTask.value
            Issue.record("The old play unexpectedly succeeded for a replacement source.")
        } catch is CancellationError {
            // Expected: the play request belongs to the previous source.
        }

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .pause)
        #expect(!engine.isPlaying)
        await controller.shutdown()
    }

    @Test("Play after finite media ends seeks to the beginning before resuming")
    func playAfterEndRestartsFiniteMedia() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.mp4")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        engine.emit(.timeUpdated(currentTime: 30, duration: 30, timeline: .init()), fromLoad: 1)
        engine.emit(.ended, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.ended, controller: controller)

        let playTask = Task { try await controller.play() }
        await engine.waitForSeek(id: 1)

        #expect(engine.seekTimes == [0])
        #expect(engine.playCallCount == 0)

        engine.completeSeek(id: 1)
        try await playTask.value

        #expect(engine.playCallCount == 1)
        #expect(controller.snapshot.intent == .play)
        await controller.shutdown()
    }

    @Test("A pause during replay seek prevents playback from starting")
    func pauseDuringReplaySeekCancelsRestart() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.mp4")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        engine.emit(.timeUpdated(currentTime: 30, duration: 30, timeline: .init()), fromLoad: 1)
        engine.emit(.ended, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.ended, controller: controller)

        let playTask = Task { try await controller.play() }
        await engine.waitForSeek(id: 1)
        await controller.pause()
        engine.completeSeek(id: 1)
        try await playTask.value

        #expect(engine.playCallCount == 0)
        #expect(controller.snapshot.intent == .pause)
        await controller.shutdown()
    }

    @Test("Play after an ended item with unknown duration does not seek")
    func playAfterUnknownDurationEndDoesNotSeek() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/live.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        engine.emit(.timeUpdated(currentTime: 30, duration: nil, timeline: .init()), fromLoad: 1)
        engine.emit(.ended, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.ended, controller: controller)

        try await controller.play()

        #expect(engine.seekTimes.isEmpty)
        #expect(engine.playCallCount == 1)
        await controller.shutdown()
    }

    @Test("Autoplay waits for AVFoundation state before reporting playback")
    func autoplayWaitsForObservedPlaybackState() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: true),
            engine: engine
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )

        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .play)

        engine.emit(.waiting, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.waiting, controller: controller)

        #expect(controller.snapshot.phase == .waiting)
        #expect(controller.snapshot.intent == .play)

        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        #expect(controller.snapshot.phase == .playing)
        #expect(controller.snapshot.intent == .play)

        await controller.shutdown()
    }

    @Test("A pause during suspended autoplay remains the final engine command")
    func pauseDuringSuspendedAutoplayRemainsEffective() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: true),
            engine: engine
        )

        engine.suspendNextPlay()
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        await engine.waitForPendingPlay()

        await controller.pause()
        engine.completePendingPlay()
        try await load.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .pause)
        #expect(!engine.isPlaying)
        await controller.shutdown()
    }

    @Test("A late pause completion cannot override a newer play request")
    func latePauseCompletionReconcilesToLatestPlayIntent() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()
        try await controller.play()

        engine.suspendNextPause()
        let pauseTask = Task { await controller.pause() }
        await engine.waitForPendingPause()

        try await controller.play()
        #expect(controller.snapshot.intent == .play)

        engine.completePendingPause()
        await pauseTask.value

        #expect(controller.snapshot.intent == .play)
        #expect(engine.isPlaying)
        #expect(engine.playCallCount == 3)
        await controller.shutdown()
    }

    @Test("A late autoplay failure cannot fail a source after explicit pause")
    func lateAutoplayFailureDoesNotFailPausedSource() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: true),
            engine: engine
        )

        engine.suspendNextPlay()
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        await engine.waitForPendingPlay()

        await controller.pause()
        engine.failPendingPlay(
            with: PlaybackFailure(code: .playback, message: "Stale autoplay failure")
        )

        try await load.waitUntilReady()
        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .pause)
        #expect(controller.snapshot.failure == nil)
        #expect(!engine.isPlaying)
        await controller.shutdown()
    }
}
