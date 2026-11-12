import Foundation
import Testing
@testable import StreamKit

@Suite("PlaybackMetricsBroadcaster")
@MainActor
struct PlaybackMetricsBroadcasterTests {
    @Test("Late subscribers receive bounded metric history in sequence")
    func replaysBoundedHistoryInOrder() async {
        let broadcaster = PlaybackMetricsBroadcaster(historyLimit: 2)
        let metric = PlaybackMetricEvent.Kind.stall
        broadcaster.publish(timestamp: .now, loadGeneration: 1, kind: metric)
        broadcaster.publish(timestamp: .now, loadGeneration: 1, kind: metric)
        broadcaster.publish(timestamp: .now, loadGeneration: 2, kind: metric)

        var iterator = broadcaster.makeStream().makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.sequence == 2)
        #expect(second?.sequence == 3)
        #expect(first?.loadGeneration == 1)
        #expect(second?.loadGeneration == 2)
    }

    @Test("Independent subscribers receive the same metric event")
    func broadcastsToIndependentSubscribers() async {
        let broadcaster = PlaybackMetricsBroadcaster()
        var first = broadcaster.makeStream().makeAsyncIterator()
        var second = broadcaster.makeStream().makeAsyncIterator()

        broadcaster.publish(timestamp: .now, loadGeneration: 4, kind: .stall)

        let firstEvent = await first.next()
        let secondEvent = await second.next()
        #expect(firstEvent == secondEvent)
        #expect(firstEvent?.sequence == 1)
    }

    @Test("Slow subscribers can detect dropped metric events")
    func droppedEventsLeaveSequenceGap() async {
        let broadcaster = PlaybackMetricsBroadcaster(
            historyLimit: 4,
            subscriberBufferLimit: 2
        )
        var iterator = broadcaster.makeStream().makeAsyncIterator()

        for _ in 0..<3 {
            broadcaster.publish(timestamp: .now, loadGeneration: 1, kind: .stall)
        }

        #expect(await iterator.next()?.sequence == 2)
        #expect(await iterator.next()?.sequence == 3)
    }

    @Test("Finished stream replays history then terminates")
    func finishedStreamTerminates() async {
        let broadcaster = PlaybackMetricsBroadcaster()
        broadcaster.publish(timestamp: .now, loadGeneration: 8, kind: .stall)
        let active = broadcaster.makeStream()
        broadcaster.finish()

        var iterator = active.makeAsyncIterator()
        #expect(await iterator.next()?.loadGeneration == 8)
        #expect(await iterator.next() == nil)
        var later = broadcaster.makeStream().makeAsyncIterator()
        #expect(await later.next()?.sequence == 1)
        #expect(await later.next() == nil)
    }
}
