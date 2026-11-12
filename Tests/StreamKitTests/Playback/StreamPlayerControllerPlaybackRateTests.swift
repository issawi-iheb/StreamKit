// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController playback rate")
@MainActor
struct StreamPlayerControllerPlaybackRateTests {

    @Test("Playback rate is forwarded to the engine")
    func playbackRateIsForwardedToEngine() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        try await controller.setPlaybackRate(1.5)

        #expect(engine.playbackRate == 1.5)
        #expect(controller.snapshot.phase == .idle)
        #expect(controller.snapshot.intent == .pause)

        await controller.shutdown()
    }

    @Test("Playback rate can be set before loading a source")
    func playbackRateCanBeSetBeforeLoading() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        try await controller.setPlaybackRate(2.0)

        #expect(engine.playbackRate == 2.0)
        #expect(controller.snapshot.phase == .idle)

        await controller.shutdown()
    }

    @Test("Invalid playback rates are rejected")
    func invalidPlaybackRatesAreRejected() async {
        let invalidRates: [Float] = [
            0,
            -1,
            .nan,
            .infinity,
            -.infinity,
            32.01,
            .greatestFiniteMagnitude
        ]

        for rate in invalidRates {
            let engine = MockPlaybackEngine()
            let controller = StreamPlayerController(
                configuration: PlayerConfiguration(autoplay: false),
                engine: engine
            )

            do {
                try await controller.setPlaybackRate(rate)
                Issue.record("Expected playback rate \(rate) to be rejected")
            } catch let failure as PlaybackFailure {
                #expect(failure.code == .invalidPlaybackRate)
            } catch {
                Issue.record("Unexpected error for playback rate \(rate): \(error)")
            }

            #expect(engine.playbackRate == 1.0)

            await controller.shutdown()
        }
    }

    @Test("Changing playback rate does not change playback state")
    func changingPlaybackRatePreservesSnapshot() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let initialSnapshot = controller.snapshot

        try await controller.setPlaybackRate(0.5)

        #expect(controller.snapshot == initialSnapshot)
        #expect(engine.playbackRate == 0.5)

        await controller.shutdown()
    }

    @Test("Playback rate changes after shutdown are rejected")
    func playbackRateAfterShutdownIsRejected() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        await controller.shutdown()

        do {
            try await controller.setPlaybackRate(1.5)
            Issue.record("Expected playback-rate change to fail after shutdown")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .playback)
        } catch {
            Issue.record("Unexpected error after shutdown: \(error)")
        }
    }

    @Test("Independent controllers maintain independent playback rates")
    func independentControllersMaintainPlaybackRates() async throws {
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

        try await controller1.setPlaybackRate(0.5)
        try await controller2.setPlaybackRate(2.0)

        #expect(engine1.playbackRate == 0.5)
        #expect(engine2.playbackRate == 2.0)

        await controller1.shutdown()

        #expect(engine2.playbackRate == 2.0)

        await controller2.shutdown()
    }

    @Test("Playback rate persists across source replacements")
    func playbackRatePersistsAcrossSourceReplacements() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)

        try await controller.setPlaybackRate(1.5)

        _ = controller.load(
            MediaSource(url: URL(string: "https://example.com/first.m3u8")!)
        )

        _ = controller.load(
            MediaSource(url: URL(string: "https://example.com/second.m3u8")!)
        )

        #expect(engine.playbackRate == 1.5)
        #expect(controller.snapshot.intent == .pause)

        await controller.shutdown()
    }

    @Test("Setting playback rate does not start playback")
    func settingPlaybackRateDoesNotStartPlayback() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)

        try await controller.setPlaybackRate(2.0)

        #expect(engine.playbackRate == 2.0)
        #expect(controller.snapshot.phase == .idle)
        #expect(controller.snapshot.intent == .pause)

        await controller.shutdown()
    }
}
