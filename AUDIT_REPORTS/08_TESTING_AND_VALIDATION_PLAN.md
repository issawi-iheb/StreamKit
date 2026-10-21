# Testing and validation plan

## Existing coverage inventory

Swift Testing is used in `Tests/StreamKitTests` (9 test files; observed `@Test` counts total 111). Coverage includes snapshot/error/value types; broadcaster normal delivery; controller loading, stale completions, shutdown, playback intent/phase, interruption, track forwarding, rates and multiple instances; AVFoundation engine shutdown/insecure FairPlay/instance isolation; authenticated loader URL/range/token helpers; FairPlay key-exchange provider orchestration. Demo XCTest/UI tests exist. No PiP-specific test file, fullscreen test, external consumer integration target, or CI workflow was found.

## Validation attempted

- `rtk swift test` — **not run to completion**. SwiftPM manifest compilation failed because sandbox denied writing `/Users/ihebI/.cache/clang/ModuleCache` (`Operation not permitted`).
- `CLANG_MODULE_CACHE_PATH=/private/tmp/streamkit-clang-cache rtk swift test --scratch-path /private/tmp/streamkit-swift-build` — **not run to completion**. SwiftPM then failed during sandbox setup (`sandbox_apply: Operation not permitted`).
- No `xcodebuild`, simulator, hardware, DRM endpoint, PiP, or performance run was performed. No test pass is claimed.

Run when host permissions permit:

```sh
swift test
swift build -c release
xcodebuild -project Examples/StreamKitDemo/StreamKitDemo.xcodeproj -scheme StreamKitDemo -destination 'platform=iOS Simulator,name=<available simulator>' build
```

Use a host writable Swift module cache. Verify available simulator names first; the demo is configured for iOS 26.5, and package floor is iOS 16, so maintain a separate minimum-target consumer build.

## Proposed tests

| Test | Exact target | Setup / expected | Protects | Platform |
|---|---|---|---|---|
| `overlappingSeeksPublishOnlyCurrentSeek` | `Tests/StreamKitTests/StreamPlayerControllerTests.swift` | Suspend two seeks, finish out of order; only documented winning request matches observed playhead | PLAY-001 | macOS mock + iOS device for AVPlayer semantics |
| `loadHandleCancellationContract` | `Tests/StreamKitTests/StreamPlayerControllerTests.swift` or new `LoadHandleTests.swift` | Two waiters share handle; cancel and assert explicitly documented shared/local behavior | CONC-001 | macOS |
| `replacementWhileSPCRequestPendingDoesNotCompleteStaleRequest` | new `Tests/StreamKitTests/FairPlayContentKeySessionTests.swift` with injected callback seam | Replace source before SPC callback; cancellation once, late callback ignored | DRM-002 | deterministic seam macOS; real key path device |
| `twoFairPlayPlayersRemainIsolated` | `Tests/StreamKitTests/AVFoundationPlaybackEngineTests.swift` + integration fixture | Give each player separate protected asset/session, stop one | DRM-001 | physical iOS + external DRM fixture |
| `piPRestorationCompletesOnce` | new `Tests/StreamKitTests/PictureInPictureControllerTests.swift` for completion gate; demo UI test for AVKit | Invoke restoration twice; gate only completes once | PIP-001 | gate macOS where available; PiP device |
| `customPiPSurvivesSourceViewRemoval` | `Examples/StreamKitDemo/StreamKitDemoUITests/StreamKitDemoUITests.swift` | Start PiP, remove inline presentation, restore UI | PIP-001 | physical iOS device |
| `redirectDoesNotForwardBearerToUntrustedHost` | `Tests/StreamKitTests/AuthenticatedMediaResourceLoaderTests.swift` | Mock redirect to untrusted/HTTP URL; request fails or credentials are stripped per policy | SEC-001 | macOS URL loading mock |
| `swiftUIViewRebindsPlayerAfterControllerChange` | `Examples/StreamKitDemo/StreamKitDemoUITests/StreamKitDemoUITests.swift` | Recreate representable with second controller; verify rendering follows it | VIDEO-001 | iOS simulator |
| `liveSeekableWindowUpdates` | new AVFoundation integration target | Sliding live HLS, seek in/outside current range; API behavior documented | PLAY-002 | device/network fixture |
| `externalPackageConsumerCompiles` | new consumer target or CI fixture | Import only product; compile SwiftUI and UIKit APIs | API-001 | macOS package build + iOS simulator |

## Acceptance by priority

- **P0:** none assigned; do not create a P0 for unverified risks.
- **P1:** PLAY-001 ordering behavior specified and tested; DRM-001/002 provider path tested against approved fixture; PIP-001 device lifecycle passes.
- **P2:** CI runs package tests and minimum-iOS consumer compile; SEC-001 redirect matrix passes; API-001 consumer integration documentation is accurate.
- **P3:** live seekable-range model only after requirements and fixture exist; track persistence identifiers only with concrete consumer need.
