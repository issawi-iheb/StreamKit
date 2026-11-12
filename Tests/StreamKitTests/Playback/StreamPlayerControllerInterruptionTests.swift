// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController audio interruptions")
@MainActor
struct StreamPlayerControllerInterruptionTests {

    @Test("Audio interruptions pause playback and resume when the system allows it")
    func resumesAfterAllowedAudioInterruption() async throws {
        let engine = MockPlaybackEngine()
        let interruptionSource = MockAudioInterruptionSource()
        let controller = StreamPlayerController(
            engine: engine,
            audioInterruptionSource: interruptionSource
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()
        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        interruptionSource.send(.began)
        await waitForPhase(.paused, controller: controller)

        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .play)
        #expect(engine.pauseCallCount == 1)

        interruptionSource.send(.ended(systemAllowsResume: true))
        await waitForPlayCallCount(2, engine: engine)

        #expect(engine.playCallCount == 2)
        #expect(controller.snapshot.intent == .play)
        await controller.shutdown()
        #expect(interruptionSource.shutdownCallCount == 1)
    }

    @Test("A late interruption-resume failure cannot replace an explicit pause")
    func lateInterruptionResumeFailureDoesNotReplacePause() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        await controller.handleAudioSessionInterruption(.began)
        engine.suspendNextPlay()
        let resumeTask = Task {
            await controller.handleAudioSessionInterruption(
                .ended(systemAllowsResume: true)
            )
        }
        await engine.waitForPendingPlay()

        // A newer user command supersedes the pending automatic resume.
        await controller.pause()
        engine.failPendingPlay(
            with: PlaybackFailure(code: .playback, message: "Late resume failure")
        )
        await resumeTask.value

        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .pause)
        #expect(controller.snapshot.failure == nil)
        await controller.shutdown()
    }

    @Test("A late interruption resume cannot undo an explicit pause")
    func lateInterruptionResumeCannotUndoPause() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        await controller.handleAudioSessionInterruption(.began)
        engine.suspendNextPlay()
        let resumeTask = Task {
            await controller.handleAudioSessionInterruption(
                .ended(systemAllowsResume: true)
            )
        }
        await engine.waitForPendingPlay()

        await controller.pause()
        engine.completePendingPlay()
        await resumeTask.value

        #expect(!engine.isPlaying)
        #expect(controller.snapshot.intent == .pause)
        await controller.shutdown()
    }

    @Test("An interruption resume from a replaced source cannot start the new source")
    func lateInterruptionResumeCannotStartReplacementSource() async throws {
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

        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        await controller.handleAudioSessionInterruption(.began)
        engine.suspendNextPlay()
        let resumeTask = Task {
            await controller.handleAudioSessionInterruption(
                .ended(systemAllowsResume: true)
            )
        }
        await engine.waitForPendingPlay()

        let replacementLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/replacement.m3u8")!)
        )
        await engine.waitForLoad(id: 2)
        engine.completeLoad(id: 2)
        try await replacementLoad.waitUntilReady()

        engine.completePendingPlay()
        await resumeTask.value

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .pause)
        #expect(!engine.isPlaying)
        await controller.shutdown()
    }

    @Test("Audio interruption does not resume when the system disallows it")
    func doesNotResumeWhenSystemDisallowsAudioInterruptionResume() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()
        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        await controller.handleAudioSessionInterruption(.began)
        await controller.handleAudioSessionInterruption(
            .ended(systemAllowsResume: false)
        )

        #expect(engine.playCallCount == 1)
        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .play)
        await controller.shutdown()
    }

    @Test("Audio interruption resumption can be disabled by configuration")
    func canDisableAutomaticAudioInterruptionResume() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(
                automaticallyResumesAfterAudioInterruption: false
            ),
            engine: engine
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()
        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        await controller.handleAudioSessionInterruption(.began)
        await controller.handleAudioSessionInterruption(
            .ended(systemAllowsResume: true)
        )

        #expect(engine.playCallCount == 1)
        #expect(controller.snapshot.phase == .paused)
        await controller.shutdown()
    }

    @Test("An interrupted autoplay load does not start when the system disallows resumption")
    func interruptedAutoplayRespectsSystemResumeDecision() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: true),
            engine: engine
        )
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)

        await controller.handleAudioSessionInterruption(.began)
        await controller.handleAudioSessionInterruption(
            .ended(systemAllowsResume: false)
        )
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()

        #expect(engine.playCallCount == 0)
        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .play)

        try await controller.play()
        #expect(engine.playCallCount == 1)
        await controller.shutdown()
    }

    @Test("An explicit pause during interruption cancels automatic resumption")
    func explicitPauseDuringInterruptionPreventsResume() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let handle = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await handle.waitUntilReady()
        try await controller.play()
        engine.emit(.playing, fromLoad: 1)
        engine.deliverQueuedEvents()
        await waitForPhase(.playing, controller: controller)

        await controller.handleAudioSessionInterruption(.began)
        await controller.pause()
        await controller.handleAudioSessionInterruption(
            .ended(systemAllowsResume: true)
        )

        #expect(engine.playCallCount == 1)
        #expect(controller.snapshot.phase == .paused)
        #expect(controller.snapshot.intent == .pause)
        await controller.shutdown()
    }
}
