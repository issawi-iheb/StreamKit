import Foundation
import Testing
@testable import StreamKit

@Suite("Playback interstitial seek policy")
struct PlaybackInterstitialSeekPolicyTests {

    @Test("Active break blocks forward seeks but allows backward seeks")
    func activeBreakRestrictionAppliesOnlyToForwardSeeks() {
        #expect(PlaybackInterstitialSeekPolicy.activeBreakRestrictsForwardSeek(
            from: 10,
            to: 11,
            restrictsForwardSeeking: true
        ))
        #expect(!PlaybackInterstitialSeekPolicy.activeBreakRestrictsForwardSeek(
            from: 10,
            to: 9,
            restrictsForwardSeeking: true
        ))
        #expect(!PlaybackInterstitialSeekPolicy.activeBreakRestrictsForwardSeek(
            from: 10,
            to: 11,
            restrictsForwardSeeking: false
        ))
    }

    @Test("Rejects a forward seek that crosses a restricted scheduled break")
    func rejectsForwardSeekAcrossRestrictedBreak() {
        let restrictions = [PlaybackInterstitialSeekRestriction(time: 10, date: nil)]

        #expect(PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: 2,
            to: 15,
            currentDate: nil,
            targetDate: nil,
            scheduledRestrictions: restrictions
        ))
    }

    @Test("Allows a backward seek and a seek ending at the break")
    func allowsSeekThatDoesNotCrossBreak() {
        let restrictions = [PlaybackInterstitialSeekRestriction(time: 10, date: nil)]

        #expect(!PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: 15,
            to: 2,
            currentDate: nil,
            targetDate: nil,
            scheduledRestrictions: restrictions
        ))
        #expect(!PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: 2,
            to: 10,
            currentDate: nil,
            targetDate: nil,
            scheduledRestrictions: restrictions
        ))
    }

    @Test("Rejects a seek across a date-scheduled break")
    func rejectsSeekAcrossDateScheduledBreak() {
        let start = Date(timeIntervalSince1970: 1_000)
        let restrictions = [PlaybackInterstitialSeekRestriction(
            time: nil,
            date: start.addingTimeInterval(10)
        )]

        #expect(PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: 2,
            to: 15,
            currentDate: start,
            targetDate: start.addingTimeInterval(13),
            scheduledRestrictions: restrictions
        ))
    }

    @Test("Includes a break at the current position but excludes one at the target")
    func respectsHalfOpenSeekInterval() {
        let atCurrent = [PlaybackInterstitialSeekRestriction(time: 10, date: nil)]
        let atTarget = [PlaybackInterstitialSeekRestriction(time: 15, date: nil)]

        #expect(PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: 10,
            to: 20,
            currentDate: nil,
            targetDate: nil,
            scheduledRestrictions: atCurrent
        ))
        #expect(!PlaybackInterstitialSeekPolicy.crossesRestrictedInterstitial(
            from: 10,
            to: 15,
            currentDate: nil,
            targetDate: nil,
            scheduledRestrictions: atTarget
        ))
    }
}

@Suite("Playback ad-break state")
@MainActor
struct PlaybackAdBreakTests {

    @Test("Snapshot defaults to no active ad break and includes it in equality")
    func snapshotTracksActiveAdBreak() {
        let plain = PlaybackSnapshot(phase: .playing, intent: .play)
        let adBreak = PlaybackAdBreakState(
            deliveryMode: .hlsInterstitial,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: false
        )
        let playingAd = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            adBreak: adBreak
        )

        #expect(plain.adBreak == nil)
        #expect(playingAd.adBreak == adBreak)
        #expect(plain != playingAd)
    }

    @Test("Publishes begin and end diagnostics for an interstitial")
    func publishesAdBreakLifecycleDiagnostics() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/interstitials.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        var diagnostics = controller.diagnosticEvents.makeAsyncIterator()
        #expect((await diagnostics.next())?.kind == .loadStarted)
        #expect((await diagnostics.next())?.kind == .ready)

        var snapshots = controller.snapshots.makeAsyncIterator()
        _ = await snapshots.next()

        let state = PlaybackAdBreakState(
            deliveryMode: .hlsInterstitial,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )
        engine.emit(.adBreakChanged(state), fromLoad: 1)
        engine.deliverQueuedEvents()

        #expect((await snapshots.next())?.adBreak == state)
        #expect((await diagnostics.next())?.kind == .adBreakBegan(.hlsInterstitial))

        // Identical duplicate events must not create additional lifecycle edges.
        engine.emit(.adBreakChanged(state), fromLoad: 1)
        engine.deliverQueuedEvents()

        let nextState = PlaybackAdBreakState(
            deliveryMode: .hlsInterstitial,
            sequence: 2,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )
        engine.emit(.adBreakChanged(nextState), fromLoad: 1)
        engine.deliverQueuedEvents()
        #expect((await snapshots.next())?.adBreak == nextState)
        #expect((await diagnostics.next())?.kind == .adBreakEnded(.hlsInterstitial))
        #expect((await diagnostics.next())?.kind == .adBreakBegan(.hlsInterstitial))

        engine.emit(.adBreakChanged(nil), fromLoad: 1)
        engine.deliverQueuedEvents()

        #expect((await snapshots.next())?.adBreak == nil)
        #expect((await diagnostics.next())?.kind == .adBreakEnded(.hlsInterstitial))
        await controller.shutdown()
    }

    @Test("Preserves active state on time updates and interrupts it on source replacement")
    func preservesStateAndReportsInterruptionOnReplacement() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(engine: engine)
        let firstLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/first.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await firstLoad.waitUntilReady()

        var diagnostics = controller.diagnosticEvents.makeAsyncIterator()
        _ = await diagnostics.next()
        _ = await diagnostics.next()
        var snapshots = controller.snapshots.makeAsyncIterator()
        _ = await snapshots.next()

        let state = PlaybackAdBreakState(
            deliveryMode: .hlsInterstitial,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: false
        )
        engine.emit(.adBreakChanged(state), fromLoad: 1)
        engine.deliverQueuedEvents()
        #expect((await snapshots.next())?.adBreak == state)
        #expect((await diagnostics.next())?.kind == .adBreakBegan(.hlsInterstitial))

        engine.emit(
            .timeUpdated(currentTime: 5, duration: 30, timeline: .init()),
            fromLoad: 1
        )
        engine.deliverQueuedEvents()
        let timedSnapshot = await snapshots.next()
        #expect(timedSnapshot?.currentTime == 5)
        #expect(timedSnapshot?.adBreak == state)

        let secondLoad = controller.load(
            MediaSource(url: URL(string: "https://example.com/second.m3u8")!)
        )
        await engine.waitForLoad(id: 2)
        #expect(controller.snapshot.phase == .loading)
        #expect(controller.snapshot.adBreak == nil)
        let interruption = await diagnostics.next()
        #expect(interruption?.kind == .adBreakInterrupted(.hlsInterstitial))
        #expect(interruption?.loadGeneration == 1)

        var metrics = controller.metrics.makeAsyncIterator()
        engine.emit(.adBreakChanged(state), fromLoad: 1)
        engine.emit(.metric(date: .now, kind: .stall), fromLoad: 2)
        engine.deliverQueuedEvents()
        _ = await metrics.next()
        #expect(controller.snapshot.adBreak == nil)

        await controller.shutdown()
        do {
            try await secondLoad.waitUntilReady()
            Issue.record("The pending replacement load unexpectedly succeeded.")
        } catch is CancellationError {
            // Expected: shutdown cancels the pending replacement load.
        }
    }

    @Test("Preferred-rate restriction rejects rate changes during a break")
    func rejectsPreferredRateChangeDuringBreak() async {
        let engine = AVFoundationPlaybackEngine()
        engine.activeAdBreakState = PlaybackAdBreakState(
            deliveryMode: .hlsInterstitial,
            sequence: 1,
            restrictsForwardSeeking: false,
            requiresPreferredPlaybackRate: true
        )

        do {
            try await engine.setPlaybackRate(1.5)
            Issue.record("Expected playback-rate change to be rejected during the break.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .adPlaybackRestricted)
        } catch {
            Issue.record("Unexpected failure: \(error)")
        }

        do {
            try await engine.setPlaybackRate(1.0)
        } catch {
            Issue.record("The preferred playback rate should remain allowed: \(error)")
        }

        await engine.shutdown()
    }
}
