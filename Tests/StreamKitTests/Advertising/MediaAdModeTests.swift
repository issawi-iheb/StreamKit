//
//  MediaAdModeTests.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import Foundation
import Testing
@testable import StreamKit

@Suite("MediaAdMode")
struct MediaAdModeTests {

    @Test("Equivalent configurations using the same provider are equal")
    @MainActor
    func equivalentConfigurationsAreEqual() {
        let provider = TestClientSideAdProvider()
        let request = ClientSideAdRequest(
            tagURL: URL(string: "https://ads.example.com/vast.xml")!
        )

        let first = ClientSideAdConfiguration(
            request: request,
            provider: provider
        )

        let second = ClientSideAdConfiguration(
            request: request,
            provider: provider
        )

        #expect(first == second)
    }

    @Test("Configurations using different providers are unequal")
    @MainActor
    func differentProvidersAreUnequal() {
        let request = ClientSideAdRequest(
            tagURL: URL(string: "https://ads.example.com/vast.xml")!
        )

        let first = ClientSideAdConfiguration(
            request: request,
            provider: TestClientSideAdProvider()
        )

        let second = ClientSideAdConfiguration(
            request: request,
            provider: TestClientSideAdProvider()
        )

        #expect(first != second)
    }

    @Test("Configurations with different requests are unequal")
    @MainActor
    func differentRequestsAreUnequal() {
        let provider = TestClientSideAdProvider()

        let first = ClientSideAdConfiguration(
            request: ClientSideAdRequest(
                tagURL: URL(string: "https://ads.example.com/first.xml")!
            ),
            provider: provider
        )

        let second = ClientSideAdConfiguration(
            request: ClientSideAdRequest(
                tagURL: URL(string: "https://ads.example.com/second.xml")!
            ),
            provider: provider
        )

        #expect(first != second)
    }

    @Test("MediaSource equality includes its ad configuration")
    @MainActor
    func mediaSourceEqualityIncludesAdConfiguration() {
        let url = URL(string: "https://media.example.com/video.m3u8")!
        let provider = TestClientSideAdProvider()

        let configuration = ClientSideAdConfiguration(
            request: ClientSideAdRequest(
                tagURL: URL(string: "https://ads.example.com/vast.xml")!
            ),
            provider: provider
        )

        let first = MediaSource(
            url: url,
            adMode: .clientSide(configuration)
        )

        let second = MediaSource(
            url: url,
            adMode: .clientSide(configuration)
        )

        let withoutAds = MediaSource(url: url)

        #expect(first == second)
        #expect(first != withoutAds)
    }

    @Test("Ad request descriptions redact the tag URL")
    func adRequestDescriptionsAreRedacted() {
        let request = ClientSideAdRequest(
            tagURL: URL(string: "https://ads.example.com/private?token=secret")!
        )

        #expect(!request.description.contains("secret"))
        #expect(!request.debugDescription.contains("ads.example.com"))
    }
}

@MainActor
private final class TestClientSideAdProvider: ClientSideAdProvider {

    func makeSession(
        for request: ClientSideAdRequest,
        context: ClientSideAdSessionContext
    ) throws -> any ClientSideAdSession {
        TestClientSideAdSession()
    }
}

@MainActor
private final class TestClientSideAdSession: ClientSideAdSession {

    let events = AsyncStream<ClientSideAdEvent> { continuation in
        continuation.finish()
    }

    func start() {}
    func contentDidFinish() {}
    func pauseBreak() {}
    func resumeBreak() {}
    func invalidate() {}
}
