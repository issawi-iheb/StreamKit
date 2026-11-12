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

    @Test("Client-side ad break prevents content playback from starting")
    func clientSideAdBreakPreventsContentPlayback() async throws {
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

        let adBreak = PlaybackAdBreakState(
            deliveryMode: .clientSide,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )

        controller.updateAdBreak(adBreak)

        try await controller.play()

        #expect(controller.snapshot.intent == .play)
        #expect(controller.snapshot.adBreak == adBreak)
        #expect(engine.playCallCount == 0)
        #expect(!engine.isPlaying)

        await controller.shutdown()
    }

    @Test("Client-side ad break preserves the selected playback rate")
    @MainActor
    func clientSideAdBreakRestrictsPlaybackRateChanges() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        try await controller.setPlaybackRate(1.5)

        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        let adBreak = PlaybackAdBreakState(
            deliveryMode: .clientSide,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )
        controller.updateAdBreak(adBreak)

        // The selected rate remains valid.
        try await controller.setPlaybackRate(1.5)
        #expect(engine.playbackRate == 1.5)

        // A different rate must be rejected.
        do {
            try await controller.setPlaybackRate(2.0)
            Issue.record("Expected playback-rate change to be rejected.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .adPlaybackRestricted)
        }

        #expect(engine.playbackRate == 1.5)

        await controller.shutdown()
    }

    @Test("Client-side ad break blocks forward seeks but allows backward seeks")
    @MainActor
    func clientSideAdBreakRestrictsForwardSeeking() async throws {
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

        controller.updateSnapshot(
            PlaybackSnapshot(
                phase: .ready,
                intent: .pause,
                currentTime: 30,
                duration: 300
            )
        )

        controller.updateAdBreak(
            PlaybackAdBreakState(
                deliveryMode: .clientSide,
                sequence: 1,
                restrictsForwardSeeking: true,
                requiresPreferredPlaybackRate: true
            )
        )

        // Forward seek must be rejected before reaching the engine.
        do {
            try await controller.seek(to: 60)
            Issue.record("Expected forward seek to be rejected.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .adPlaybackRestricted)
        }

        #expect(engine.seekTimes.isEmpty)

        // Backward seek remains available.
        let backwardSeek = Task {
            try await controller.seek(to: 10)
        }

        await engine.waitForSeek(id: 1)
        #expect(engine.seekTimes == [10])

        engine.completeSeek(id: 1)
        try await backwardSeek.value

        await controller.shutdown()
    }

    @Test("Client-side ad break blocks forward live-edge seeking")
    @MainActor
    func clientSideAdBreakRestrictsLiveEdgeSeeking() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let load = controller.load(
            MediaSource(
                url: URL(string: "https://example.com/live.m3u8")!,
                presentationKind: .live
            )
        )
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        controller.updateSnapshot(
            PlaybackSnapshot(
                phase: .ready,
                intent: .pause,
                currentTime: 100,
                timeline: PlaybackTimeline(
                    seekableRanges: [
                        PlaybackTimeRange(start: 50, end: 200)
                    ],
                    presentationKind: .live
                )
            )
        )

        controller.updateAdBreak(
            PlaybackAdBreakState(
                deliveryMode: .clientSide,
                sequence: 1,
                restrictsForwardSeeking: true,
                requiresPreferredPlaybackRate: true
            )
        )

        do {
            try await controller.seekToLiveEdge(offsetFromLive: 10)
            Issue.record("Expected forward live-edge seek to be rejected.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .adPlaybackRestricted)
        }

        #expect(engine.liveEdgeSeekOffsets.isEmpty)

        await controller.shutdown()
    }

    @Test("HLS interstitial does not block content engine playback")
    func hlsInterstitialAllowsContentEnginePlayback() async throws {
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

        let adBreak = PlaybackAdBreakState(
            deliveryMode: .hlsInterstitial,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )

        controller.updateAdBreak(adBreak)

        try await controller.play()

        #expect(controller.snapshot.adBreak == adBreak)
        #expect(engine.playCallCount == 1)
        #expect(engine.isPlaying)

        await controller.shutdown()
    }

    @Test("Autoplay does not start content while a client-side ad break is active")
    func autoplayWaitsWhileClientSideAdBreakIsActive() async throws {
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: true),
            engine: engine
        )

        let load = controller.load(
            MediaSource(url: URL(string: "https://example.com/video.m3u8")!)
        )

        // Wait until the content load is in flight.
        await engine.waitForLoad(id: 1)

        let adBreak = PlaybackAdBreakState(
            deliveryMode: .clientSide,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )

        // Simulate the ad coordinator activating a pre-roll break
        // before the content load completes.
        controller.updateAdBreak(adBreak)

        engine.completeLoad(id: 1)
        try await load.waitUntilReady()

        #expect(controller.snapshot.phase == .ready)
        #expect(controller.snapshot.intent == .play)
        #expect(controller.snapshot.adBreak == adBreak)
        #expect(engine.playCallCount == 0)
        #expect(!engine.isPlaying)

        await controller.shutdown()
    }

    @Test("Activating a client-side ad break interrupts an in-flight content play")
    func clientSideAdBreakInterruptsInFlightPlay() async throws {
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

        // Hold the engine's play operation before it completes.
        engine.suspendNextPlay()

        let playTask = Task {
            try await controller.play()
        }

        await engine.waitForPendingPlay()

        let adBreak = PlaybackAdBreakState(
            deliveryMode: .clientSide,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )

        // Activate the ad while content playback is still in flight.
        controller.updateAdBreak(adBreak)

        engine.completePendingPlay()
        try await playTask.value

        #expect(controller.snapshot.adBreak == adBreak)
        #expect(controller.snapshot.intent == .play)
        #expect(!engine.isPlaying)
        #expect(engine.pauseCallCount >= 1)

        await controller.shutdown()
    }

    @Test("Client-side ad break prevents playback after waiting for shared audio focus")
    func clientSideAdBreakWinsDuringAudioFocusAcquisition() async throws {
        let focusCoordinator = AudioPlaybackFocusCoordinator()

        let engineA = MockPlaybackEngine()
        let controllerA = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engineA,
            audioPlaybackFocusCoordinator: focusCoordinator
        )

        let engineB = MockPlaybackEngine()
        let controllerB = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engineB,
            audioPlaybackFocusCoordinator: focusCoordinator
        )

        // Load both players.
        let loadA = controllerA.load(
            MediaSource(url: URL(string: "https://example.com/player-a.m3u8")!)
        )
        await engineA.waitForLoad(id: 1)
        engineA.completeLoad(id: 1)
        try await loadA.waitUntilReady()

        let loadB = controllerB.load(
            MediaSource(url: URL(string: "https://example.com/player-b.m3u8")!)
        )
        await engineB.waitForLoad(id: 1)
        engineB.completeLoad(id: 1)
        try await loadB.waitUntilReady()

        // Player A acquires and owns shared audio focus.
        try await controllerA.play()

        #expect(engineA.isPlaying)
        #expect(engineA.playCallCount == 1)

        // Player B requests focus. Its request suspends while A is pausing.
        engineA.suspendNextPause()

        let playTask = Task {
            try await controllerB.play()
        }

        await engineA.waitForPendingPause()

        // The ad break starts while B is waiting for A to pause.
        let adBreak = PlaybackAdBreakState(
            deliveryMode: .clientSide,
            sequence: 1,
            restrictsForwardSeeking: true,
            requiresPreferredPlaybackRate: true
        )

        controllerB.updateAdBreak(adBreak)

        // Allow A's pause to complete, so B can finish acquiring focus.
        engineA.completePendingPause()

        try await playTask.value

        #expect(!engineA.isPlaying)
        #expect(controllerB.snapshot.intent == .play)
        #expect(controllerB.snapshot.adBreak == adBreak)
        #expect(engineB.playCallCount == 0)
        #expect(!engineB.isPlaying)

        await controllerA.shutdown()
        await controllerB.shutdown()
    }

}
