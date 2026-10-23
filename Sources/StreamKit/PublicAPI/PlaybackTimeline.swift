import Foundation

/// A time range in a media presentation that can be used for seeking.
public struct PlaybackTimeRange: Equatable, Sendable {

    /// The inclusive start of the range, in seconds on the player timeline.
    public let start: TimeInterval

    /// The exclusive end of the range, in seconds on the player timeline.
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    /// Whether a time falls inside this half-open range.
    public func contains(_ time: TimeInterval) -> Bool {
        guard start.isFinite, end.isFinite, end >= start, time.isFinite else {
            return false
        }

        return time >= start && time < end
    }
}

/// Timeline metadata reported by the active media item.
///
/// Seekable ranges may be discontinuous. `currentDate` is available only when
/// the media timeline maps playback time to wall-clock time.
public struct PlaybackTimeline: Equatable, Sendable {

    /// The presentation classification supplied when loading the source.
    public let presentationKind: MediaPresentationKind

    /// The media time ranges that AVFoundation currently reports as seekable.
    public let seekableRanges: [PlaybackTimeRange]

    /// The wall-clock date corresponding to the sampled playback position, if known.
    public let currentDate: Date?

    /// The end of the newest seekable range for an explicitly live source.
    /// This is a seekable-window boundary, not a promise of zero latency.
    public var latestSeekableTime: TimeInterval? {
        guard presentationKind == .live else { return nil }
        return seekableRanges.map(\.end).filter(\.isFinite).max()
    }

    public init(
        seekableRanges: [PlaybackTimeRange] = [],
        currentDate: Date? = nil,
        presentationKind: MediaPresentationKind = .unspecified
    ) {
        self.seekableRanges = seekableRanges
        self.currentDate = currentDate
        self.presentationKind = presentationKind
    }

    /// Whether AVFoundation currently reports the specified media time as seekable.
    public func containsSeekableTime(_ time: TimeInterval) -> Bool {
        seekableRanges.contains { $0.contains(time) }
    }
}
