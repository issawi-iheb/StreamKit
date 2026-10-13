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

        #expect(source.requestConfiguration.httpHeaders.isEmpty)
    }

    @Test("Preserves HTTP headers")
    func preservesHTTPHeaders() {
        let headers = [
            "Authorization": "Bearer test-token",
            "X-Client-ID": "test-client"
        ]

        let source = MediaSource(
            url: URL(string: "https://example.com/video.m3u8")!,
            requestConfiguration: MediaRequestConfiguration(
                httpHeaders: headers
            )
        )

        #expect(source.requestConfiguration.httpHeaders == headers)
    }

    @Test("Identical sources are equal")
    func identicalSourcesAreEqual() {
        let url = URL(string: "https://example.com/video.m3u8")!
        let configuration = MediaRequestConfiguration(
            httpHeaders: ["Authorization": "Bearer test-token"]
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

    @Test("Sources with different headers are unequal")
    func differentHeadersProduceUnequalSources() {
        let url = URL(string: "https://example.com/video.m3u8")!

        let first = MediaSource(
            url: url,
            requestConfiguration: MediaRequestConfiguration(
                httpHeaders: ["Authorization": "Bearer token-a"]
            )
        )

        let second = MediaSource(
            url: url,
            requestConfiguration: MediaRequestConfiguration(
                httpHeaders: ["Authorization": "Bearer token-b"]
            )
        )

        #expect(first != second)
    }
}
