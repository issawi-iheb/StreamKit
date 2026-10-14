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
