//
//  StreamKitDemoTests.swift
//  StreamKitDemoTests
//
//  Created by Iheb on 13/10/2026.
//

import Testing
import StreamKit
@testable import StreamKitDemo

struct StreamKitDemoTests {

    @MainActor
    @Test("A new source clears cached tracks and ignores a late result from the old source")
    func resetsTracksForNewSourceRevision() {
        let state = PlayerTrackState()
        let firstRevision = state.sourceRevision
        let firstTrack = MediaTrack(
            id: "audio:1",
            type: .audio,
            name: "English",
            languageCode: "en"
        )
        state.applyTracks(audio: [firstTrack], subtitles: [], for: firstRevision)

        #expect(state.hasLoadedTracks)
        #expect(state.audioTracks == [firstTrack])

        state.prepareForNewSource()
        let secondRevision = state.sourceRevision

        #expect(secondRevision != firstRevision)
        #expect(state.audioTracks.isEmpty)
        #expect(state.subtitleTracks.isEmpty)
        #expect(!state.hasLoadedTracks)

        state.applyTracks(audio: [firstTrack], subtitles: [], for: firstRevision)
        #expect(state.audioTracks.isEmpty)
        #expect(!state.hasLoadedTracks)

        let secondTrack = MediaTrack(
            id: "audio:2",
            type: .audio,
            name: "French",
            languageCode: "fr"
        )
        state.applyTracks(audio: [secondTrack], subtitles: [], for: secondRevision)
        #expect(state.audioTracks == [secondTrack])
        #expect(state.hasLoadedTracks)
    }

}
