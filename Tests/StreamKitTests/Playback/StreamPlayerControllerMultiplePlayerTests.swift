// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController multiple players")
@MainActor
struct StreamPlayerControllerMultiplePlayerTests {

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

    @Test("A shared audio focus coordinator pauses the previously focused player")
    func sharedAudioFocusPausesPreviousController() async throws {
        let focusCoordinator = AudioPlaybackFocusCoordinator()
        let firstEngine = MockPlaybackEngine()
        let secondEngine = MockPlaybackEngine()
        let firstController = StreamPlayerController(
            engine: firstEngine,
            audioPlaybackFocusCoordinator: focusCoordinator
        )
        let secondController = StreamPlayerController(
            engine: secondEngine,
            audioPlaybackFocusCoordinator: focusCoordinator
        )

        let firstLoad = firstController.load(
            MediaSource(url: URL(string: "https://example.com/first.m3u8")!)
        )
        let secondLoad = secondController.load(
            MediaSource(url: URL(string: "https://example.com/second.m3u8")!)
        )
        await firstEngine.waitForLoad(id: 1)
        await secondEngine.waitForLoad(id: 1)
        firstEngine.completeLoad(id: 1)
        secondEngine.completeLoad(id: 1)
        try await firstLoad.waitUntilReady()
        try await secondLoad.waitUntilReady()

        try await firstController.play()
        firstEngine.emit(.playing, fromLoad: 1)
        firstEngine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: firstController)

        try await secondController.play()

        #expect(!firstEngine.isPlaying)
        #expect(firstController.snapshot.phase == .paused)
        #expect(firstController.snapshot.intent == .pause)
        #expect(secondEngine.isPlaying)
        #expect(secondController.snapshot.intent == .play)

        await firstController.shutdown()
        await secondController.shutdown()
    }

    // MARK: - Playback Rate
}
