//
//  PlaybackEngine.swift
//  StreamKit
//
//  Created by Iheb on 12/10/2026.
//

import Foundation

/// Manages the playback lifecycle for a single player instance.
@MainActor
protocol PlaybackEngine: AnyObject {

    /// Events emitted by the engine during playback.
    var events: AsyncStream<PlaybackEngineEventEnvelope> { get }

    /// Loads a media source and waits until it is ready for playback.
    func load(
        _ source: MediaSource,
        generation: UInt64
    ) async throws

    /// Starts playback.
    func play() async throws

    /// Pauses playback.
    func pause() async

    /// Seeks to a position in seconds.
    func seek(to time: TimeInterval) async throws

    /// Releases the engine's playback resources.
    func shutdown() async
}
