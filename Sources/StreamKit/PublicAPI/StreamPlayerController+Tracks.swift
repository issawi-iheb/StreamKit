import Foundation
import AVFoundation

extension StreamPlayerController {

// MARK: - Media Tracks

    private func validateTrackAccess() throws {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard snapshot.phase != .idle,
              snapshot.phase != .loading,
              snapshot.phase != .failed
        else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "A ready media source is required to access tracks."
            )
        }
    }

    /// Returns the available audio tracks for the current media source.
    public func availableAudioTracks() async throws -> [MediaTrack] {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        let tracks = try await engine.availableAudioTracks()
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }

        return tracks
    }

    /// Returns the available subtitle tracks for the current media source.
    public func availableSubtitleTracks() async throws -> [MediaTrack] {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        let tracks = try await engine.availableSubtitleTracks()
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }

        return tracks
    }

    /// Selects an audio track by its identifier.
    public func selectAudioTrack(id: String) async throws {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        try await engine.selectAudioTrack(id: id)
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }
    }

    /// Selects a subtitle track, or disables subtitles when `id` is `nil`.
    public func selectSubtitleTrack(id: String?) async throws {
        try validateTrackAccess()
        try Task.checkCancellation()
        let generation = loadGeneration

        try await engine.selectSubtitleTrack(id: id)
        try Task.checkCancellation()

        guard !isShutdown, loadGeneration == generation else {
            throw CancellationError()
        }
    }
}
