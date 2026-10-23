import Foundation
import Testing
@testable import StreamKit

@Suite("Playback event reducer")
struct PlaybackEventReducerTests {

    @Test("Playing event is ignored when playback intent is pause")
    func ignoresPlayingWhenIntentIsPause() {
        let snapshot = PlaybackSnapshot(phase: .paused, intent: .pause)

        #expect(PlaybackEventReducer.reduce(.playing, from: snapshot) == nil)
    }

    @Test("Paused event is ignored while loading")
    func ignoresPausedWhileLoading() {
        let snapshot = PlaybackSnapshot(phase: .loading, intent: .play)

        #expect(PlaybackEventReducer.reduce(.paused, from: snapshot) == nil)
    }

    @Test("Time updates preserve playback intent and update timeline")
    func appliesTimeAndTimeline() {
        let originalTimeline = PlaybackTimeline(
            seekableRanges: [.init(start: 20, end: 40)]
        )
        let updatedTimeline = PlaybackTimeline(
            seekableRanges: [.init(start: 25, end: 45)],
            currentDate: Date(timeIntervalSince1970: 100)
        )
        let snapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 5,
            duration: nil,
            timeline: originalTimeline
        )

        let updated = PlaybackEventReducer.reduce(
            .timeUpdated(currentTime: 12, duration: nil, timeline: updatedTimeline),
            from: snapshot
        )

        #expect(updated?.phase == .playing)
        #expect(updated?.intent == .play)
        #expect(updated?.currentTime == 12)
        #expect(updated?.timeline == updatedTimeline)
    }

    @Test("Paused timeline updates preserve playback time and phase")
    func appliesTimelineOnlyUpdate() {
        let timeline = PlaybackTimeline(
            seekableRanges: [.init(start: 90, end: 150)],
            presentationKind: .live
        )
        let snapshot = PlaybackSnapshot(
            phase: .paused,
            intent: .pause,
            currentTime: 123,
            duration: nil
        )

        let updated = PlaybackEventReducer.reduce(.timelineUpdated(timeline), from: snapshot)

        #expect(updated?.phase == .paused)
        #expect(updated?.intent == .pause)
        #expect(updated?.currentTime == 123)
        #expect(updated?.duration == nil)
        #expect(updated?.timeline == timeline)
    }

    @Test("End event pauses intent and preserves the sampled timeline")
    func endEventPreservesTimeline() {
        let timeline = PlaybackTimeline(
            seekableRanges: [.init(start: 0, end: 60)]
        )
        let snapshot = PlaybackSnapshot(
            phase: .playing,
            intent: .play,
            currentTime: 60,
            duration: 60,
            timeline: timeline
        )

        let ended = PlaybackEventReducer.reduce(.ended, from: snapshot)

        #expect(ended?.phase == .ended)
        #expect(ended?.intent == .pause)
        #expect(ended?.timeline == timeline)
    }
}
