import AVFoundation
import Foundation
import Testing
@testable import StreamKit

@Suite("Authenticated HLS resource-loader integration")
@MainActor
struct AuthenticatedMediaResourceLoaderIntegrationTests {
    @Test("AVURLAsset loads an authenticated playlist and requests its rewritten segment")
    func loadsPlaylistAndChildSegment() async throws {
        let host = Self.uniqueHost(prefix: "media")
        let origin = ControlledOrigin(
            host: host,
            responses: [
                "/master.m3u8": .body(
                    statusCode: 200,
                    headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                    data: Data(Self.mediaPlaylist.utf8)
                ),
                "/segment.ts": .body(
                    statusCode: 206,
                    headers: [
                        "Content-Type": "video/mp2t",
                        "Content-Range": "bytes 0-375/376"
                    ],
                    data: Data(repeating: 0x47, count: 376)
                )
            ]
        )
        origin.register()
        defer { origin.unregister() }

        let loader = Self.makeLoader(trustedHosts: [host])
        let asset = try Self.makeAsset(host: host, path: "/master.m3u8", loader: loader)
        defer {
            asset.resourceLoader.setDelegate(nil, queue: nil)
            loader.cancelAll()
        }

        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        defer {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        player.play()
        let playlistRequest = try await origin.waitForRequest(path: "/master.m3u8")
        #expect(playlistRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")

        let segmentRequest = try await origin.waitForRequest(path: "/segment.ts")
        #expect(segmentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
        #expect(segmentRequest.value(forHTTPHeaderField: "Range") == "bytes=0-375")
        try await origin.waitForCompletion(path: "/segment.ts")
    }

    @Test("Redirects reapply credentials only for trusted destinations")
    func redirectRescopesCredentials() async throws {
        let sourceHost = Self.uniqueHost(prefix: "source")
        let trustedHost = Self.uniqueHost(prefix: "trusted")
        let untrustedHost = Self.uniqueHost(prefix: "untrusted")
        let sourceOrigin = ControlledOrigin(
            host: sourceHost,
            responses: [
                "/master.m3u8": .redirect(URL(string: "https://\(trustedHost)/trusted.m3u8")!)
            ]
        )
        let trustedOrigin = ControlledOrigin(
            host: trustedHost,
            responses: [
                "/trusted.m3u8": .body(
                    statusCode: 200,
                    headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                    data: Data(Self.mediaPlaylist.utf8)
                )
            ]
        )
        let untrustedSourceHost = Self.uniqueHost(prefix: "source-untrusted")
        let untrustedSourceOrigin = ControlledOrigin(
            host: untrustedSourceHost,
            responses: [
                "/master.m3u8": .redirect(URL(string: "https://\(untrustedHost)/untrusted.m3u8")!)
            ]
        )
        let untrustedOrigin = ControlledOrigin(
            host: untrustedHost,
            responses: [
                "/untrusted.m3u8": .body(
                    statusCode: 200,
                    headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                    data: Data(Self.mediaPlaylist.utf8)
                )
            ]
        )
        sourceOrigin.register()
        trustedOrigin.register()
        untrustedSourceOrigin.register()
        untrustedOrigin.register()
        defer {
            sourceOrigin.unregister()
            trustedOrigin.unregister()
            untrustedSourceOrigin.unregister()
            untrustedOrigin.unregister()
        }

        let trustedLoader = Self.makeLoader(trustedHosts: [sourceHost, trustedHost])
        let trustedAsset = try Self.makeAsset(
            host: sourceHost,
            path: "/master.m3u8",
            loader: trustedLoader
        )
        defer {
            trustedAsset.resourceLoader.setDelegate(nil, queue: nil)
            trustedLoader.cancelAll()
        }

        let trustedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: trustedAsset))
        defer {
            trustedPlayer.pause()
            trustedPlayer.replaceCurrentItem(with: nil)
        }
        trustedPlayer.play()
        let initialTrustedRequest = try await sourceOrigin.waitForRequest(path: "/master.m3u8")
        let redirectedTrustedRequest = try await trustedOrigin.waitForRequest(path: "/trusted.m3u8")
        #expect(initialTrustedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(redirectedTrustedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")

        let untrustedLoader = Self.makeLoader(
            trustedHosts: [untrustedSourceHost],
            cookies: [
                MediaCookie(name: "session", value: "secret-cookie", domain: untrustedSourceHost)
            ]
        )
        let untrustedAsset = try Self.makeAsset(
            host: untrustedSourceHost,
            path: "/master.m3u8",
            loader: untrustedLoader
        )
        defer {
            untrustedAsset.resourceLoader.setDelegate(nil, queue: nil)
            untrustedLoader.cancelAll()
        }

        let untrustedPlayer = AVPlayer(playerItem: AVPlayerItem(asset: untrustedAsset))
        defer {
            untrustedPlayer.pause()
            untrustedPlayer.replaceCurrentItem(with: nil)
        }
        untrustedPlayer.play()
        let initialUntrustedRequest = try await untrustedSourceOrigin.waitForRequest(path: "/master.m3u8")
        let redirectedUntrustedRequest = try await untrustedOrigin.waitForRequest(path: "/untrusted.m3u8")
        #expect(initialUntrustedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(initialUntrustedRequest.value(forHTTPHeaderField: "Cookie") == "session=secret-cookie")
        #expect(redirectedUntrustedRequest.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(redirectedUntrustedRequest.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("Rejects an HTTPS redirect to an HTTP destination")
    func redirectDoesNotDowngradeToHTTP() async throws {
        let sourceHost = Self.uniqueHost(prefix: "secure-source")
        let destinationHost = Self.uniqueHost(prefix: "insecure-destination")
        let sourceOrigin = ControlledOrigin(
            host: sourceHost,
            responses: [
                "/master.m3u8": .redirect(URL(string: "http://\(destinationHost)/master.m3u8")!)
            ]
        )
        let destinationOrigin = ControlledOrigin(
            host: destinationHost,
            responses: [
                "/master.m3u8": .body(
                    statusCode: 200,
                    headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                    data: Data(Self.mediaPlaylist.utf8)
                )
            ]
        )
        sourceOrigin.register()
        destinationOrigin.register()
        defer {
            sourceOrigin.unregister()
            destinationOrigin.unregister()
        }

        let loader = Self.makeLoader(trustedHosts: [sourceHost, destinationHost])
        let asset = try Self.makeAsset(host: sourceHost, path: "/master.m3u8", loader: loader)
        defer {
            asset.resourceLoader.setDelegate(nil, queue: nil)
            loader.cancelAll()
        }
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        defer {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        player.play()

        _ = try await sourceOrigin.waitForRequest(path: "/master.m3u8")
        try await Task.sleep(for: .milliseconds(250))
        #expect(!destinationOrigin.hasRequest(path: "/master.m3u8"))
    }

    @Test("Cancelling the loader stops an in-flight AVURLAsset request")
    func cancellationStopsInFlightRequest() async throws {
        let host = Self.uniqueHost(prefix: "cancel")
        let origin = ControlledOrigin(host: host, responses: ["/held.m3u8": .hold])
        origin.register()
        defer { origin.unregister() }

        let loader = Self.makeLoader(trustedHosts: [host])
        let asset = try Self.makeAsset(host: host, path: "/held.m3u8", loader: loader)

        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        defer {
            player.pause()
            player.replaceCurrentItem(with: nil)
            asset.resourceLoader.setDelegate(nil, queue: nil)
            loader.cancelAll()
        }
        player.play()
        _ = try await origin.waitForRequest(path: "/held.m3u8")
        loader.cancelAll()

        try await origin.waitForStop(path: "/held.m3u8")
    }

    @Test("Source replacement and shutdown cancel the matching in-flight HLS loads")
    func sourceReplacementAndShutdownCancelLoads() async throws {
        let firstHost = Self.uniqueHost(prefix: "first-source")
        let secondHost = Self.uniqueHost(prefix: "second-source")
        let firstOrigin = ControlledOrigin(host: firstHost, responses: ["/first.m3u8": .hold])
        let secondOrigin = ControlledOrigin(host: secondHost, responses: ["/second.m3u8": .hold])
        firstOrigin.register()
        secondOrigin.register()
        defer {
            firstOrigin.unregister()
            secondOrigin.unregister()
        }

        let engine = AVFoundationPlaybackEngine(
            urlProtocolClassesForTesting: [ControlledOriginURLProtocol.self]
        )
        let controller = StreamPlayerController(engine: engine)

        do {
            let firstLoad = controller.load(Self.authenticatedSource(host: firstHost, path: "/first.m3u8"))
            _ = try await firstOrigin.waitForRequest(path: "/first.m3u8")

            let secondLoad = controller.load(Self.authenticatedSource(host: secondHost, path: "/second.m3u8"))
            try await firstOrigin.waitForStop(path: "/first.m3u8")
            _ = try await secondOrigin.waitForRequest(path: "/second.m3u8")

            await controller.shutdown()
            try await secondOrigin.waitForStop(path: "/second.m3u8")

            do {
                try await firstLoad.waitUntilReady()
                Issue.record("The replaced source unexpectedly became ready.")
            } catch is CancellationError {
                // Replacing a source cancels the previous readiness operation.
            } catch {
                Issue.record("The replaced load failed with an unexpected error: \(error)")
            }
            do {
                try await secondLoad.waitUntilReady()
                Issue.record("The shutdown source unexpectedly became ready.")
            } catch is CancellationError {
                // Shutdown cancels the active readiness operation.
            } catch {
                Issue.record("The shutdown load failed with an unexpected error: \(error)")
            }
        } catch {
            await controller.shutdown()
            throw error
        }
    }

    private static let mediaPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:4
        #EXT-X-TARGETDURATION:2
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:2.0,
        #EXT-X-BYTERANGE:376@0
        segment.ts
        #EXT-X-ENDLIST
        """

    private static func uniqueHost(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased()).streamkit.test"
    }

    private static func authenticatedSource(host: String, path: String) -> MediaSource {
        let authentication = MediaBearerAuthentication(trustedHosts: [host]) { _ in
            "token"
        }
        return MediaSource(
            url: URL(string: "https://\(host)\(path)")!,
            requestConfiguration: MediaRequestConfiguration(
                bearerAuthentication: authentication
            )
        )
    }

    private static func makeLoader(
        trustedHosts: [String],
        cookies: [MediaCookie] = []
    ) -> AuthenticatedMediaResourceLoader {
        let tokens = IntegrationTokenSequence()
        let authentication = MediaBearerAuthentication(trustedHosts: Set(trustedHosts)) { url in
            await tokens.next(for: url)
        }
        return AuthenticatedMediaResourceLoader(
            authentication: authentication,
            cookies: cookies,
            userAgent: nil,
            urlProtocolClassesForTesting: [ControlledOriginURLProtocol.self]
        )
    }

    private static func makeAsset(
        host: String,
        path: String,
        loader: AuthenticatedMediaResourceLoader
    ) throws -> AVURLAsset {
        let sourceURL = URL(string: "https://\(host)\(path)")!
        let assetURL = try AuthenticatedMediaResourceLoader.assetURL(for: sourceURL)
        let asset = AVURLAsset(url: assetURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.delegateQueue)
        return asset
    }
}

private actor IntegrationTokenSequence {
    private var count = 0

    func next(for _: URL) -> String {
        count += 1
        return "token-\(count)"
    }
}
