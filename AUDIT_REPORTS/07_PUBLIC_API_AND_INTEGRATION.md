# Public API and integration

## Implementation follow-up — 2026-10-21

README integration guidance now shows snapshot consumption in a `@MainActor` task and explicitly says that `AsyncStream` does not isolate its consumer. It also documents that removing `StreamVideoView` does not stop the controller, describes retaining the playback/PiP owners through PiP, and provides a host-owned audio-focus example. The example serializes app play requests at the owner boundary; StreamKit still does not provide shared multi-controller focus arbitration.

The standalone demo now demonstrates route-scoped playback-session ownership through `StandalonePlayerDemoSession`, including retaining the controller and PiP controller above the route and performing shutdown after route exit and PiP stop. The new session is compiled but not directly unit-tested; device PiP lifecycle acceptance remains open.

## Consumer shape

```swift
import StreamKit

@MainActor
final class PlaybackModel: ObservableObject {
    let player = StreamPlayerController(configuration: .init(autoplay: false))
    private var observation: Task<Void, Never>?

    func observe() {
        observation = Task {
            for await snapshot in player.snapshots {
                // Update app-owned UI state.
                print(snapshot.phase, snapshot.currentTime)
            }
        }
    }

    func open(_ url: URL) async throws {
        let load = player.load(MediaSource(url: url))
        try await load.waitUntilReady()
    }

    func close() async {
        observation?.cancel()
        await player.shutdown()
    }
}
```

Views are presented with `StreamVideoView(controller:)` or the AVKit adapter. `shutdown()` is explicit, async and idempotent; view removal alone does not shut down playback. Host app configures `AVAudioSession`, audio background mode, PiP entitlement/settings as applicable, and owns SwiftUI/UIKit presentation and orientation. FairPlay provider and credentials are app-owned.

## API assessment

The controller is `@MainActor`, has an injectable internal engine seam, returns a `LoadHandle`, exposes immutable snapshot and independent `AsyncStream`s, and normalizes failures. `MediaSource` and configuration are `Sendable`. Track APIs are explicit. A clear migration advantage is that app control does not require access to AVPlayer directly, though the rendering bridge internally obtains it.

**API-001 — Medium, Enhancement:** public lifecycle is present but the rules should be consolidated into package API docs: who calls shutdown, whether canceling a `LoadHandle` cancels the shared readiness task, snapshot stream buffering semantics, safe ownership for multiple observers, controller retention during PiP, and host audio-session duties. Locations: `StreamPlayerController.swift:25-33, 106-110, 613-641`; `LoadHandle.swift:10-25`; docs `README.md`. Add an API integration test target/sample that compiles only against the package product, not `@testable` internals.

**API-002 — Low, Enhancement:** public track IDs are stringly typed and positional; document item-scoped lifetime (`MediaTrack.swift:7-10`). Do not change to a new public ID until persistence/reordering use case is concrete.

No evidence supports exposing raw `AVPlayer` as a public API, owning global audio-session policy, or introducing a dependency-injection framework. The `renderingPlayer` internal concrete cast is a limited extension seam (ARCH-001), and changing it is only justified if a second engine/render backend is planned.

## Multi-instance integration

Create one `StreamPlayerController` per independent playback session. Share neither a PiP coordinator nor state store across unrelated players. A host may present two inline views simultaneously; its audio-session and audio-focus policy determines whether both should audibly play. Each engine owns a distinct AVPlayer. Tests establish independent mock controllers and independent engine player identities; DRM concurrency remains to be validated.

## Compatibility

Package deployment target is iOS 16. APIs guarded with `#available` should be tested at the deployment floor. No library-evolution setting or semantic-version compatibility test exists. Before release, document API stability policy and compile an external sample against tagged package product. Adding cases to public non-frozen enums can be source-breaking for exhaustive switches; release strategy should account for it.
