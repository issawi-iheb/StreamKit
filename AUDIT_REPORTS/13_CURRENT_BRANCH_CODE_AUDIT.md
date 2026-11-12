# Current branch code audit — 2026-11-12

This is the single current audit for the `ads/discovery` checkout. It is based on the source code in this checkout and the sibling `StreamKitIMA` package. It replaces the older overlapping audit snapshots.

**Inspected revision:** `43cdcee` on `ads/discovery`, plus the local UI test changes described below. The fullscreen fix was device-tested on iPhone 12 / iOS 27.0.1. Focused package and public-sample IMA/HLS device checks pass; the demo test build resolved StreamKit `935cc42` and StreamKitIMA `f6e8c6b` from `Package.resolved`.

## Executive assessment

The SDK has a coherent single-player ownership model: each `StreamPlayerController` owns one AVFoundation engine/player, source generation guards, state streams, client-side ad coordination, and an ad display container. `StreamPlayerSession` is a managed facade that constructs and owns a controller. The optional `StreamKitIMA` package adapts Google IMA without adding it to core dependencies. UIKit is used to bridge AVPlayerLayer, AVKit presentation/PiP, and IMA display requirements; it is required by the current iOS integration choices, though not by AVFoundation playback in isolation.

The fullscreen-exit playback defect is **fixed and verified on device**. The demo lockfile pins the corresponding core revision. The post-await seek/ad-break race restores the prior position and is covered by delayed-engine tests. The IMA adapter no longer logs raw vendor error messages. Public Google IMA and Apple HLS sample flows pass focused device checks across Managed, Advanced, and AVKit surfaces. This is sample-level acceptance on one device, not production-tag or multi-OS acceptance.

## Fixed and verified

| Item | Status | Evidence and limit |
|---|---|---|
| Playback pauses after AVKit fullscreen exit | **Fixed; device-verified** | `StreamAVPlayerView` observes the exit pause and asks `StreamPlayerController.reconcileTransportIntent()` to restore the latest permitted intent. The focused UI test asserts the returned surface exposes `Pause` after exit. It passed on physical iPhone 12 / iOS 27.0.1 using the same source now in commit `935cc42`. |
| Regression assertion | **Committed** | `testManagedPlayerCanEnterAndExitFullscreen` checks post-exit playback state, not only route return. |
| Core dependency isolation | **Confirmed by source** | Root `Package.swift` has no external package dependencies. Google IMA is in sibling package `StreamKitIMA`. |
| Seek/ad-break race | **Fixed; package-tested** | Delayed-engine tests cover `seek(to:)` and `seekToLiveEdge` when a client-side break begins during the engine await; both restore the starting position and return `.adPlaybackRestricted`. |
| Raw IMA error logging | **Fixed by code** | `GoogleIMAAdProvider` no longer prints `error.message`; type and numeric code remain available for diagnostics. |
| IMA/HLS sample surfaces | **Device-checked; limited scope** | Focused UI tests passed public Google VAST and Apple HLS sample ad breaks across Managed, Advanced, and AVKit on iPhone 12 / iOS 27.0.1. The HLS test captured screenshots for each surface. Xcode resolved StreamKit `935cc42`, StreamKitIMA `f6e8c6b`, and Google IMA `3.34.1`; production tags and other OS/device combinations remain untested. |

No full package suite or full demo UI suite was run for the fullscreen fix. Do not read the focused device result as full-suite or release acceptance.

## Architecture and integration

- **Ownership is clear.** `StreamPlayerSession` creates and owns `StreamPlayerController`; each controller has its own `AVPlayer`, engine, and `ClientSideAdContainer`. Generation/token checks protect replacement and stale ad-session events.
- **The three player surfaces share the playback controller/player.** `StreamVideoView` renders an `AVPlayerLayer`; `StreamAVPlayerView` wraps AVKit; `StreamPlayerView` renders a managed session.
- **UIKit is justified for these surfaces.** UIKit appears at SwiftUI representable boundaries, AVKit delegate APIs, process application state, and IMA's `UIView`/`UIViewController` display context. Removing UIKit would mean changing current product capabilities or maintaining alternate render/presentation implementations. A separate headless target only makes sense if a UIKit-free integration is an actual product goal; the current iOS-only single product is reasonable.
- **Ads follow per-player isolation.** The controller invokes the configured provider for each client-side source load and passes that controller's player and ad container. `GoogleIMAAdProvider.makeSession` returns a new private IMA session with its own loader/manager. Source replacement invalidates its prior session.
- **Managed ads mount their display host automatically.** Both `StreamPlayerView` initializers add `ClientSideAdContainerHost` when the session source uses client-side ads. Direct `StreamVideoView` or `StreamAVPlayerView` compositions still require the host app to mount the matching container alongside that player.
- **HLS interstitials are a separate route.** AVFoundation item events are monitored and normalized by core; they do not flow through Google IMA or `ClientSideAdProvider`.
- **The supplied diagram is substantially aligned after two corrections.** Reverse its `StreamPlayerController → Managed StreamPlayerSession` ownership arrow to `StreamPlayerSession → StreamPlayerController`. Managed `StreamPlayerView` mounts the ad host internally; the app mounts it explicitly only for custom surface compositions. The refreshed [architecture document](../Documentation/Architecture.md#advertising-architecture) includes these boundaries and the separate HLS route.

## Dependencies and project management

- Core product: iOS 18 minimum, Swift tools 6.4, one library target and one test target, no external dependencies.
- Optional adapter: `StreamKitIMA` depends on StreamKit branch `ads/discovery` and Google IMA from 3.33.0. It is a separate package/product, which keeps the core dependency graph free of the vendor SDK.
- The demo Xcode project uses branch references for StreamKit and StreamKitIMA while its current `Package.resolved` pins StreamKit `935cc42`, StreamKitIMA `f6e8c6b`, and Google IMA `3.34.1`. The lockfile makes this checkout resolution specific, but branch references still float on future updates; release validation should use immutable tags/commits and document the exact adapter/core compatibility pair.
- Demo deployment target is iOS 26.5, above the package's iOS 18 minimum. Current demo builds therefore cannot prove the minimum supported OS.
- The main module keeps public declarations under `Sources/StreamKit/PublicAPI/` and internal implementations under `Sources/StreamKit/Internal/`, grouped by playback, media, advertising, diagnostics, and presentation. The controller is a substantial orchestration point, but current source does not establish a stable second backend or responsibility boundary that warrants a broad refactor. Keep seams internal unless a concrete second backend or public extension need appears.

## Samples and coverage

- Demo routes now include managed playback, custom controls, advanced AVKit/PiP, live/DVR, multiple players, audio/interruption, bearer authentication, FairPlay, HLS interstitials, and IMA/VAST.
- The IMA route now relies on `StreamPlayerView` to mount its container for the managed surface and explicitly mounts it for the AVKit and custom-control surfaces. That sample is useful for integration guidance but does not establish broad concurrent-player or provider-replacement acceptance.
- Focused fullscreen-exit device test passed as described above. Package and complete UI suites were not rerun for this audit update.
- Focused package tests passed: 26 tests across `PlaybackAdBreakTests`, `ClientSideAdIntegrationTests`, and `ClientSideAdCoordinatorTests`. New lifecycle assertions cover independent sessions/containers, replacement invalidation, break start/end, user pause, and shutdown; existing coordinator tests cover initial-decision timeout and session failure. Focused IMA/HLS UI tests passed on iPhone 12 across all three surfaces. The app test uses the lockfile versions noted above.

## Open findings

| Priority | Finding | Code evidence | Recommended next action |
|---|---|---|---|
| P2 | Ad acceptance remains limited to public samples and one physical device. No-fill/customer-tag behavior, provider-backed failures, and supported-OS/device combinations are not established by the sample UI run. | `Examples/StreamKitDemo/StreamKitDemo/IMAVASTDemoView.swift`, `HLSInterstitialDemoView.swift`, `Sources/StreamKit/Internal/Advertising/ClientSideAdCoordinator.swift` | Validate controlled no-fill/failure tags and repeat surface checks on supported OS/device combinations; keep sample verification distinct from production acceptance. |
| P2 | Minimum deployment is not demonstrated by the demo target. | `Package.swift` vs demo Xcode deployment setting | Add an iOS 18 package build/test lane and record device/runtime coverage separately. |
| P3 | Demo package references float branches. | Demo `.pbxproj` and `Package.resolved` | Pin tagged or immutable revisions in release/CI workflows. |

## Next work

1. Validate no-fill and provider-failure behavior with controlled IMA tags, including fail-open behavior.
2. Repeat IMA/HLS surface checks on supported OS/device combinations and test HLS break transitions.
3. Validate the package at iOS 18 and use immutable dependency revisions for release builds.

## Source map

- Public SDK surface: `Sources/StreamKit/PublicAPI/`
- Playback engine and AVFoundation event bridge: `Sources/StreamKit/Internal/Playback/Engine/`
- Client-side ad coordinator: `Sources/StreamKit/Internal/Advertising/ClientSideAdCoordinator.swift`
- IMA adapter: `../../StreamKitIMA/Sources/StreamKitIMA/GoogleIMAAdProvider.swift`
- Demo ad routes: `Examples/StreamKitDemo/StreamKitDemo/IMAVASTDemoView.swift`, `HLSInterstitialDemoView.swift`
- Current diagrams and integration guidance: `Documentation/Architecture.md`
