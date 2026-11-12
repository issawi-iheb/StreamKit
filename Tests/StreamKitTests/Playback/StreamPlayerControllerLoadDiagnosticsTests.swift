// Controller tests grouped by public behavior.

import Foundation
import Testing
@testable import StreamKit

@Suite("StreamPlayerController load and diagnostics")
@MainActor
struct StreamPlayerControllerLoadDiagnosticsTests {

    @Test("Declared live presentation kind is visible during loading")
    func exposesLivePresentationKindDuringLoading() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        _ = controller.load(
            MediaSource(
                url: URL(string: "https://example.com/live.m3u8")!,
                presentationKind: .live
            )
        )

        #expect(controller.snapshot.phase == .loading)
        #expect(controller.snapshot.timeline.presentationKind == .live)

        await controller.shutdown()
    }

    @Test("Late diagnostic subscriber receives load start and readiness")
    func lateDiagnosticSubscriberReceivesStartupEvents() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )

        // Loading starts synchronously, before a managed-session caller can
        // request the diagnostic stream.
        var events = controller.diagnosticEvents.makeAsyncIterator()
        let started = await events.next()
        #expect(started?.kind == .loadStarted)
        #expect(started?.loadGeneration == 1)

        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        #expect((await events.next())?.kind == .ready)
        await controller.shutdown()
    }

    @Test("AVFoundation metrics are forwarded without changing playback state")
    func forwardsMetricsWithoutChangingSnapshot() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        var metrics = controller.metrics.makeAsyncIterator()
        engine.emit(.metric(date: .now, kind: .stall), fromLoad: 1)
        engine.deliverQueuedEvents()

        let metric = await metrics.next()
        #expect(metric?.kind == .stall)
        #expect(metric?.loadGeneration == 1)
        #expect(controller.snapshot.phase == .ready)
        await controller.shutdown()
    }

    @Test("Explicit load cancellation is a diagnostic outcome")
    func explicitLoadCancellationIsReported() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/private.m3u8?token=secret")!)
        )
        await engine.waitForLoad(id: 1)
        var events = controller.diagnosticEvents.makeAsyncIterator()

        load.cancel()
        do {
            try await load.waitUntilReady()
            Issue.record("Expected the load to be cancelled.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }

        let started = await events.next()
        let cancelled = await events.next()
        #expect(started?.kind == .loadStarted)
        #expect(cancelled?.kind == .loadCancelled(.requested))
        await controller.shutdown()
    }

    @Test("Replacing a loading source reports cancellation against old generation")
    func replacingLoadingSourceReportsCancellation() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        _ = controller.load(
            MediaSource(url: URL(string: "https://example.com/first.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        let stream = controller.diagnosticEvents
        var events = stream.makeAsyncIterator()

        _ = controller.load(
            MediaSource(url: URL(string: "https://example.com/second.m3u8")!)
        )

        let started = await events.next()
        let replaced = await events.next()
        let replacementStarted = await events.next()
        #expect(started?.kind == .loadStarted)
        #expect(replaced?.kind == .loadCancelled(.replacedByNewSource))
        #expect(replaced?.loadGeneration == 1)
        #expect(replacementStarted?.kind == .loadStarted)
        #expect(replacementStarted?.loadGeneration == 2)

        await controller.shutdown()
    }

    @Test("Failed load publishes only normalized failure category")
    func failedLoadPublishesNormalizedFailure() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8?token=secret")!)
        )
        await engine.waitForLoad(id: 1)
        var events = controller.diagnosticEvents.makeAsyncIterator()
        engine.failLoad(
            id: 1,
            with: PlaybackFailure(code: .network, message: "private response text")
        )

        do {
            try await load.waitUntilReady()
            Issue.record("Expected the load to fail.")
        } catch {
            // The public diagnostic event intentionally carries only its code.
        }

        #expect((await events.next())?.kind == .loadStarted)
        #expect((await events.next())?.kind == .playbackFailed(.network))
        await controller.shutdown()
    }

    @Test("Shutdown reports active-load cancellation and finishes diagnostics")
    func shutdownFinishesDiagnosticStream() async {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        _ = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        var events = controller.diagnosticEvents.makeAsyncIterator()

        await controller.shutdown()

        #expect((await events.next())?.kind == .loadStarted)
        #expect((await events.next())?.kind == .loadCancelled(.shutdown))
        #expect(await events.next() == nil)
    }
}
