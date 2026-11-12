//
//  ClientSideAdProvider.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import AVFoundation
import Foundation

/// Context supplied by StreamKit when creating an ad session.
///
/// The container belongs to the player instance, so simultaneous players
/// can host independent ad sessions.
@MainActor
public struct ClientSideAdSessionContext {

    #if os(iOS)
    public let container: ClientSideAdContainer
    #endif

    public let contentPlayer: AVPlayer?

    #if os(iOS)
    public init(
        container: ClientSideAdContainer,
        contentPlayer: AVPlayer?
    ) {
        self.container = container
        self.contentPlayer = contentPlayer
    }
    #else
    public init(contentPlayer: AVPlayer?) {
        self.contentPlayer = contentPlayer
    }
    #endif
}

/// Creates client-side advertising sessions for StreamKit.
///
/// Implementations adapt a specific advertising SDK to StreamKit's
/// provider-neutral session contract.
@MainActor
public protocol ClientSideAdProvider: AnyObject, Sendable {
    func makeSession(
        for request: ClientSideAdRequest,
        context: ClientSideAdSessionContext
    ) throws -> any ClientSideAdSession
}
