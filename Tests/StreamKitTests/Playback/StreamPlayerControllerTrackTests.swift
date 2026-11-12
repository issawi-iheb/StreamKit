// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController track selection")
@MainActor
struct StreamPlayerControllerTrackTests {

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

    @Test("Cancelled audio-track discovery does not return loaded results")
    func cancelledAudioTrackDiscoveryThrowsCancellation() async throws {
        let engine = MockPlaybackEngine()
        engine.audioTracks = [
            MediaTrack(
                id: "audio:0",
                type: .audio,
                name: "English",
                languageCode: nil
            )
        ]
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

        engine.suspendNextAudioTrackQuery()
        let queryTask = Task {
            try await controller.availableAudioTracks()
        }
        await engine.waitForPendingAudioTrackQuery()
        queryTask.cancel()
        engine.completePendingAudioTrackQuery()

        do {
            _ = try await queryTask.value
            Issue.record("The cancelled track query unexpectedly returned results.")
        } catch is CancellationError {
            // Expected: cancellation is checked after the async engine call.
        }

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
}
