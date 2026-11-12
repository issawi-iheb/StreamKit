//
//  MediaAdMode.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import Foundation

/// Defines how advertising is delivered for a media source.
public enum MediaAdMode: Equatable, Sendable {

    /// Advertising is scheduled by the HLS presentation itself.
    case hlsInterstitials

    /// Advertising is managed by an external client-side provider.
    case clientSide(ClientSideAdConfiguration)
}

/// Describes the request used to retrieve client-side advertisements.
public struct ClientSideAdRequest: Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {

    /// The VAST or VMAP advertising tag URL.
    public let tagURL: URL

    public init(tagURL: URL) {
        self.tagURL = tagURL
    }

    /// Deliberately redacts the advertising URL because it may contain
    /// targeting parameters or other sensitive information.
    public var description: String {
        "ClientSideAdRequest(<redacted>)"
    }

    public var debugDescription: String {
        description
    }
}

/// Configuration for a client-side advertising provider.
///
/// Each configuration has its own identity. Two configurations compare
/// equal only when they use the same request, timeout and provider instance.
public struct ClientSideAdConfiguration: Equatable, Sendable {

    public let request: ClientSideAdRequest
    public let provider: any ClientSideAdProvider
    public let initialDecisionTimeout: TimeInterval

    public init(
        request: ClientSideAdRequest,
        provider: any ClientSideAdProvider,
        initialDecisionTimeout: TimeInterval = 3
    ) {
        precondition(
            initialDecisionTimeout.isFinite && initialDecisionTimeout > 0,
            "The initial ad decision timeout must be greater than zero."
        )

        self.request = request
        self.provider = provider
        self.initialDecisionTimeout = initialDecisionTimeout
    }

    public static func == (
        lhs: ClientSideAdConfiguration,
        rhs: ClientSideAdConfiguration
    ) -> Bool {
        lhs.request == rhs.request
            && lhs.initialDecisionTimeout == rhs.initialDecisionTimeout
            && (lhs.provider as AnyObject) === (rhs.provider as AnyObject)
    }
}
