import Foundation

/// A normalized point in the primary timeline for a restricted interstitial.
struct PlaybackInterstitialSeekRestriction: Equatable, Sendable {
    let time: TimeInterval?
    let date: Date?
}

/// Pure seek policy shared by ordinary forward seeks and live-edge seeks.
enum PlaybackInterstitialSeekPolicy {
    static func activeBreakRestrictsForwardSeek(
        from currentTime: TimeInterval,
        to targetTime: TimeInterval,
        restrictsForwardSeeking: Bool
    ) -> Bool {
        restrictsForwardSeeking
            && currentTime.isFinite
            && targetTime.isFinite
            && targetTime > currentTime
    }

    static func crossesRestrictedInterstitial(
        from currentTime: TimeInterval,
        to targetTime: TimeInterval,
        currentDate: Date?,
        targetDate: Date?,
        scheduledRestrictions: [PlaybackInterstitialSeekRestriction]
    ) -> Bool {
        guard currentTime.isFinite,
              targetTime.isFinite,
              targetTime > currentTime else {
            return false
        }

        return scheduledRestrictions.contains { restriction in
            if let time = restriction.time,
               time.isFinite,
               time >= currentTime,
               time < targetTime {
                return true
            }

            if let date = restriction.date,
               let currentDate,
               let targetDate,
               date >= currentDate,
               date < targetDate {
                return true
            }

            return false
        }
    }
}
