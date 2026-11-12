//
//  PlaybackPhaseTests.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Testing
@testable import StreamKit

@Suite("PlaybackPhase")
struct PlaybackPhaseTests {

    @Test("All playback phases are distinct")
    func playbackPhasesAreDistinct() {
        let phases: [PlaybackPhase] = [
            .idle,
            .loading,
            .ready,
            .playing,
            .paused,
            .waiting,
            .ended,
            .failed
        ]

        #expect(Set(phases).count == phases.count)
    }
}

@Suite("PlaybackIntent")
struct PlaybackIntentTests {

    @Test("Play and pause are distinct intents")
    func playAndPauseAreDistinct() {
        #expect(PlaybackIntent.play != PlaybackIntent.pause)
    }
}

@Suite("Playback State Model")
struct PlaybackStateModelTests {

    @Test("Playback phase and intent can represent different concepts")
    func phaseAndIntentAreIndependent() {
        let snapshot = PlaybackSnapshot(
            phase: .ready,
            intent: .play
        )

        #expect(snapshot.phase == .ready)
        #expect(snapshot.intent == .play)
    }
}
