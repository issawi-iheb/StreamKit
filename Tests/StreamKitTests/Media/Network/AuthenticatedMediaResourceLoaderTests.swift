import Foundation
import Testing
@testable import StreamKit

@Suite("Authenticated HLS resource loading")
struct AuthenticatedMediaResourceLoaderTests {
    @Test("Builds finite and open-ended byte ranges from AVFoundation request details")
    func buildsByteRanges() throws {
        let finiteRange = try AuthenticatedMediaByteRange.make(
            requestedOffset: 10,
            currentOffset: 14,
            requestedLength: 12,
            requestsAllDataToEndOfResource: false
        )
        let openEndedRange = try AuthenticatedMediaByteRange.make(
            requestedOffset: 10,
            currentOffset: 10,
            requestedLength: 0,
            requestsAllDataToEndOfResource: true
        )
        let fullResourceRequest = try AuthenticatedMediaByteRange.make(
            requestedOffset: 0,
            currentOffset: 0,
            requestedLength: 0,
            requestsAllDataToEndOfResource: true
        )

        #expect(finiteRange?.headerValue == "bytes=14-25")
        #expect(openEndedRange?.headerValue == "bytes=10-")
        #expect(fullResourceRequest == nil)
    }

    @Test("Rejects finite byte-range arithmetic overflow")
    func rejectsByteRangeOverflow() {
        #expect(throws: PlaybackFailure.self) {
            _ = try AuthenticatedMediaByteRange.make(
                requestedOffset: Int64.max,
                currentOffset: Int64.max,
                requestedLength: 2,
                requestsAllDataToEndOfResource: false
            )
        }
    }

    @Test("Rejects a server that ignores a finite range beginning at byte zero")
    func rejectsIgnoredZeroOffsetRange() throws {
        let range = try AuthenticatedMediaByteRange.make(
            requestedOffset: 0,
            currentOffset: 0,
            requestedLength: 10,
            requestsAllDataToEndOfResource: false
        )!
        let response = httpResponse(statusCode: 200)

        #expect(throws: PlaybackFailure.self) {
            try range.validate(response: response)
        }
    }

    @Test("Rejects a partial response with the wrong Content-Range start")
    func rejectsMisalignedContentRange() throws {
        let range = try AuthenticatedMediaByteRange.make(
            requestedOffset: 10,
            currentOffset: 10,
            requestedLength: 10,
            requestsAllDataToEndOfResource: false
        )!
        let response = httpResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 9-18/100"]
        )

        #expect(throws: PlaybackFailure.self) {
            try range.validate(response: response)
        }
    }

    @Test("Accepts an exact finite response and caps it to its declared range")
    func acceptsExactFiniteRange() throws {
        let range = try AuthenticatedMediaByteRange.make(
            requestedOffset: 10,
            currentOffset: 10,
            requestedLength: 10,
            requestsAllDataToEndOfResource: false
        )!
        let response = httpResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 10-19/100"]
        )

        let validated = try range.validate(response: response)

        #expect(validated.bodyLength == 10)
        #expect(validated.remainingBytes(after: 7) == 3)
        #expect(validated.remainingBytes(after: 10) == 0)
    }

    @Test("Accepts a short finite response only when Content-Range proves end of resource")
    func acceptsShortRangeOnlyAtEndOfResource() throws {
        let range = try AuthenticatedMediaByteRange.make(
            requestedOffset: 90,
            currentOffset: 90,
            requestedLength: 20,
            requestsAllDataToEndOfResource: false
        )!
        let response = httpResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 90-99/100"]
        )

        #expect(try range.validate(response: response).bodyLength == 10)
    }

    @Test("Rejects a short finite response before the resource end")
    func rejectsPrematureShortRange() throws {
        let range = try AuthenticatedMediaByteRange.make(
            requestedOffset: 10,
            currentOffset: 10,
            requestedLength: 10,
            requestsAllDataToEndOfResource: false
        )!
        let response = httpResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 10-14/100"]
        )

        #expect(throws: PlaybackFailure.self) {
            try range.validate(response: response)
        }
    }

    @Test("Uses open-ended ranges for requests from a nonzero offset through EOF")
    func validatesOpenEndedRange() throws {
        let range = try AuthenticatedMediaByteRange.make(
            requestedOffset: 100,
            currentOffset: 100,
            requestedLength: 0,
            requestsAllDataToEndOfResource: true
        )!
        let response = httpResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 100-199/200"]
        )

        #expect(range.headerValue == "bytes=100-")
        #expect(try range.validate(response: response).bodyLength == 100)
    }

    @Test("Requires a full HTTP response when no range was requested")
    func rejectsPartialResponseWithoutRange() throws {
        let response = httpResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 0-9/100"]
        )

        #expect(throws: PlaybackFailure.self) {
            try AuthenticatedMediaByteRange.validateFullResponse(response)
        }
    }

    @Test("Authenticated requests do not use shared cookie storage")
    func authenticatedSessionDoesNotUseSharedCookies() {
        let configuration = AuthenticatedMediaResourceLoader.makeSessionConfiguration()

        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
    }

    @Test("Requests fresh tokens for each media resource")
    func requestsTokenForEachResource() async throws {
        let tokenSequence = TokenSequence()
        let authentication = MediaBearerAuthentication(trustedHosts: ["media.example.com"]) { _ in
            await tokenSequence.next()
        }
        let playlistRequest = try await AuthenticatedMediaResourceLoader.makeURLRequest(
            for: URL(string: "https://media.example.com/master.m3u8")!,
            authentication: authentication,
            cookies: [],
            userAgent: nil
        )
        let segmentRequest = try await AuthenticatedMediaResourceLoader.makeURLRequest(
            for: URL(string: "https://media.example.com/segment.ts")!,
            authentication: authentication,
            cookies: [],
            userAgent: nil
        )

        #expect(playlistRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(segmentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
    }

    @Test("Maps HTTPS asset URLs to a loader scheme and back")
    func mapsAuthenticatedAssetURL() throws {
        let sourceURL = URL(string: "https://media.example.com/path/master.m3u8?x=1")!
        let assetURL = try AuthenticatedMediaResourceLoader.assetURL(for: sourceURL)

        #expect(assetURL.scheme == AuthenticatedMediaResourceLoader.httpsScheme)
        #expect(try AuthenticatedMediaResourceLoader.networkURL(for: assetURL) == sourceURL)
    }

    @Test("Rejects non-HTTPS authenticated assets")
    func rejectsInsecureAssetURL() {
        let sourceURL = URL(string: "http://media.example.com/master.m3u8")!

        #expect(throws: PlaybackFailure.self) {
            try AuthenticatedMediaResourceLoader.assetURL(for: sourceURL)
        }
    }

    @Test("Builds bearer requests with scoped cookie, user-agent, and range headers")
    func buildsAuthenticatedResourceRequest() async throws {
        let authentication = MediaBearerAuthentication(trustedHosts: ["media.example.com"]) { url in
            "token-\(url.lastPathComponent)"
        }
        let cookies = [
            MediaCookie(name: "session", value: "abc", domain: "example.com", path: "/video"),
            MediaCookie(name: "unrelated", value: "no", domain: "other.example.com")
        ]
        let url = URL(string: "https://media.example.com/video/segment.ts")!

        let request = try await AuthenticatedMediaResourceLoader.makeURLRequest(
            for: url,
            authentication: authentication,
            cookies: cookies,
            userAgent: "StreamKitDemo/1.0",
            range: "bytes=10-19"
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-segment.ts")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "session=abc")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "StreamKitDemo/1.0")
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=10-19")
    }

    @Test("Does not send bearer token or cookie to an untrusted host")
    func omitsCredentialsForUntrustedHost() async throws {
        let authentication = MediaBearerAuthentication(trustedHosts: ["media.example.com"]) { _ in
            "secret"
        }
        let request = try await AuthenticatedMediaResourceLoader.makeURLRequest(
            for: URL(string: "https://cdn.example.com/segment.ts")!,
            authentication: authentication,
            cookies: [MediaCookie(name: "session", value: "secret", domain: "media.example.com")],
            userAgent: nil
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("Respects cookie path boundaries")
    func respectsCookiePathBoundaries() async throws {
        let authentication = MediaBearerAuthentication(trustedHosts: ["media.example.com"]) { _ in
            "token"
        }
        let request = try await AuthenticatedMediaResourceLoader.makeURLRequest(
            for: URL(string: "https://media.example.com/video2/segment.ts")!,
            authentication: authentication,
            cookies: [MediaCookie(name: "session", value: "secret", domain: "media.example.com", path: "/video")],
            userAgent: nil
        )

        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("Rewrites relative HLS segment and key URIs through the authenticated loader")
    func rewritesPlaylistResourceURIs() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin"
        #EXTINF:6.0,
        segments/one.ts
        """
        let baseURL = URL(string: "https://media.example.com/path/master.m3u8")!

        let result = try HLSPlaylistRewriter.rewrite(Data(playlist.utf8), playlistURL: baseURL)
        let rewritten = String(decoding: result, as: UTF8.self)

        #expect(rewritten.contains("URI=\"streamkit-auth-https://media.example.com/path/keys/key.bin\""))
        #expect(rewritten.contains("streamkit-auth-https://media.example.com/path/segments/one.ts"))
    }

    @Test("Rewrites absolute HTTPS HLS resources")
    func rewritesAbsoluteHTTPSResources() throws {
        let playlist = """
        #EXTM3U
        https://cdn.example.com/video/segment.ts?token=abc
        """
        let baseURL = URL(string: "https://media.example.com/master.m3u8")!

        let result = try HLSPlaylistRewriter.rewrite(Data(playlist.utf8), playlistURL: baseURL)
        let rewritten = String(decoding: result, as: UTF8.self)

        #expect(rewritten.contains("streamkit-auth-https://cdn.example.com/video/segment.ts?token=abc"))
    }

    @Test("Rejects insecure HTTP resources in an authenticated HLS playlist")
    func rejectsInsecureChildResources() {
        let playlist = "#EXTM3U\nhttp://cdn.example.com/segment.ts\n"
        let baseURL = URL(string: "https://media.example.com/master.m3u8")!

        #expect(throws: PlaybackFailure.self) {
            try HLSPlaylistRewriter.rewrite(Data(playlist.utf8), playlistURL: baseURL)
        }
    }

    private func httpResponse(
        statusCode: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://media.example.com/video.ts")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}

private actor TokenSequence {
    private var count = 0

    func next() -> String {
        count += 1
        return "token-\(count)"
    }
}
