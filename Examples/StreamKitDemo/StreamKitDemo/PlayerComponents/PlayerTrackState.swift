//
//  PlayerTrackState.swift
//  StreamKitDemo
//
//  Created by Iheb on 14/10/2026.
//

import SwiftUI
import StreamKit

@MainActor
@Observable
final class PlayerTrackState {
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []

    private(set) var selectedAudioID: String?
    private(set) var selectedSubtitleID: String?

    private(set) var isLoading = false
    var errorMessage: String?

    private(set) var hasLoadedTracks = false
    private(set) var sourceRevision = UUID()

    func prepareForNewSource() {
        sourceRevision = UUID()
        audioTracks = []
        subtitleTracks = []
        selectedAudioID = nil
        selectedSubtitleID = nil
        hasLoadedTracks = false
        isLoading = false
        errorMessage = nil
    }

    func applyTracks(
        audio: [MediaTrack],
        subtitles: [MediaTrack],
        for revision: UUID
    ) {
        guard revision == sourceRevision else { return }
        audioTracks = audio
        subtitleTracks = subtitles
        hasLoadedTracks = true
    }

    var hasAudioTracks: Bool {
        !audioTracks.isEmpty
    }

    var hasSubtitleTracks: Bool {
        !subtitleTracks.isEmpty
    }

    var selectedAudioName: String {
        audioTracks.first {
            $0.id == selectedAudioID
        }?.name ?? "Audio"
    }

    var selectedSubtitleName: String {
        guard let selectedSubtitleID else {
            return "Off"
        }

        return subtitleTracks.first {
            $0.id == selectedSubtitleID
        }?.name ?? "Subtitles"
    }

    func load(using controller: StreamPlayerController) async {
        guard !hasLoadedTracks, !isLoading else {
            return
        }

        let revision = sourceRevision
        isLoading = true
        errorMessage = nil

        defer {
            if sourceRevision == revision {
                isLoading = false
            }
        }

        do {
            async let audioResult = controller.availableAudioTracks()
            async let subtitleResult = controller.availableSubtitleTracks()

            let loadedAudio = try await audioResult
            let loadedSubtitles = try await subtitleResult

            guard !Task.isCancelled,
                  sourceRevision == revision
            else {
                return
            }

            applyTracks(
                audio: loadedAudio,
                subtitles: loadedSubtitles,
                for: revision
            )
        } catch {
            guard !Task.isCancelled,
                  sourceRevision == revision
            else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    func selectAudio(
        _ id: String,
        using controller: StreamPlayerController
    ) async {
        guard !isLoading else {
            return
        }

        errorMessage = nil

        do {
            try await controller.selectAudioTrack(id: id)
            selectedAudioID = id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSubtitle(
        _ id: String?,
        using controller: StreamPlayerController
    ) async {
        guard !isLoading else {
            return
        }

        errorMessage = nil

        do {
            try await controller.selectSubtitleTrack(id: id)
            selectedSubtitleID = id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
