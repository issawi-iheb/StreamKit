# Testing and validation plan

## Current branch addendum — 2026-10-28

The focused demo validation for revision `81496be` is recorded in [12_CURRENT_STATE_AND_DEMO_UX.md](12_CURRENT_STATE_AND_DEMO_UX.md). `StreamKitDemoUITests.testManagedPlayerCanEnterAndExitFullscreen` passed on the iPhone Duo / iOS 27.1 Simulator, and the simulator `build-for-testing` succeeded. The full Swift package suite was not rerun for this documentation/demo revision; the 115-test result below is from 2026-10-21. Physical-device PiP and restoration, broad device/layout coverage, and minimum-iOS compilation remain unverified.

## Existing coverage inventory

Swift Testing is used in `Tests/StreamKitTests`; the current package suite contains **115 passing tests in 11 suites**. Coverage includes snapshot/error/value types; broadcaster normal delivery; controller loading, stale completions, shutdown, playback intent/phase, interruption, track forwarding, rates, command supersession, and multiple instances; AVFoundation engine shutdown/insecure FairPlay/instance isolation; authenticated loader URL/range/token helpers; FairPlay key-exchange provider orchestration. Demo XCTest/UI tests and a GitHub Actions workflow exist. No dedicated PiP-specific test suite or external consumer integration target is present. The latest UI test attempt did not complete; see validation below.

## Validation attempted

### Latest implementation validation — 2026-10-21

- `rtk swift test` — **passed: 115 tests in 11 suites** (macOS 14.0).
- Generic iOS demo build with `xcodebuild ... -destination 'generic/platform=iOS' ... CODE_SIGNING_ALLOWED=NO -quiet build` — **passed**.
- iOS Simulator `build-for-testing` for app, unit-test, and UI-test targets — **passed**.
- iPhone 17 Pro / iOS 26.5 Simulator demo unit tests — **passed: 4 tests**.
- Demo UI tests — **no result**. The run stalled on repeated Xcode debugger-version lookup warnings and was interrupted. Do not count this as a pass or failure.
- Physical-device PiP and the reported standalone player video behavior — **not revalidated in this pass**.
- iOS 16 minimum-deployment build — **not run**; it was explicitly excluded from this change set.

These results supersede older local validation counts below only for the listed checks. Historical audit attempts remain as recorded.

- Historical attempts on the earlier audited checkout: `rtk swift test` was blocked by a sandboxed Swift module-cache write; retrying with a scratch path failed during sandbox setup. Those attempts are superseded by the successful latest package run above.
- The 2026-10-21 UI-test attempt stalled on Xcode debugger-version lookup warnings and was interrupted; do not interpret it as a test failure or pass.

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
