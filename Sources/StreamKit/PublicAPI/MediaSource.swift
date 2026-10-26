import Foundation

/// Declares the presentation semantics supplied by the media provider.
public enum MediaPresentationKind: Equatable, Sendable {
    /// No live or on-demand classification was supplied.
    case unspecified
    /// Finite, on-demand media such as a VOD asset.
    case onDemand
    /// A live presentation, with DVR availability reported by seekable ranges.
    case live
}

/// Describes a media resource that StreamKit can play.
public struct MediaSource: Equatable, Sendable {

    /// The location of the media resource.
    public let url: URL

    /// Configuration used when requesting the media.
    public let requestConfiguration: MediaRequestConfiguration
    /// Caller-supplied playback semantics. StreamKit doesn't infer live
    /// playback from an indefinite duration or seekable ranges.
    public let presentationKind: MediaPresentationKind

    public init(
        url: URL,
        requestConfiguration: MediaRequestConfiguration = .init(),
        presentationKind: MediaPresentationKind = .unspecified
    ) {
        self.url = url
        self.requestConfiguration = requestConfiguration
        self.presentationKind = presentationKind
    }
}
