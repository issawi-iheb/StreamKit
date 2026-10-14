//
//  StreamPlayerControllerTests.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController")
@MainActor
struct StreamPlayerControllerTests {

    @Test("An event from a previous source must not modify the new source")
    func ignoresEventFromPreviousSource() async throws {
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

        // Load source A.
        let loadA = controller.load(sourceA)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await loadA.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.currentTime == 0)

        var snapshots = controller.snapshots.makeAsyncIterator()

        // Start source B, making source A's events stale.
        let loadB = controller.load(sourceB)
        await engine.waitForLoad(id: 2)

        #expect(controller.snapshot.phase == .loading)
        #expect(controller.snapshot.currentTime == 0)

        engine.completeLoad(id: 2)
        try await loadB.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.currentTime == 0)

        // Queue an event from A and a valid event from B.
        engine.emit(
            .timeUpdated(currentTime: 42, duration: 120),
            fromLoad: 1
        )
        engine.emit(
            .timeUpdated(currentTime: 5, duration: 120),
            fromLoad: 2
        )
        engine.deliverQueuedEvents()

        var receivedStaleUpdate = false
        var receivedCurrentUpdate = false

        // Wait for B's update so the test cannot hang waiting for a stale event.
        while !receivedCurrentUpdate, let snapshot = await snapshots.next() {
            if snapshot.currentTime == 42 {
                receivedStaleUpdate = true
            }

            if snapshot.currentTime == 5 {
                receivedCurrentUpdate = true
            }
        }

        #expect(receivedCurrentUpdate)
        #expect(
            !receivedStaleUpdate,
            "An event from source A must not modify source B's snapshot."
        )

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

    @Test("Pausing updates the snapshot to paused")
    func pauseUpdatesSnapshot() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        let handle = controller.load(source)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.play()

        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        #expect(controller.snapshot.intent == .play)

        await controller.pause()

        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .pause)

        await controller.shutdown()
    }

    @Test("A paused event does not override play intent")
    func pausedEventDoesNotOverridePlayIntent() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        let handle = controller.load(source)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await Task.yield()

        #expect(controller.snapshot.intent == .play)

        engine.emit(.paused, fromLoad: 1)
        engine.deliverQueuedEvents()

        // Allow the controller's event task to process the event.
        await Task.yield()

        #expect(controller.snapshot.phase == .playing)
        #expect(controller.snapshot.intent == .play)

        await controller.shutdown()
    }
    @Test("A playing event does not override pause intent")
    func playingEventDoesNotOverridePauseIntent() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        let handle = controller.load(source)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.play()
        // Simulate playback actually starting.
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await Task.yield()
        await controller.pause()

        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .pause)

        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()

        // Allow the controller's event task to process the event.
        await Task.yield()

        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .pause)

        await controller.shutdown()
    }
    @Test("Waiting persists until playback resumes")
    func waitingPersistsUntilPlaybackResumes() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        let handle = controller.load(source)
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.play()

        // Simulate playback starting.
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        #expect(controller.snapshot.phase == .playing)
        #expect(controller.snapshot.intent == .play)

        // Simulate buffering.
        engine.emit(.waiting, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.waiting, controller: controller)

        #expect(controller.snapshot.phase == .waiting)
        #expect(controller.snapshot.intent == .play)

        // Simulate playback resuming.
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        #expect(controller.snapshot.phase == .playing)
        #expect(controller.snapshot.intent == .play)

        await controller.shutdown()
    }

    @Test("Controller does not report playing before receiving playing event")
    func doesNotReportPlayingBeforeReceivingPlayingEvent() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        let handle = controller.load(source)

        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.play()

        // play() returning does not prove that playback has started.
        #expect(controller.snapshot.intent == .play)
        #expect(controller.snapshot.phase != .playing)

        await controller.shutdown()
    }

    @Test("Controller exposes available audio and subtitle tracks")
    func exposesAvailableTracks() async throws {
        let engine = MockPlaybackEngine()
        let audioTrack = MediaTrack(
            id: "audio:0",
            type: .audio,
            name: "English",
            languageCode: "en"
        )
        let subtitleTrack = MediaTrack(
            id: "subtitle:0",
            type: .subtitle,
            name: "French",
            languageCode: "fr"
        )

        engine.audioTracks = [audioTrack]
        engine.subtitleTracks = [subtitleTrack]

        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )
        let handle = controller.load(source)

        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        let audioTracks = try await controller.availableAudioTracks()
        let subtitleTracks = try await controller.availableSubtitleTracks()

        #expect(audioTracks == [audioTrack])
        #expect(subtitleTracks == [subtitleTrack])

        await controller.shutdown()
    }

    @Test("Controller forwards audio and subtitle selection")
    func forwardsTrackSelection() async throws {
        let engine = MockPlaybackEngine()
        engine.audioTracks = [
            MediaTrack(
                id: "audio:0",
                type: .audio,
                name: "English",
                languageCode: "en"
            )
        ]
        engine.subtitleTracks = [
            MediaTrack(
                id: "subtitle:0",
                type: .subtitle,
                name: "French",
                languageCode: "fr"
            )
        ]

        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )
        let handle = controller.load(source)

        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.selectAudioTrack(id: "audio:0")
        try await controller.selectSubtitleTrack(id: "subtitle:0")

        #expect(engine.selectedAudioTrackID == "audio:0")
        #expect(engine.selectedSubtitleTrackID == "subtitle:0")

        await controller.shutdown()
    }

    @Test("Controller can disable subtitles")
    func disablesSubtitles() async throws {
        let engine = MockPlaybackEngine()
        engine.subtitleTracks = [
            MediaTrack(
                id: "subtitle:0",
                type: .subtitle,
                name: "French",
                languageCode: "fr"
            )
        ]

        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )
        let handle = controller.load(source)

        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        try await controller.selectSubtitleTrack(id: "subtitle:0")
        try await controller.selectSubtitleTrack(id: nil)

        #expect(engine.subtitleSelectionWasRequested)
        #expect(engine.selectedSubtitleTrackID == nil)

        await controller.shutdown()
    }

    @Test("Track discovery fails before loading a source")
    func trackDiscoveryFailsBeforeLoading() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        do {
            _ = try await controller.availableAudioTracks()
            Issue.record("Expected audio track discovery to fail before loading")
        } catch {
            // Expected: no source has been loaded.
        }

        do {
            _ = try await controller.availableSubtitleTracks()
            Issue.record("Expected subtitle track discovery to fail before loading")
        } catch {
            // Expected: no source has been loaded.
        }

        await controller.shutdown()
    }

    @Test("Audio track selection fails after shutdown")
    func audioTrackSelectionFailsAfterShutdown() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        await controller.shutdown()

        do {
            try await controller.selectAudioTrack(id: "audio:0")
            Issue.record("Expected audio track selection to fail after shutdown")
        } catch {
            // Expected: the controller has been shut down.
        }
    }

    @Test("Subtitle track selection fails after shutdown")
    func subtitleTrackSelectionFailsAfterShutdown() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        await controller.shutdown()

        do {
            try await controller.selectSubtitleTrack(id: "subtitle:0")
            Issue.record("Expected subtitle track selection to fail after shutdown")
        } catch {
            // Expected: the controller has been shut down.
        }
    }

    @Test("Independent controllers do not interfere with each other")
    func independentControllersDoNotInterfere() async throws {
        let engine1 = MockPlaybackEngine()
        let engine2 = MockPlaybackEngine()

        let controller1 = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine1
        )
        let controller2 = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine2
        )

        let source1 = MediaSource(
            url: URL(string: "https://example.com/a.mp4")!
        )
        let source2 = MediaSource(
            url: URL(string: "https://example.com/b.mp4")!
        )

        let load1 = controller1.load(source1)
        let load2 = controller2.load(source2)

        await engine1.waitForLoad(id: 1)
        await engine2.waitForLoad(id: 1)

        engine1.completeLoad(id: 1)
        engine2.completeLoad(id: 1)

        try await load1.waitUntilReady()
        try await load2.waitUntilReady()

        #expect(controller1.snapshot.phase == .ready)
        #expect(controller2.snapshot.phase == .ready)

        // Playing controller 1 must not affect controller 2.
        try await controller1.play()
        engine1.emit(.playing, fromLoad: 1)
        engine1.deliverQueuedEvents()

        await waitForPhase(.playing, controller: controller1)

        #expect(controller1.snapshot.phase == .playing)
        #expect(controller2.snapshot.phase == .ready)
        #expect(controller2.snapshot.intent == .pause)

        // Shutting down controller 1 must not affect controller 2.
        await controller1.shutdown()

        #expect(controller1.snapshot.phase == .idle)
        #expect(controller2.snapshot.phase == .ready)

        // Controller 2 must remain independently usable.
        try await controller2.play()
        engine2.emit(.playing, fromLoad: 1)
        engine2.deliverQueuedEvents()

        await waitForPhase(.playing, controller: controller2)

        #expect(controller2.snapshot.phase == .playing)

        await controller2.shutdown()
    }

    private func waitForPhase(
        _ expectedPhase: PlaybackPhase,
        controller: StreamPlayerController
    ) async {
        var snapshots = controller.snapshots.makeAsyncIterator()

        while controller.snapshot.phase != expectedPhase {
            guard let snapshot = await snapshots.next() else {
                Issue.record("Snapshot stream ended before phase \(expectedPhase)")
                return
            }

            if snapshot.phase == expectedPhase {
                return
            }
        }
    }
}
