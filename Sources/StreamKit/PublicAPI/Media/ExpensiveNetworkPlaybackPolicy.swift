import Foundation

/// Optional playback limits that AVFoundation applies on expensive networks.
///
/// The system continues to choose HLS variants adaptively within these limits.
/// A `nil` value leaves that particular limit unset.
public struct ExpensiveNetworkPlaybackPolicy: Equatable, Sendable {

    /// Preferred maximum network bitrate in bits per second.
    public let maximumBitRate: Double?

    /// Preferred maximum video resolution in pixels.
    public let maximumResolution: CGSize?

    /// Creates an expensive-network policy with at least one limit.
    public init(
        maximumBitRate: Double? = nil,
        maximumResolution: CGSize? = nil
    ) {
        precondition(
            maximumBitRate == nil || (maximumBitRate!.isFinite && maximumBitRate! > 0),
            "The maximum bit rate must be finite and greater than zero."
        )
        precondition(
            maximumResolution == nil ||
                (maximumResolution!.width.isFinite && maximumResolution!.height.isFinite &&
                    maximumResolution!.width > 0 && maximumResolution!.height > 0),
            "The maximum resolution dimensions must be finite and greater than zero."
        )
        precondition(
            maximumBitRate != nil || maximumResolution != nil,
            "An expensive-network policy must set a bit-rate or resolution limit."
        )

        self.maximumBitRate = maximumBitRate
        self.maximumResolution = maximumResolution
    }
}
