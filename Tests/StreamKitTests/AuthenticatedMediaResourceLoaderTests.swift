import Foundation
import Testing
@testable import StreamKit

@Suite("Authenticated HLS resource loading")
struct AuthenticatedMediaResourceLoaderTests {
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
}

private actor TokenSequence {
    private var count = 0

    func next() -> String {
        count += 1
        return "token-\(count)"
    }
}
