//
//  AVFoundationPlaybackEngineTests.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

import AVFoundation
import Foundation
import Testing
@testable import StreamKit

@Suite("AVFoundation Playback Engine")
@MainActor
struct AVFoundationPlaybackEngineTests {

    @Test("Play after shutdown throws a playback failure")
    func playAfterShutdownThrows() async {
        let engine = AVFoundationPlaybackEngine()

        await engine.shutdown()

        do {
            try await engine.play()
            Issue.record("Expected play() to throw after shutdown.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .playback)
            #expect(
                failure.message == "The playback engine has been shut down."
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Seek after shutdown throws a playback failure")
    func seekAfterShutdownThrows() async {
        let engine = AVFoundationPlaybackEngine()

        await engine.shutdown()

        do {
            try await engine.seek(to: 10)
            Issue.record("Expected seek() to throw after shutdown.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .playback)
            #expect(
                failure.message == "The playback engine has been shut down."
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Shutdown finishes the event stream")
    func shutdownFinishesEventStream() async {
        let engine = AVFoundationPlaybackEngine()
        let events = engine.events

        await engine.shutdown()

        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()

        #expect(event == nil)
    }

    @Test("Play without a loaded source throws an invalid source failure")
    func playWithoutLoadedSourceThrows() async {
        let engine = AVFoundationPlaybackEngine()

        do {
            try await engine.play()
            Issue.record("Expected play() to throw without a loaded source.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .invalidSource)
            #expect(failure.message == "Load a media source before playing.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await engine.shutdown()
    }

    @Test("Seek without a loaded source throws an invalid source failure")
    func seekWithoutLoadedSourceThrows() async {
        let engine = AVFoundationPlaybackEngine()

        do {
            try await engine.seek(to: 10)
            Issue.record("Expected seek() to throw without a loaded source.")
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .invalidSource)
            #expect(failure.message == "Load a media source before seeking.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await engine.shutdown()
    }

    @Test("Engine instances own independent players")
    func engineInstancesOwnIndependentPlayers() async {
        let engine1 = AVFoundationPlaybackEngine()
        let engine2 = AVFoundationPlaybackEngine()

        #expect(engine1.renderingPlayer !== engine2.renderingPlayer)

        await engine1.shutdown()

        // Shutting down engine1 must not affect engine2.
        #expect(engine2.renderingPlayer.currentItem == nil)

        // The second engine should still accept playback commands.
        do {
            try await engine2.play()
        } catch let failure as PlaybackFailure {
            #expect(failure.code == .invalidSource)
            #expect(failure.message == "Load a media source before playing.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await engine2.shutdown()
    }
}
