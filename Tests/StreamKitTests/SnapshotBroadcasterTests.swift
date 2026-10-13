//
//  SnapshotBroadcasterTests.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation
import Testing
@testable import StreamKit

@Suite("SnapshotBroadcaster")
@MainActor
struct SnapshotBroadcasterTests {

    @Test("New subscriber receives initial snapshot")
    func newSubscriberReceivesInitialSnapshot() async {
        let broadcaster = SnapshotBroadcaster()

        let initialSnapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        let stream = broadcaster.makeStream(
            initialSnapshot: initialSnapshot
        )

        var iterator = stream.makeAsyncIterator()

        let receivedSnapshot = await iterator.next()

        #expect(receivedSnapshot == initialSnapshot)
    }

    @Test("Subscriber receives published snapshots")
    func subscriberReceivesPublishedSnapshots() async {
        let broadcaster = SnapshotBroadcaster()

        let initialSnapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        let updatedSnapshot = PlaybackSnapshot(
            phase: .ready,
            intent: .pause,
            currentTime: 0,
            duration: 120
        )

        let stream = broadcaster.makeStream(
            initialSnapshot: initialSnapshot
        )

        var iterator = stream.makeAsyncIterator()

        let receivedInitialSnapshot = await iterator.next()

        #expect(receivedInitialSnapshot == initialSnapshot)

        broadcaster.publish(updatedSnapshot)

        let receivedUpdatedSnapshot = await iterator.next()

        #expect(receivedUpdatedSnapshot == updatedSnapshot)
    }

    @Test("Multiple subscribers receive published snapshots")
    func multipleSubscribersReceiveSnapshots() async {
        let broadcaster = SnapshotBroadcaster()

        let initialSnapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        let updatedSnapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 10,
            duration: 120
        )

        let firstStream = broadcaster.makeStream(
            initialSnapshot: initialSnapshot
        )

        let secondStream = broadcaster.makeStream(
            initialSnapshot: initialSnapshot
        )

        var firstIterator = firstStream.makeAsyncIterator()
        var secondIterator = secondStream.makeAsyncIterator()

        #expect(await firstIterator.next() == initialSnapshot)
        #expect(await secondIterator.next() == initialSnapshot)

        broadcaster.publish(updatedSnapshot)

        #expect(await firstIterator.next() == updatedSnapshot)
        #expect(await secondIterator.next() == updatedSnapshot)
    }

    @Test("Finished broadcaster terminates new streams")
    func finishedBroadcasterTerminatesNewStreams() async {
        let broadcaster = SnapshotBroadcaster()

        let finalSnapshot = PlaybackSnapshot(
            phase: .idle,
            intent: .pause
        )

        broadcaster.finish(with: finalSnapshot)

        let stream = broadcaster.makeStream(
            initialSnapshot: finalSnapshot
        )

        var iterator = stream.makeAsyncIterator()

        #expect(await iterator.next() == finalSnapshot)
        #expect(await iterator.next() == nil)
    }
}
