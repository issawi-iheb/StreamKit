import Foundation
import Testing
@testable import StreamKit

@Suite("PlaybackDiagnosticsBroadcaster")
@MainActor
struct PlaybackDiagnosticsBroadcasterTests {
    @Test("Late subscribers receive retained events in sequence")
    func replaysBoundedHistoryInOrder() async {
        let broadcaster = PlaybackDiagnosticsBroadcaster(historyLimit: 2)
        broadcaster.publish(kind: .loadStarted, loadGeneration: 1)
        broadcaster.publish(kind: .ready, loadGeneration: 1)
        broadcaster.publish(kind: .ended, loadGeneration: 1)

        var iterator = broadcaster.makeStream().makeAsyncIterator()

        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first?.kind == .ready)
        #expect(second?.kind == .ended)
        #expect(first?.sequence == 2)
        #expect(second?.sequence == 3)
    }

    @Test("Independent subscribers receive the same events")
    func broadcastsToIndependentSubscribers() async {
        let broadcaster = PlaybackDiagnosticsBroadcaster()
        var first = broadcaster.makeStream().makeAsyncIterator()
        var second = broadcaster.makeStream().makeAsyncIterator()

        let event = broadcaster.publish(kind: .loadStarted, loadGeneration: 7)

        #expect(await first.next() == event)
        #expect(await second.next() == event)
    }

    @Test("Finish terminates active and future streams after retained history")
    func finishTerminatesStreams() async {
        let broadcaster = PlaybackDiagnosticsBroadcaster()
        broadcaster.publish(kind: .loadStarted, loadGeneration: 2)
        let activeStream = broadcaster.makeStream()
        broadcaster.finish()

        var active = activeStream.makeAsyncIterator()
        #expect((await active.next())?.kind == .loadStarted)
        #expect(await active.next() == nil)

        var later = broadcaster.makeStream().makeAsyncIterator()
        #expect((await later.next())?.kind == .loadStarted)
        #expect(await later.next() == nil)
    }

    @Test("Slow subscriber can detect dropped events by sequence gap")
    func droppedSubscriberEventsLeaveSequenceGap() async {
        let broadcaster = PlaybackDiagnosticsBroadcaster(
            historyLimit: 4,
            subscriberBufferLimit: 2
        )
        var iterator = broadcaster.makeStream().makeAsyncIterator()

        broadcaster.publish(kind: .loadStarted, loadGeneration: 1)
        broadcaster.publish(kind: .ready, loadGeneration: 1)
        broadcaster.publish(kind: .ended, loadGeneration: 1)

        let firstDelivered = await iterator.next()
        let secondDelivered = await iterator.next()
        #expect(firstDelivered?.sequence == 2)
        #expect(secondDelivered?.sequence == 3)
    }
}
