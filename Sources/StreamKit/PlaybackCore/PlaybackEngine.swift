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
    func setPlaybackRate(_ rate: Float) async throws

    /// Seeks to a position in seconds.
    func seek(to time: TimeInterval) async throws

    /// Seeks to the live edge or a finite offset behind it.
    func seekToLiveEdge(offsetFromLive: TimeInterval) async throws

    /// Releases the engine's playback resources.
    func shutdown() async
    
    func availableAudioTracks() async throws -> [MediaTrack]

    func availableSubtitleTracks() async throws -> [MediaTrack]

    func selectAudioTrack(id: String) async throws

    func selectSubtitleTrack(id: String?) async throws
}
