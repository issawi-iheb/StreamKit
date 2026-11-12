import Foundation

/// Supplies a fresh bearer token for each media resource request.
///
/// The player invokes the provider for the initial asset and each HLS child
/// resource. Exact host allowlisting prevents credentials from being sent to
/// hosts that are not explicitly trusted.
public struct MediaBearerAuthentication: Sendable, Equatable {
    private let id: UUID
    private let trustedHosts: Set<String>
    private let tokenProvider: @Sendable (URL) async throws -> String

    /// Creates bearer authentication scoped to an explicit set of host names.
    /// Host names are compared case-insensitively and must match exactly.
    public init(
        trustedHosts: Set<String>,
        tokenProvider: @escaping @Sendable (URL) async throws -> String
    ) {
        self.id = UUID()
        self.trustedHosts = Set(trustedHosts.map { $0.lowercased() })
        self.tokenProvider = tokenProvider
    }

    func token(for url: URL) async throws -> String? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              trustedHosts.contains(host)
        else {
            return nil
        }
        do {
            let token = try await tokenProvider(url)
            try Task.checkCancellation()
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlaybackFailure(
                    code: .authentication,
                    message: "The media token provider returned an empty token."
                )
            }
            return token
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as PlaybackFailure {
            throw failure
        } catch {
            throw PlaybackFailure(
                code: .authentication,
                message: "The app could not obtain media authorization."
            )
        }
    }

    func authorizationHeader(for url: URL) async throws -> String? {
        try await token(for: url).map { "Bearer \($0)" }
    }

    func trusts(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return false }
        return trustedHosts.contains(host)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

/// A cookie attached to matching media requests made by AVFoundation.
public struct MediaCookie: Equatable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        isSecure: Bool = true
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
    }
}

/// Configuration for requests used to retrieve media.
public struct MediaRequestConfiguration: Equatable, Sendable {

    /// Cookies scoped by domain and path for media requests.
    /// Authenticated loading uses only these explicit cookies and does not
    /// consult the app's shared URLSession cookie storage.
    public let cookies: [MediaCookie]
    /// User-Agent supplied to AVURLAsset for media requests.
    public let userAgent: String?
    /// Optional bearer authentication for explicitly trusted media hosts.
    public let bearerAuthentication: MediaBearerAuthentication?
    /// Optional FairPlay Streaming integration for protected HLS media.
    public let fairPlay: FairPlayConfiguration?

    public init(
        cookies: [MediaCookie] = [],
        userAgent: String? = nil,
        bearerAuthentication: MediaBearerAuthentication? = nil,
        fairPlay: FairPlayConfiguration? = nil
    ) {
        self.cookies = cookies
        self.userAgent = userAgent
        self.bearerAuthentication = bearerAuthentication
        self.fairPlay = fairPlay
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cookies == rhs.cookies
            && lhs.userAgent == rhs.userAgent
            && lhs.bearerAuthentication == rhs.bearerAuthentication
            && lhs.fairPlay == rhs.fairPlay
    }
}
