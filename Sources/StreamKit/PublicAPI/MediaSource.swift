import Foundation

/// Configuration for requests used to retrieve media.
public struct MediaRequestConfiguration: Equatable, Sendable {

    /// HTTP headers to include in media requests.
    ///
    /// Do not log this dictionary because it may contain
    /// sensitive values such as authorization tokens.
    public let httpHeaders: [String: String]

    public init(
        httpHeaders: [String: String] = [:]
    ) {
        self.httpHeaders = httpHeaders
    }
}

/// Describes a media resource that StreamKit can play.
public struct MediaSource: Equatable, Sendable {

    /// The location of the media resource.
    public let url: URL

    /// Configuration used when requesting the media.
    public let requestConfiguration: MediaRequestConfiguration

    public init(
        url: URL,
        requestConfiguration: MediaRequestConfiguration = .init()
    ) {
        self.url = url
        self.requestConfiguration = requestConfiguration
    }
}
