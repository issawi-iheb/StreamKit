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

        #expect(controller.snapshot.phase == .playing)
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
}
