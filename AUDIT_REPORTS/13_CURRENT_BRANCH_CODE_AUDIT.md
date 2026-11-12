# Current branch code audit — 2026-11-12

This is the single current audit for the `ads/discovery` checkout. It is based on the source code in this checkout and the sibling `StreamKitIMA` package. It replaces the older overlapping audit snapshots.

**Inspected revision:** `ce29826` on `ads/discovery`, containing the fullscreen fix, regression assertion, refreshed documentation, and removal of superseded audits. The physical-device test was run against the same local source before it was committed.

## Executive assessment

The SDK has a coherent single-player ownership model: each `StreamPlayerController` owns one AVFoundation engine/player, source generation guards, state streams, client-side ad coordination, and an ad display container. `StreamPlayerSession` is a managed facade that constructs and owns a controller. The optional `StreamKitIMA` package adapts Google IMA without adding it to core dependencies. UIKit is used to bridge AVPlayerLayer, AVKit presentation/PiP, and IMA display requirements; it is required by the current iOS integration choices, though not by AVFoundation playback in isolation.

The fullscreen-exit playback defect is **fixed in commit `ce29826` and verified on device**. The demo lockfile now points to that commit. The current ad paths are structurally implemented, but real IMA ad delivery, all surface combinations, concurrent ads, and HLS interstitial acceptance are not fully verified. One seek/ad-break race and one vendor-log privacy issue remain actionable.

## Fixed and verified

| Item | Status | Evidence and limit |
|---|---|---|
| Playback pauses after AVKit fullscreen exit | **Fixed; device-verified** | `StreamAVPlayerView` observes the exit pause and asks `StreamPlayerController.reconcileTransportIntent()` to restore the latest permitted intent. The focused UI test asserts the returned surface exposes `Pause` after exit. It passed on physical iPhone 12 / iOS 27.0.1 using the same source now in commit `ce29826`. |
| Regression assertion | **Committed** | `testManagedPlayerCanEnterAndExitFullscreen` checks post-exit playback state, not only route return. |
| Core dependency isolation | **Confirmed by source** | Root `Package.swift` has no external package dependencies. Google IMA is in sibling package `StreamKitIMA`. |

No full package suite or full demo UI suite was run for this change. Do not read the focused device result as full-suite or release acceptance.

## Architecture and integration

- **Ownership is clear.** `StreamPlayerSession` creates and owns `StreamPlayerController`; each controller has its own `AVPlayer`, engine, and `ClientSideAdContainer`. Generation/token checks protect replacement and stale ad-session events.
- **The three player surfaces share the playback controller/player.** `StreamVideoView` renders an `AVPlayerLayer`; `StreamAVPlayerView` wraps AVKit; `StreamPlayerView` renders a managed session.
- **UIKit is justified for these surfaces.** UIKit appears at SwiftUI representable boundaries, AVKit delegate APIs, process application state, and IMA's `UIView`/`UIViewController` display context. Removing UIKit would mean changing current product capabilities or maintaining alternate render/presentation implementations. A separate headless target only makes sense if a UIKit-free integration is an actual product goal; the current iOS-only single product is reasonable.
- **Ads follow per-player isolation.** The controller invokes the configured provider for each client-side source load and passes that controller's player and ad container. `GoogleIMAAdProvider.makeSession` returns a new private IMA session with its own loader/manager. Source replacement invalidates its prior session.
- **The host app supplies the ad display host.** `ClientSideAdContainerHost` must be mounted as an overlay alongside the matching surface. `StreamPlayerView(source:)` hides its internally created session; client-side ads with the managed surface need a retained `StreamPlayerSession` and `StreamPlayerView(session:)` so the app can mount that session's container.
- **HLS interstitials are a separate route.** AVFoundation item events are monitored and normalized by core; they do not flow through Google IMA or `ClientSideAdProvider`.
- **The supplied diagram is substantially aligned after two corrections.** Reverse its `StreamPlayerController → Managed StreamPlayerSession` ownership arrow to `StreamPlayerSession → StreamPlayerController`. Show the app explicitly mounting the ad host; player surfaces do not mount it automatically. The refreshed [architecture document](../Documentation/Architecture.md#advertising-architecture) includes these boundaries and the separate HLS route.

## Dependencies and project management

- Core product: iOS 18 minimum, Swift tools 6.4, one library target and one test target, no external dependencies.
- Optional adapter: `StreamKitIMA` depends on StreamKit branch `ads/discovery` and Google IMA from 3.33.0. It is a separate package/product, which keeps the core dependency graph free of the vendor SDK.
- The demo Xcode project uses branch references for StreamKit and StreamKitIMA while its current `Package.resolved` pins StreamKit `ce29826`, StreamKitIMA `f6e8c6b`, and Google IMA `3.34.1`. The lockfile makes this checkout resolution specific, but branch references still float on future updates; release validation should use immutable tags/commits and document the exact adapter/core compatibility pair.
- Demo deployment target is iOS 26.5, above the package's iOS 18 minimum. Current demo builds therefore cannot prove the minimum supported OS.
- The main module is organized by public API, playback core, and internal support. The controller is a substantial orchestration point, but current source does not establish a stable second backend or responsibility boundary that warrants a broad refactor. Keep seams internal unless a concrete second backend or public extension need appears.

## Samples and coverage

- Demo routes now include managed playback, custom controls, advanced AVKit/PiP, live/DVR, multiple players, audio/interruption, bearer authentication, FairPlay, HLS interstitials, and IMA/VAST.
- The IMA route explicitly overlays the appropriate `ClientSideAdContainerHost` for its AVKit and managed-session compositions. That sample is useful for integration guidance but does not establish broad concurrent-player or provider-replacement acceptance.
- Focused fullscreen-exit device test passed as described above. Package and complete UI suites were not rerun for this audit update.
- Ads need explicit tests for no-fill/timeout, failure/fail-open, break pause/resume and user pause, source replacement, simultaneous sessions, each exposed surface, and HLS interstitial transitions.

## Open findings

| Priority | Finding | Code evidence | Recommended next action |
|---|---|---|---|
| P1 | A seek can cross into an ad break after its restriction check. `seek(to:)` and `seekToLiveEdge` validate before awaiting the engine, then only check source and seek generations on completion. Ad-break start increments the playback command generation but does not invalidate the in-flight seek generation. | `Sources/StreamKit/PublicAPI/StreamPlayerController+Commands.swift:238-334`; `Sources/StreamKit/PublicAPI/StreamPlayerController+State.swift:62-87` | Revalidate break restrictions after the awaited engine seek and define how to restore a blocked seek target; add deterministic delayed-engine tests for both seek APIs. |
| P2 | The IMA adapter logs raw vendor error messages. IMA messages can include ad request URLs or response details, while the core failure model intentionally excludes vendor text. | `../../StreamKitIMA/Sources/StreamKitIMA/GoogleIMAAdProvider.swift:238-243` | Keep type/code and safe context only; remove or redact `error.message` before shipping production logs. |
| P2 | Ads have limited acceptance evidence across their public integration paths. Demo routes exist, but a route alone does not establish ad decision, display, break, replacement, multi-player, or failure behavior. | `Examples/StreamKitDemo/StreamKitDemo/IMAVASTDemoView.swift`, `HLSInterstitialDemoView.swift`, `Sources/StreamKit/InternalSupport/ClientSideAdCoordinator.swift` | Add provider-fixture tests for coordinator lifecycle and focused demo/device checks for the IMA and HLS paths, including all surfaces the SDK claims to support. |
| P2 | Minimum deployment is not demonstrated by the demo target. | `Package.swift` vs demo Xcode deployment setting | Add an iOS 18 package build/test lane and record device/runtime coverage separately. |
| P3 | Demo package references float branches. | Demo `.pbxproj` and `Package.resolved` | Pin tagged or immutable revisions in release/CI workflows. |

## Next work

1. Close the post-await ad-restriction seek race with deterministic tests.
2. Remove raw IMA error text from logs.
3. Add IMA/HLS ad lifecycle test coverage and run the ad route on device using a controlled tag/stream.
4. Validate the package at iOS 18 and use immutable dependency revisions for release builds.

## Source map

- Core public API: `Sources/StreamKit/PublicAPI/`
- Playback engine and AVFoundation event bridge: `Sources/StreamKit/PlaybackCore/`
- Client-side ad coordinator: `Sources/StreamKit/InternalSupport/ClientSideAdCoordinator.swift`
- IMA adapter: `../../StreamKitIMA/Sources/StreamKitIMA/GoogleIMAAdProvider.swift`
- Demo ad routes: `Examples/StreamKitDemo/StreamKitDemo/IMAVASTDemoView.swift`, `HLSInterstitialDemoView.swift`
- Current diagrams and integration guidance: `Documentation/Architecture.md`
