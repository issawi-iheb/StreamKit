//
//  AVFoundationPlaybackItemFactory.swift
//  StreamKit
//

import AVFoundation
import Foundation

/// Holds the AVFoundation objects that must live as long as a playback item.
struct PreparedPlaybackItem {
    let item: AVPlayerItem
    let authenticatedResourceLoader: AuthenticatedMediaResourceLoader?
    let fairPlayContentKeySession: FairPlayContentKeySession?
}

/// Translates a public media source into an AVFoundation item and its resources.
/// Playback lifecycle, readiness, and replacement remain the engine's job.
@MainActor
enum AVFoundationPlaybackItemFactory {

    static func make(
        from source: MediaSource,
        fairPlayDiagnosticHandler: ((FairPlayKeySessionDiagnostic) -> Void)? = nil
    ) throws -> PreparedPlaybackItem {
        let request = source.requestConfiguration

        guard request.fairPlay == nil || source.url.scheme?.lowercased() == "https" else {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "FairPlay-protected media must use HTTPS."
            )
        }

        var assetOptions: [String: Any] = [:]
        if let userAgent = request.userAgent, !userAgent.isEmpty {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
                assetOptions[AVURLAssetHTTPUserAgentKey] = userAgent
            } else {
                throw PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "A custom User-Agent requires a newer operating system."
                )
            }
        }

        if !request.cookies.isEmpty {
            let cookies = request.cookies.compactMap { value in
                HTTPCookie(properties: [
                    .name: value.name,
                    .value: value.value,
                    .domain: value.domain,
                    .path: value.path,
                    .secure: value.isSecure ? "TRUE" : "FALSE"
                ])
            }
            guard cookies.count == request.cookies.count else {
                throw PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "One or more media cookies are invalid."
                )
            }
            assetOptions[AVURLAssetHTTPCookiesKey] = cookies
        }

        let assetURL: URL
        let resourceLoader: AuthenticatedMediaResourceLoader?
        if let authentication = request.bearerAuthentication {
            guard authentication.trusts(source.url) else {
                throw PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "Bearer authentication must trust the media URL host."
                )
            }
            assetURL = try AuthenticatedMediaResourceLoader.assetURL(for: source.url)
            let loader = AuthenticatedMediaResourceLoader(
                authentication: authentication,
                cookies: request.cookies,
                userAgent: request.userAgent
            )
            resourceLoader = loader
        } else {
            assetURL = source.url
            resourceLoader = nil
        }

        let asset = AVURLAsset(url: assetURL, options: assetOptions)
        if let resourceLoader {
            asset.resourceLoader.setDelegate(
                resourceLoader,
                queue: resourceLoader.delegateQueue
            )
        }

        let contentKeySession: FairPlayContentKeySession?
        if let fairPlay = request.fairPlay {
            let session = FairPlayContentKeySession(
                configuration: fairPlay,
                onDiagnostic: fairPlayDiagnosticHandler
            )
            session.addRecipient(asset)
            contentKeySession = session
        } else {
            contentKeySession = nil
        }

        return PreparedPlaybackItem(
            item: AVPlayerItem(asset: asset),
            authenticatedResourceLoader: resourceLoader,
            fairPlayContentKeySession: contentKeySession
        )
    }
}
