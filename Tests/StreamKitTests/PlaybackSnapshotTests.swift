//
//  PlaybackSnapshotTests.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Testing
@testable import StreamKit

@Suite("PlaybackSnapshot")
struct PlaybackSnapshotTests {

    @Test("Preserves phase and intent")
    func initializationPreservesPhaseAndIntent() {
        let snapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play
        )

        #expect(snapshot.phase == .playing)
        #expect(snapshot.intent == .play)
    }

    @Test("Uses default timing values")
    func defaultTimingValues() {
        let snapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        #expect(snapshot.currentTime == 0)
        #expect(snapshot.duration == nil)
    }

    @Test("Preserves playback timing")
    func initializationPreservesPlaybackTiming() {
        let snapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 42.5,
            duration: 180
        )

        #expect(snapshot.currentTime == 42.5)
        #expect(snapshot.duration == 180)
    }

    @Test("Supports unknown duration")
    func supportsUnknownDuration() {
        let snapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 10,
            duration: nil
        )

        #expect(snapshot.duration == nil)
    }

    @Test("Identical snapshots are equal")
    func identicalSnapshotsAreEqual() {
        let first = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 42,
            duration: 180
        )

        let second = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 42,
            duration: 180
        )

        #expect(first == second)
    }

    @Test("Different phases produce unequal snapshots")
    func differentPhasesProduceUnequalSnapshots() {
        let first = PlaybackSnapshot(
            phase: .playing,
            intent: .play
        )

        let second = PlaybackSnapshot(
            phase: .paused,
            intent: .play
        )

        #expect(first != second)
    }

    @Test("Different intents produce unequal snapshots")
    func differentIntentsProduceUnequalSnapshots() {
        let first = PlaybackSnapshot(
            phase: .paused,
            intent: .pause
        )

        let second = PlaybackSnapshot(
            phase: .paused,
            intent: .play
        )

        #expect(first != second)
    }

    @Test("Different timing produces unequal snapshots")
    func differentTimingProducesUnequalSnapshots() {
        let first = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 10,
            duration: 180
        )

        let second = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 20,
            duration: 200
        )

        #expect(first != second)
    }

    @Test("Failure defaults to nil")
    func failureDefaultsToNil() {
        let snapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play
        )

        #expect(snapshot.failure == nil)
    }

    @Test("Failed snapshot exposes its failure")
    func failedSnapshotExposesFailure() {
        let failure = PlaybackFailure(
            code: .network,
            message: "The connection was lost."
        )

        let snapshot = PlaybackSnapshot(
            phase: .failed,
            intent: .play,
            failure: failure
        )

        #expect(snapshot.phase == .failed)
        #expect(snapshot.failure == failure)
        #expect(snapshot.failure?.code == .network)
        #expect(snapshot.failure?.message == "The connection was lost.")
    }

    @Test("Snapshots with different failures are unequal")
    func snapshotsWithDifferentFailuresAreUnequal() {
        let networkFailure = PlaybackFailure(
            code: .network,
            message: "Connection lost."
        )

        let playbackFailure = PlaybackFailure(
            code: .playback,
            message: "Playback failed."
        )

        let first = PlaybackSnapshot(
            phase: .failed,
            intent: .play,
            failure: networkFailure
        )

        let second = PlaybackSnapshot(
            phase: .failed,
            intent: .play,
            failure: playbackFailure
        )

        #expect(first != second)
    }
}
