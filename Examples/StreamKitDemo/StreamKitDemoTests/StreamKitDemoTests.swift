//
//  StreamKitDemoTests.swift
//  StreamKitDemoTests
//
//  Created by Iheb on 13/10/2026.
//

import Foundation
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

    @MainActor
    @Test("PiP restoration completes only after the player route appears")
    func restorationWaitsForPlayerRoute() {
        let coordinator = PresentationDemoRestorationCoordinator()
        let completion = RestorationCompletionRecorder()
        var routeRequestCount = 0
        coordinator.requestPlayerRoute = { routeRequestCount += 1 }

        coordinator.restorePlayerInterface { completion.record($0) }

        #expect(routeRequestCount == 1)
        #expect(completion.value == nil)

        coordinator.playerInterfaceDidAppear()

        #expect(coordinator.isPlayerInterfaceAvailable)
        #expect(completion.value == true)

        coordinator.playerInterfaceDidDisappear()
        #expect(!coordinator.isPlayerInterfaceAvailable)
    }

    @MainActor
    @Test("PiP restoration reports failure if the host cannot present the player route")
    func restorationReportsUnavailableRoute() {
        let coordinator = PresentationDemoRestorationCoordinator()
        let completion = RestorationCompletionRecorder()

        coordinator.restorePlayerInterface { completion.record($0) }

        #expect(completion.value == false)
    }

    @MainActor
    @Test("The root presentation session retains its playback owners across route removal")
    func presentationSessionRetainsOwners() {
        let session = PresentationDemoSession()
        let playerController = session.playerController
        let pipController = session.pictureInPictureController

        session.isPlayerPresented = true
        session.playerInterfaceDidAppear()
        session.playerInterfaceDidDisappear()
        session.isPlayerPresented = false

        #expect(session.playerController === playerController)
        #expect(session.pictureInPictureController === pipController)
    }

}

private final class RestorationCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool?

    var value: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func record(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        storedValue = value
    }
}
