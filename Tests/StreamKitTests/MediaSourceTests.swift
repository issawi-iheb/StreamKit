//
//  MediaSourceTests.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation
import Testing
@testable import StreamKit

@Suite("MediaSource")
struct MediaSourceTests {

    @Test("Preserves the media URL")
    func preservesURL() {
        let url = URL(
            string: "https://example.com/video.m3u8"
        )!

        let source = MediaSource(url: url)

        #expect(source.url == url)
    }

    @Test("Uses empty request configuration by default")
    func defaultsToEmptyRequestConfiguration() {
        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!
        )

        #expect(source.requestConfiguration.cookies.isEmpty)
        #expect(source.requestConfiguration.userAgent == nil)
    }

    @Test("Preserves cookies and user agent")
    func preservesCookiesAndUserAgent() {
        let cookie = MediaCookie(
            name: "session",
            value: "secret",
            domain: "media.example.com"
        )
        let source = MediaSource(
            url: URL(string: "https://media.example.com/video.m3u8")!,
            requestConfiguration: MediaRequestConfiguration(
                cookies: [cookie],
                userAgent: "StreamKitDemo/1.0"
            )
        )

        #expect(source.requestConfiguration.cookies == [cookie])
        #expect(source.requestConfiguration.userAgent == "StreamKitDemo/1.0")
    }

    @Test("Identical sources are equal")
    func identicalSourcesAreEqual() {
        let url = URL(string: "https://example.com/video.m3u8")!
        let configuration = MediaRequestConfiguration(
            cookies: [MediaCookie(name: "session", value: "token", domain: "example.com")]
        )

        let first = MediaSource(
            url: url,
            requestConfiguration: configuration
        )

        let second = MediaSource(
            url: url,
            requestConfiguration: configuration
        )

        #expect(first == second)
    }

    @Test("Sources with different cookies are unequal")
    func differentCookiesProduceUnequalSources() {
        let url = URL(string: "https://example.com/video.m3u8")!

        let first = MediaSource(
            url: url,
            requestConfiguration: MediaRequestConfiguration(
                cookies: [MediaCookie(name: "session", value: "a", domain: "example.com")]
            )
        )

        let second = MediaSource(
            url: url,
            requestConfiguration: MediaRequestConfiguration(
                cookies: [MediaCookie(name: "session", value: "b", domain: "example.com")]
            )
        )

        #expect(first != second)
    }

    @Test("Bearer tokens are requested only for explicitly trusted HTTPS hosts")
    func bearerAuthenticationIsHostScoped() async throws {
        let authentication = MediaBearerAuthentication(trustedHosts: ["MEDIA.example.com"]) { url in
            "token-for-\(url.path)"
        }

        let trustedURL = URL(string: "https://media.example.com/master.m3u8")!
        let untrustedURL = URL(string: "https://other.example.com/master.m3u8")!
        let insecureURL = URL(string: "http://media.example.com/master.m3u8")!

        #expect(try await authentication.authorizationHeader(for: trustedURL) == "Bearer token-for-/master.m3u8")
        #expect(try await authentication.authorizationHeader(for: untrustedURL) == nil)
        #expect(try await authentication.authorizationHeader(for: insecureURL) == nil)
    }
}
