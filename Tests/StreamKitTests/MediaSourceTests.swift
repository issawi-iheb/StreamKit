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
        #expect(source.requestConfiguration.fairPlay == nil)
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

    @Test("Preserves FairPlay configuration and compares its identity")
    func preservesFairPlayConfiguration() {
        let url = URL(string: "https://media.example.com/protected.m3u8")!
        let provider = TestFairPlayLicenseProvider()
        let fairPlay = FairPlayConfiguration(licenseProvider: provider)
        let configuration = MediaRequestConfiguration(fairPlay: fairPlay)
        let source = MediaSource(url: url, requestConfiguration: configuration)

        #expect(source.requestConfiguration.fairPlay == fairPlay)
        #expect(configuration == MediaRequestConfiguration(fairPlay: fairPlay))
        #expect(configuration != MediaRequestConfiguration(
            fairPlay: FairPlayConfiguration(licenseProvider: provider)
        ))
    }

    @Test("Preserves FairPlay license request fields")
    func preservesFairPlayLicenseRequest() {
        let request = FairPlayLicenseRequest(
            contentIdentifier: Data([1, 2]),
            streamingContentKeyRequest: Data([3, 4]),
            isRenewal: true
        )

        #expect(request.contentIdentifier == Data([1, 2]))
        #expect(request.streamingContentKeyRequest == Data([3, 4]))
        #expect(request.isRenewal)
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

private struct TestFairPlayLicenseProvider: FairPlayLicenseProvider {
    func applicationCertificate() async throws -> Data { Data([1]) }

    func contentIdentifier(
        for keyIdentifier: String,
        initializationData: Data?
    ) throws -> Data {
        Data(keyIdentifier.utf8)
    }

    func contentKey(for request: FairPlayLicenseRequest) async throws -> Data {
        Data([2])
    }
}
