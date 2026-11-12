import Foundation
import Testing
@testable import StreamKit

@Suite("Audio interruption coordinator")
struct AudioInterruptionCoordinatorTests {

    @Test("Resumes only when playback was active and the system allows it")
    func resumesWhenPolicyAllows() {
        var coordinator = AudioInterruptionCoordinator()
        let playing = PlaybackSnapshot(phase: .playing, intent: .play)

        let firstBeganEvent = coordinator.interruptionBegan(for: playing)
        let duplicateBeganEvent = coordinator.interruptionBegan(for: playing)
        let shouldResume = coordinator.interruptionEnded(
            systemAllowsResume: true,
            automaticallyResumes: true,
            snapshot: playing
        )

        #expect(firstBeganEvent)
        #expect(!duplicateBeganEvent)
        #expect(shouldResume)
        #expect(coordinator.allowsPlaybackStart)
    }

    @Test("Requires explicit play when automatic resumption is denied")
    func requiresExplicitPlayWhenDenied() {
        var coordinator = AudioInterruptionCoordinator()
        let playing = PlaybackSnapshot(phase: .playing, intent: .play)

        _ = coordinator.interruptionBegan(for: playing)
        let shouldResume = coordinator.interruptionEnded(
            systemAllowsResume: false,
            automaticallyResumes: true,
            snapshot: playing
        )
        #expect(!shouldResume)
        #expect(!coordinator.allowsPlaybackStart)

        coordinator.playbackIntentRequested()
        #expect(coordinator.allowsPlaybackStart)
    }

    @Test("An interruption during loading can resume after load readiness")
    func recordsAutoplayDuringLoading() {
        var coordinator = AudioInterruptionCoordinator()
        let loading = PlaybackSnapshot(phase: .loading, intent: .play)

        _ = coordinator.interruptionBegan(for: loading)
        let shouldResumeAfterLoad = coordinator.interruptionEnded(
            systemAllowsResume: true,
            automaticallyResumes: true,
            snapshot: loading
        )
        #expect(shouldResumeAfterLoad)
        #expect(coordinator.allowsPlaybackStart)
    }
}
