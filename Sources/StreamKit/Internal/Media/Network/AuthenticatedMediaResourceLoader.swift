import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Routes bearer-authenticated HTTPS resources through a custom AVFoundation
/// resource-loader scheme. HLS playlists are rewritten so child resources use
/// the same authenticated loading path.
final class AuthenticatedMediaResourceLoader: NSObject,
    AVAssetResourceLoaderDelegate,
    @unchecked Sendable
{
    static let httpsScheme = "streamkit-auth-https"

    let delegateQueue = DispatchQueue(label: "StreamKit.AuthenticatedResourceLoader")

    private let authentication: MediaBearerAuthentication
    private let cookies: [MediaCookie]
    private let userAgent: String?
    private let session: URLSession
    private let sessionDelegate: AuthenticatedMediaSessionDelegate
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    // Integration tests replace HTTPS transport without relaxing loader policy.
    init(
        authentication: MediaBearerAuthentication,
        cookies: [MediaCookie],
        userAgent: String?,
        urlProtocolClassesForTesting: [AnyClass]? = nil
    ) {
        self.authentication = authentication
        self.cookies = cookies
        self.userAgent = userAgent
        self.sessionDelegate = AuthenticatedMediaSessionDelegate(
            authentication: authentication,
            cookies: cookies,
            userAgent: userAgent
        )
        self.session = URLSession(
            configuration: Self.makeSessionConfiguration(
                urlProtocolClassesForTesting: urlProtocolClassesForTesting
            ),
            delegate: sessionDelegate,
            delegateQueue: nil
        )
        super.init()
    }

    // Production passes nil to retain URLSession's native protocol handling.
    static func makeSessionConfiguration(
        urlProtocolClassesForTesting: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.protocolClasses = urlProtocolClassesForTesting
        return configuration
    }

    static func assetURL(for sourceURL: URL) throws -> URL {
        guard sourceURL.scheme?.lowercased() == "https",
              sourceURL.host != nil,
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        else {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "Bearer authentication requires an HTTPS media URL."
            )
        }
        components.scheme = httpsScheme
        guard let result = components.url else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The authenticated media URL is invalid."
            )
        }
        return result
    }

    static func networkURL(for assetURL: URL) throws -> URL {
        guard assetURL.scheme == httpsScheme,
              var components = URLComponents(url: assetURL, resolvingAgainstBaseURL: false)
        else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The authenticated media resource URL is invalid."
            )
        }
        components.scheme = "https"
        guard let result = components.url else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "The authenticated media resource URL is invalid."
            )
        }
        return result
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let identifier = ObjectIdentifier(loadingRequest)
        tasks[identifier] = Task { [weak self, weak loadingRequest] in
            guard let self, let loadingRequest else { return }
            await self.load(loadingRequest, identifier: identifier)
        }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
    }

    func cancelAll() {
        delegateQueue.sync {
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
        }
        session.invalidateAndCancel()
    }

    private func load(
        _ loadingRequest: AVAssetResourceLoadingRequest,
        identifier: ObjectIdentifier
    ) async {
        defer {
            delegateQueue.async { [weak self] in
                self?.tasks.removeValue(forKey: identifier)
            }
        }

        do {
            guard let assetURL = loadingRequest.request.url else {
                throw PlaybackFailure(code: .invalidSource, message: "The media resource URL is missing.")
            }
            let networkURL = try Self.networkURL(for: assetURL)
            let byteRange = try Self.byteRange(for: loadingRequest.dataRequest)
            let request = try await Self.makeURLRequest(
                for: networkURL,
                authentication: authentication,
                cookies: cookies,
                userAgent: userAgent,
                range: byteRange?.headerValue
            )

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlaybackFailure(code: .network, message: "The media server returned an invalid response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw PlaybackFailure(
                        code: .authentication,
                        message: "The media server rejected the supplied credentials."
                    )
                }
                throw PlaybackFailureMapping.map(URLError(.badServerResponse))
            }
            let rangeResponse: AuthenticatedMediaByteRangeResponse?
            if let byteRange {
                rangeResponse = try byteRange.validate(response: httpResponse)
            } else {
                try AuthenticatedMediaByteRange.validateFullResponse(httpResponse)
                rangeResponse = nil
            }

            await updateContentInformation(
                loadingRequest.contentInformationRequest,
                response: httpResponse,
                requestedURL: networkURL
            )

            let isPlaylist = Self.isPlaylist(url: networkURL, response: httpResponse)
            if isPlaylist {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    if let rangeResponse,
                       rangeResponse.remainingBytes(after: Int64(data.count)) == 0 {
                        throw Self.byteRangeLengthFailure()
                    }
                    data.append(byte)
                    guard data.count <= 4 * 1024 * 1024 else {
                        throw PlaybackFailure(code: .playback, message: "The media playlist is too large.")
                    }
                }
                try Self.validateDeliveredByteCount(
                    Int64(data.count),
                    expected: rangeResponse?.bodyLength
                )
                let rewritten = try HLSPlaylistRewriter.rewrite(data, playlistURL: response.url ?? networkURL)
                await updateContentLength(rewritten.count, for: loadingRequest.contentInformationRequest)
                await respond(rewritten, to: loadingRequest.dataRequest)
            } else {
                var chunk = Data()
                chunk.reserveCapacity(64 * 1024)
                var deliveredByteCount: Int64 = 0
                for try await byte in bytes {
                    try Task.checkCancellation()
                    if let rangeResponse,
                       rangeResponse.remainingBytes(after: deliveredByteCount) == 0 {
                        throw Self.byteRangeLengthFailure()
                    }
                    chunk.append(byte)
                    deliveredByteCount += 1
                    if chunk.count == 64 * 1024 {
                        await respond(chunk, to: loadingRequest.dataRequest)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty {
                    await respond(chunk, to: loadingRequest.dataRequest)
                }
                try Self.validateDeliveredByteCount(
                    deliveredByteCount,
                    expected: rangeResponse?.bodyLength
                )
            }

            await finish(loadingRequest, error: nil)
        } catch is CancellationError {
            await finish(loadingRequest, error: CancellationError())
        } catch {
            let loadingError: Error
            if let failure = error as? PlaybackFailure,
               failure.code == .authentication {
                loadingError = PlaybackFailureMapping.authenticationNSError(
                    message: failure.message
                )
            } else {
                loadingError = error
            }
            await finish(loadingRequest, error: loadingError)
        }
    }

    static func makeURLRequest(
        for url: URL,
        authentication: MediaBearerAuthentication,
        cookies: [MediaCookie],
        userAgent: String?,
        range: String? = nil
    ) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let authorization = try await authentication.authorizationHeader(for: url) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        if let userAgent, !userAgent.isEmpty {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let cookieHeader = cookieHeader(for: url, cookies: cookies)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        return request
    }

    private static func cookieHeader(for url: URL, cookies: [MediaCookie]) -> String {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.isEmpty ? "/" : url.path
        let pairs = cookies.compactMap { cookie -> String? in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let domainMatches = host == domain || host.hasSuffix("." + domain)
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = path == cookiePath
                || path.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
            let secureMatches = !cookie.isSecure || url.scheme == "https"
            guard domainMatches, pathMatches, secureMatches else { return nil }
            return "\(cookie.name)=\(cookie.value)"
        }
        return pairs.joined(separator: "; ")
    }

    private static func byteRange(
        for request: AVAssetResourceLoadingDataRequest?
    ) throws -> AuthenticatedMediaByteRange? {
        guard let request else { return nil }
        return try AuthenticatedMediaByteRange.make(
            requestedOffset: request.requestedOffset,
            currentOffset: request.currentOffset,
            requestedLength: request.requestedLength,
            requestsAllDataToEndOfResource: request.requestsAllDataToEndOfResource
        )
    }

    private static func validateDeliveredByteCount(
        _ deliveredByteCount: Int64,
        expected: Int64?
    ) throws {
        if let expected, deliveredByteCount != expected {
            throw byteRangeLengthFailure()
        }
    }

    private static func byteRangeLengthFailure() -> PlaybackFailure {
        PlaybackFailure(
            code: .network,
            message: "The media server returned a body that did not match the requested byte range."
        )
    }

    private static func isPlaylist(url: URL, response: HTTPURLResponse) -> Bool {
        url.pathExtension.lowercased() == "m3u8"
            || response.mimeType?.lowercased().contains("mpegurl") == true
    }

    private func updateContentInformation(
        _ information: AVAssetResourceLoadingContentInformationRequest?,
        response: HTTPURLResponse,
        requestedURL: URL
    ) async {
        guard let information else { return }
        await onDelegateQueue {
            let contentRange = response.value(forHTTPHeaderField: "Content-Range")
            if response.statusCode == 206 {
                if let contentRange,
                   let total = Int64(contentRange.split(separator: "/").last ?? "") {
                    information.contentLength = total
                }
            } else if response.expectedContentLength >= 0 {
                information.contentLength = response.expectedContentLength
            }
            let isPlaylist = Self.isPlaylist(url: requestedURL, response: response)
            information.isByteRangeAccessSupported = !isPlaylist
            if isPlaylist {
                information.contentType = "com.apple.m3u-playlist"
            } else if let mimeType = response.mimeType,
                      let type = UTType(mimeType: mimeType) {
                information.contentType = type.identifier
            }
        }
    }

    private func updateContentLength(
        _ length: Int,
        for information: AVAssetResourceLoadingContentInformationRequest?
    ) async {
        guard let information else { return }
        await onDelegateQueue {
            information.contentLength = Int64(length)
        }
    }

    private func respond(_ data: Data, to request: AVAssetResourceLoadingDataRequest?) async {
        guard let request else { return }
        await onDelegateQueue { request.respond(with: data) }
    }

    private func finish(_ request: AVAssetResourceLoadingRequest, error: Error?) async {
        await onDelegateQueue {
            if let error {
                request.finishLoading(with: error)
            } else {
                request.finishLoading()
            }
        }
    }

    private func onDelegateQueue(_ operation: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            delegateQueue.async {
                operation()
                continuation.resume()
            }
        }
    }
}

private final class AuthenticatedMediaSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let authentication: MediaBearerAuthentication
    private let cookies: [MediaCookie]
    private let userAgent: String?

    init(authentication: MediaBearerAuthentication, cookies: [MediaCookie], userAgent: String?) {
        self.authentication = authentication
        self.cookies = cookies
        self.userAgent = userAgent
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let completion = UnsafeSendableBox(completionHandler)
        Task {
            var redirectedRequest = request
            if let url = request.url {
                guard url.scheme?.lowercased() == "https" else {
                    completion.value(nil)
                    return
                }
                redirectedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
                redirectedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
                do {
                    if let authorization = try await authentication.authorizationHeader(for: url) {
                        redirectedRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
                    }
                } catch {
                    completion.value(nil)
                    return
                }
                if let userAgent, !userAgent.isEmpty {
                    redirectedRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                }
                let host = url.host?.lowercased() ?? ""
                let matchingCookies = cookies.filter { cookie in
                    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    let path = url.path.isEmpty ? "/" : url.path
                    let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
                    let pathMatches = path == cookiePath
                        || path.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
                    let secureMatches = !cookie.isSecure || url.scheme == "https"
                    return (host == domain || host.hasSuffix("." + domain))
                        && pathMatches && secureMatches
                }
                let header = matchingCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                if !header.isEmpty {
                    redirectedRequest.setValue(header, forHTTPHeaderField: "Cookie")
                }
            }
            completion.value(redirectedRequest)
        }
    }
}

private final class UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
