import Foundation
import AVFoundation

/// A privacy-safe performance metric reported by AVFoundation for a source load.
///
/// Metrics are separate from lifecycle diagnostics because HLS request events
/// can be much more frequent. StreamKit omits URLs, server addresses, headers,
/// rendition identifiers, and raw AVFoundation metric objects.
public struct PlaybackMetricEvent: Equatable, Sendable {
    public enum ResourceType: Equatable, Sendable {
        case resource
        case playlist
        case mediaSegment
        case contentKey
    }

    public enum MediaType: Equatable, Sendable {
        case audio
        case video
        case subtitle
        case muxed
        case other
    }

    public struct PlaybackSummary: Equatable, Sendable {
        public let playbackDuration: TimeInterval
        public let initialStartupDuration: TimeInterval
        public let stallCount: Int
        public let stallRecoveryDuration: TimeInterval
        public let mediaRequestCount: Int
        public let recoverableErrorCount: Int
        public let variantSwitchCount: Int
        public let timeWeightedAverageBitrate: Int
        public let timeWeightedPeakBitrate: Int

        @available(macOS 15, iOS 18, *)
        init(_ event: AVMetricPlayerItemPlaybackSummaryEvent) {
            playbackDuration = TimeInterval(event.playbackDuration)
            initialStartupDuration = event.timeSpentInInitialStartup
            stallCount = event.stallCount
            stallRecoveryDuration = event.timeSpentRecoveringFromStall
            mediaRequestCount = event.mediaResourceRequestCount
            recoverableErrorCount = event.recoverableErrorCount
            variantSwitchCount = event.variantSwitchCount
            timeWeightedAverageBitrate = event.timeWeightedAverageBitrate
            timeWeightedPeakBitrate = event.timeWeightedPeakBitrate
        }
    }

    public enum Kind: Equatable, Sendable {
        case resourceRequest(
            resourceType: ResourceType,
            mediaType: MediaType,
            requestDuration: TimeInterval,
            responseDuration: TimeInterval?,
            segmentDuration: TimeInterval?,
            responseBytes: Int64?,
            httpStatusCode: Int?,
            wasReadFromCache: Bool
        )
        case startupCompleted(timeToLikelyToKeepUp: TimeInterval)
        case stall
        case variantSwitch(succeeded: Bool)
        case playbackSummary(PlaybackSummary)
    }

    /// Monotonically increasing metric number for this controller.
    public let sequence: UInt64
    /// AVFoundation's event time.
    public let timestamp: Date
    /// Source-load generation that produced this event.
    public let loadGeneration: UInt64
    public let kind: Kind

    init(sequence: UInt64, timestamp: Date, loadGeneration: UInt64, kind: Kind) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.loadGeneration = loadGeneration
        self.kind = kind
    }
}
