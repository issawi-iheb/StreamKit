import AVFoundation
import Foundation

extension AVFoundationPlaybackEngine {

    @available(macOS 15, iOS 18, *)
    func installMetricsObserver(
        for item: AVPlayerItem,
        engineGeneration: UInt64,
        sourceGeneration: UInt64
    ) {
        let metrics = item.allMetrics()
        metricsTask = Task { @MainActor [weak self, weak item] in
            do {
                for try await event in metrics {
                    guard let self, let item,
                          !Task.isCancelled,
                          self.isCurrentItem(item, generation: engineGeneration),
                          let kind = Self.normalizedMetric(from: event) else {
                        continue
                    }

                    self.emit(.metric(date: event.date, kind: kind), generation: sourceGeneration)
                }
            } catch {
                // Metrics are supplementary and must never change playback state.
            }
        }
    }

    @available(macOS 15, iOS 18, *)
    private static func normalizedMetric(
        from event: AVMetricEvent
    ) -> PlaybackMetricEvent.Kind? {
        if let request = event as? AVMetricMediaResourceRequestEvent {
            return resourceMetric(
                request,
                resourceType: .resource,
                mediaType: .other,
                segmentDuration: nil
            )
        }

        if let segment = event as? AVMetricHLSMediaSegmentRequestEvent,
           let request = segment.mediaResourceRequestEvent {
            return resourceMetric(
                request,
                resourceType: .mediaSegment,
                mediaType: mediaType(segment.mediaType),
                segmentDuration: segment.segmentDuration
            )
        }

        if let playlist = event as? AVMetricHLSPlaylistRequestEvent,
           let request = playlist.mediaResourceRequestEvent {
            return resourceMetric(
                request,
                resourceType: .playlist,
                mediaType: mediaType(playlist.mediaType),
                segmentDuration: nil
            )
        }

        if let keyRequest = event as? AVMetricContentKeyRequestEvent,
           let request = keyRequest.mediaResourceRequestEvent {
            return resourceMetric(
                request,
                resourceType: .contentKey,
                mediaType: mediaType(keyRequest.mediaType),
                segmentDuration: nil
            )
        }

        if let initialReady = event as? AVMetricPlayerItemInitialLikelyToKeepUpEvent {
            return .startupCompleted(timeToLikelyToKeepUp: initialReady.timeTaken)
        }

        if event is AVMetricPlayerItemStallEvent {
            return .stall
        }

        if let variantSwitch = event as? AVMetricPlayerItemVariantSwitchEvent {
            return .variantSwitch(succeeded: variantSwitch.didSucceed)
        }

        if let summary = event as? AVMetricPlayerItemPlaybackSummaryEvent {
            return .playbackSummary(.init(summary))
        }

        return nil
    }

    @available(macOS 15, iOS 18, *)
    private static func resourceMetric(
        _ event: AVMetricMediaResourceRequestEvent,
        resourceType: PlaybackMetricEvent.ResourceType,
        mediaType: PlaybackMetricEvent.MediaType,
        segmentDuration: TimeInterval?
    ) -> PlaybackMetricEvent.Kind {
        let requestDuration = max(0, event.requestEndTime.timeIntervalSince(event.requestStartTime))
        let responseInterval = event.responseEndTime.timeIntervalSince(event.responseStartTime)
        let responseDuration = responseInterval >= 0 ? responseInterval : nil
        let transactions = event.networkTransactionMetrics?.transactionMetrics ?? []
        let responseBytes = transactions.isEmpty
            ? nil
            : transactions.reduce(Int64(0)) { $0 &+ $1.countOfResponseBodyBytesReceived }
        let statusCode = transactions
            .compactMap { ($0.response as? HTTPURLResponse)?.statusCode }
            .last

        return .resourceRequest(
            resourceType: resourceType,
            mediaType: mediaType,
            requestDuration: requestDuration,
            responseDuration: responseDuration,
            segmentDuration: segmentDuration,
            responseBytes: responseBytes,
            httpStatusCode: statusCode,
            wasReadFromCache: event.wasReadFromCache
        )
    }

    @available(macOS 15, iOS 18, *)
    private static func mediaType(_ value: AVMediaType) -> PlaybackMetricEvent.MediaType {
        switch value {
        case .video: .video
        case .audio: .audio
        case .text, .closedCaption, .subtitle: .subtitle
        case .muxed: .muxed
        default: .other
        }
    }
}
