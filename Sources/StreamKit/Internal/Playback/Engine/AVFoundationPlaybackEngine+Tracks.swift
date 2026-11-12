import AVFoundation
import Foundation

extension AVFoundationPlaybackEngine {

// MARK: - Media Tracks

    func availableAudioTracks() async throws -> [MediaTrack] {
        try Task.checkCancellation()
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .audible)

        try Task.checkCancellation()
        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            return []
        }

        return group.options.enumerated().map { index, option in
            MediaTrack(
                id: "audio:\(index)",
                type: .audio,
                name: option.displayName,
                languageCode: option.locale?.identifier
            )
        }
    }

    func availableSubtitleTracks() async throws -> [MediaTrack] {
        try Task.checkCancellation()
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .legible)

        try Task.checkCancellation()
        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            return []
        }

        return group.options.enumerated().map { index, option in
            MediaTrack(
                id: "subtitle:\(index)",
                type: .subtitle,
                name: option.displayName,
                languageCode: option.locale?.identifier
            )
        }
    }

    func selectAudioTrack(id: String) async throws {
        try Task.checkCancellation()
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .audible)

        try Task.checkCancellation()
        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            throw invalidTrackFailure("No audio tracks are available.")
        }

        guard id.hasPrefix("audio:"),
              let index = Int(id.dropFirst("audio:".count)),
              group.options.indices.contains(index) else {
            throw invalidTrackFailure(
                "The requested audio track is unavailable."
            )
        }

        item.select(group.options[index], in: group)
    }

    func selectSubtitleTrack(id: String?) async throws {
        try Task.checkCancellation()
        let item = try currentTrackItem()
        let generation = loadGeneration
        let asset = item.asset

        let group = try await asset.loadMediaSelectionGroup(for: .legible)

        try Task.checkCancellation()
        guard isCurrentItem(item, generation: generation) else {
            throw CancellationError()
        }

        guard let group else {
            if id == nil {
                return
            }

            throw invalidTrackFailure("No subtitle tracks are available.")
        }

        guard let id else {
            item.select(nil, in: group)
            return
        }

        guard id.hasPrefix("subtitle:"),
              let index = Int(id.dropFirst("subtitle:".count)),
              group.options.indices.contains(index) else {
            throw invalidTrackFailure(
                "The requested subtitle track is unavailable."
            )
        }

        item.select(group.options[index], in: group)
    }
    private func currentTrackItem() throws -> AVPlayerItem {
        guard !isShutdown else {
            throw shutdownFailure()
        }

        guard let item = player.currentItem,
              observedItem === item else {
            throw PlaybackFailure(
                code: .invalidSource,
                message: "Load a media source before accessing its tracks."
            )
        }

        return item
    }

    private func invalidTrackFailure(_ message: String) -> PlaybackFailure {
        PlaybackFailure(
            code: .invalidSource,
            message: message
        )
    }
}
