# StreamKit Production Readiness Audit Report

## Executive Summary

This living report tracks StreamKit's production-readiness review against Phase 1 of the roadmap. The original findings below reflect earlier revisions; the later follow-up is authoritative when statuses or verification counts differ.

**Current status (2026-10-20):** StreamKit has a sound playback foundation. The current worktree passes 95 Swift tests across 11 suites, and the demo plus UI test bundle compile for a generic iOS Simulator destination. The user confirmed basic demo playback, Siri interruption/resume on an iPhone running iOS 26.5, and successful Axinom public FairPlay playback: the license service returned HTTP 200, AVFoundation accepted the key response, and playback reached `.playing`. This verifies the demo's public test integration, not a production provider or the user's own protected origin. The UI test bundle was compiled but not run because CoreSimulator services are unavailable. Hosted CI run [38916346546](https://github.com/issawi-iheb/StreamKit/actions/runs/38916346546) succeeded on an earlier revision and does not cover the current worktree. The package is **not yet production-ready**: renewal, entitlement failure, cancellation, source replacement, other audio-session scenarios, and broader origin/device coverage remain to be validated.

## Original Audit Scope and Limitations (Historical Snapshot)

### Scope
The audit covered the StreamKit SDK source code located in `/StreamKit/Sources/StreamKit/` including:
- PlaybackCore module (AVFoundationPlaybackEngine, PlaybackEngine protocols, events, failures, phases, snapshots, snapshot broadcaster)
- Public API module (StreamPlayerController, MediaSource, MediaTrack, PlayerConfiguration, LoadHandle, StreamVideoView)
- Associated unit tests in `/StreamKit/Tests/StreamKitTests/`
- Documentation files: README.md, Architecture.md, MultiPlayerArchitecture.md, PlaybackStateMachine.md, ROADMAP.md

### Limitations
- The audit was read-only; no modifications were made to the codebase
- Testing was limited to the existing unit test suite; no additional test cases were created
- Platform verification was limited to test execution results; no manual device/simulator testing was performed
- The audit focused on the source code and documentation as of commit 4451e78
- While Swift concurrency correctness was analyzed, formal verification of absence of data races was not performed

## Original Commands and Results (Historical Snapshot)

1. **Test Suite Execution**
   - Command: `cd /Users/iheb/Documents/StreamKit && swift test`
   - Result: All 61 tests passed in 9 test suites
   - Test Suites: Playback State Model, PlaybackPhase, SnapshotBroadcaster, StreamPlayerController, PlaybackSnapshot, AVFoundation Playback Engine, PlaybackIntent, MediaSource, PlaybackFailure
   - Execution Time: ~0.008 seconds

2. **Code Inspection**
   - Read all source files in StreamKit/Sources/StreamKit/
   - Read all documentation files
   - Read key test files to understand test coverage
   - Performed targeted code searches for patterns related to audit areas

## Findings Grouped by Severity

### High Severity Findings

#### LIFE-01: Incomplete Observer Cleanup in AVFoundationPlaybackEngine.shutdown()
- **File**: `StreamKit/Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift`
- **Lines**: 655-671
- **Description**: The `shutdown()` method cancels readiness continuations and removes playback observers, but does not invalidate or clean up the `itemStatusObservation` KVO observer that is set up in the `load()` method when observing `AVPlayerItem.status`. This observer is only invalidated in `cancelPendingReadiness()` and `completeReadiness()`, but not in the shutdown path if a load operation is not actively pending.
- **Impact**: Potential for KVO callbacks to be delivered to a deallocated object if the engine is deallocated without proper cleanup (though the engine is owned by StreamPlayerController which should manage lifecycle).
- **Confidence**: Confirmed
- **Recommendation**: Add `itemStatusObservation?.invalidate()` and `itemStatusObservation = nil` to the `shutdown()` method or `removePlaybackObservers()` method.
- **Fix Complexity**: Low
- **Regression Test**: Add test to verify observer cleanup during shutdown

#### CONC-01: Potential Race Condition in StreamPlayerController.shutdown()
- **File**: `StreamKit/Sources/StreamKit/PublicAPI/StreamPlayerController.swift`
- **Lines**: 478-502
- **Description**: The shutdown sequence sets `isShutdown = true`, increments `loadGeneration`, cancels tasks, then calls `await engine.shutdown()`. However, there is a window where a continuation from the engine's event stream could be resumed after `isShutdown` is set but before the engine's shutdown completes, potentially leading to state updates after shutdown.
- **Impact**: Low likelihood but possible race where events could be processed after shutdown initiation.
- **Confidence**: Strongly suspected
- **Recommendation**: Consider moving the `isShutdown = true` setting to after `await engine.shutdown()` or ensure the engine's event stream is finished before setting the flag.
- **Fix Complexity**: Medium
- **Regression Test**: Add test to verify no state updates occur after shutdown begins

### Medium Severity Findings

#### LIFE-02: Shutdown Idempotency Relies on Flag Check Only
- **File**: `StreamKit/Sources/StreamKit/PublicAPI/StreamPlayerController.swift` (lines 479-482) and `StreamKit/Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift` (lines 655-658)
- **Description**: Both shutdown methods check `isShutdown` and return early if true, making them idempotent. However, the AVFoundationPlaybackEngine.shutdown() method does not reset all state to a clean slate on subsequent calls (e.g., continuations are set to nil but other state like `playbackRate` is retained). While not incorrect, this could be clearer.
- **Impact**: Shutdown is safe to call multiple times but internal state may not be reset to initial conditions.
- **Confidence**: Confirmed
- **Recommendation**: Consider documenting the shutdown idempotency behavior or resetting more state to initial values.
- **Fix Complexity**: Low
- **Regression Test**: Verify multiple shutdown calls don't cause issues

#### API-01: Missing Validation for Extremely High Playback Rates
- **File**: `StreamKit/Sources/StreamKit/PublicAPI/StreamPlayerController.swift`
- **Lines**: 308-313
- **Description**: The `setPlaybackRate(_:)` method validates that the rate is finite and greater than zero, but does not check for excessively high rates that might cause issues with AVFoundation or produce unusable playback speeds.
- **Impact**: Could allow setting playback rates that are numerically valid but practically unusable (e.g., `Float.greatestFiniteMagnitude`).
- **Confidence**: Confirmed
- **Recommendation**: Consider adding an upper bound validation for playback rate (e.g., reasonable limit like 32.0).
- **Fix Complexity**: Low
- **Regression Test**: Test that extremely high rates are rejected

### Low Severity Findings

#### DOC-01: Documentation States Future Features Are Implemented
- **File**: `StreamKit/Documentation/Architecture.md`
- **Lines**: 11-13
- **Description**: The documentation marks `PlaybackSnapshot` and `PlaybackFailure` as "Future" items, but these are fully implemented in the codebase.
- **Impact**: Documentation inaccurately represents the current state of the codebase.
- **Confidence**: Confirmed
- **Recommendation**: Update documentation to reflect that PlaybackSnapshot and PlaybackFailure are implemented.
- **Fix Complexity**: Low
- **Regression Test**: N/A (documentation only)

#### DOC-02: PlaybackStateMachine.md Describes Future Behavior
- **File**: `StreamKit/Documentation/PlaybackStateMachine.md`
- **Lines**: 61-63
- **Description**: The document states: "The actual state transition logic and automatic resumption behavior are **not** implemented in this version of the enums." However, the implementation in StreamPlayerController and AVFoundationPlaybackEngine does implement this coordination logic.
- **Impact**: Documentation understates the current capabilities.
- **Confidence**: Confirmed
- **Recommendation**: Update documentation to reflect the implemented state coordination behavior.
- **Fix Complexity**: Low
- **Regression Test**: N/A (documentation only)

#### TEST-01: Limited Test Coverage for Live Streams and Indefinite Duration Media
- **File**: N/A (test gap)
- **Description**: The test suite does not appear to test behavior with live streams or media that has indefinite duration (where `duration` is indefinite or updates dynamically).
- **Impact**: Missing verification of edge case behavior for important media types.
- **Confidence**: Confirmed (based on test review)
- **Recommendation**: Add test cases for media with `.duration = nil` or live stream scenarios.
- **Fix Complexity**: Medium
- **Regression Test**: Add new test cases

#### TEST-02: Insufficient Stress Testing of Cancellation Scenarios
- **File**: N/A (test gap)
- **Description**: While tests cover basic cancellation, there is limited testing of rapid successive cancellations, cancellation during complex state transitions, or cancellation of multiple overlapping operations.
- **Impact**: Potential edge cases in cancellation handling may not be caught.
- **Confidence**: Confirmed (based on test review)
- **Recommendation**: Add stress tests for cancellation under various conditions.
- **Fix Complexity**: Medium
- **Regression Test**: Add new test cases

### Informational Findings

#### PERF-01: Periodic Time Observer Interval May Be Too Frequent
- **File**: `StreamKit/Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift`
- **Lines**: 261-267
- **Description**: The periodic time observer is set to fire every 0.5 seconds. For long-playing media, this could accumulate significant processing overhead.
- **Impact**: Minor performance consideration for very long playback sessions.
- **Confidence**: Confirmed
- **Recommendation**: Consider making the interval configurable or adjusting based on media duration.
- **Fix Complexity**: Low
- **Regression Test**: Verify performance impact is negligible

## Evidence with Exact File Paths and Line Numbers

### LIFE-01: Incomplete Observer Cleanup
```
StreamKit/Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift:655-671
```
The `shutdown()` method calls `cancelPendingReadiness()` and `removePlaybackObservers()` but does not invalidate `itemStatusObservation` which is only cleaned up in those methods when a readiness operation is actually pending.

### CONC-01: Potential Race in Shutdown Sequence
```
StreamKit/Sources/StreamKit/PublicAPI/StreamPlayerController.swift:478-502
```
Sequence: 
1. Line 484-485: `isShutdown = true; loadGeneration &+= 1`
2. Line 487-491: Cancel `activeLoadTask` and `eventTask`
3. Line 493: `await engine.shutdown()`
Between lines 485 and 493, engine events could still be processed.

### API-01: Missing Playback Rate Upper Bound
```
StreamKit/Sources/StreamKit/PublicAPI/StreamPlayerController.swift:308-313
```
Validation only checks `rate.isFinite, rate > 0` but does not check for excessively high values.

### DOC-01: Incorrect Documentation Status
```
StreamKit/Documentation/Architecture.md:11-13
```
States PlaybackSnapshot and PlaybackFailure are "Future" but they are implemented.

### DOC-02: Understated Implementation
```
StreamKit/Documentation/PlaybackStateMachine.md:61-63
```
States state transition logic is not implemented, but it is implemented in StreamPlayerController.handleEngineEvent() and related methods.

## Test Coverage Gaps

Based on review of the test suite, the following areas have insufficient test coverage:

1. **Live Stream Handling**: No tests for media with undefined or changing duration
2. **Stress Cancellation**: Limited testing of rapid successive cancellations or cancellation during complex state transitions
3. **Error Recovery**: Limited testing of error recovery scenarios after various failure types
4. **Concurrent Operations**: While multiple player isolation is tested, more complex interleaving of operations could be tested
5. **Boundary Conditions**: Testing of edge cases like seeking to very large times, extremely high/low playback rates, etc.
6. **Interruption Handling**: No testing of audio session interruptions or backgrounding scenarios

## Platform/Device Verification Gaps

The audit did not include:
- Manual testing on physical iOS devices across different iOS versions (16+)
- Testing under various network conditions (cellular, WiFi, offline)
- Testing with different media formats (HLS, DASH, progressive download, various codecs)
- Testing background audio playback behavior
- Testing audio routing changes (AirPlay, Bluetooth headphones)
- Testing picture-in-picture compatibility
- Testing with CarPlay integration

## Recommended Remediation Order

1. **High Priority**
   - LIFE-01: Fix incomplete observer cleanup in AVFoundationPlaybackEngine.shutdown()
   - CONC-01: Address potential race condition in shutdown sequence

2. **Medium Priority**
   - LIFE-02: Consider improving shutdown idempotency documentation/clarity
   - API-01: Add upper bound validation for playback rate

3. **Low Priority**
   - DOC-01, DOC-02: Update documentation to reflect implemented features
   - TEST-01, TEST-02: Add test cases for live streams and stress cancellation
   - PERF-01: Consider adjusting periodic time observer interval

## Areas with No Issues Found

After thorough inspection, the following areas were found to have no significant issues:

### ✅ Lifecycle and Resource Management (except LIFE-01, LIFE-02)
- Proper use of `@MainActor` for UI-thread safety
- Correct AVPlayer item replacement and cleanup
- Effective use of generation tokens to prevent stale operations
- Proper continuation management in most cases
- Resources are properly released when no longer needed

### ✅ Cancellation and Asynchronous Operations (except CONC-01)
- Proper use of `Task.isCancelled` checks
- Effective use of generation tokens for stale-operation protection
- Pending readiness continuations are properly cleaned up on cancellation
- Seek completion handles interruptions correctly
- Shutdown properly cancels active operations

### ✅ Swift Concurrency and Isolation
- Correct `@MainActor` boundaries on StreamPlayerController and AVFoundationPlaybackEngine
- Proper Sendable conformance for public types
- Safe task creation with appropriate actor isolation
- AsyncStream consumption and termination handled correctly
- No apparent data races or actor-isolation violations in reviewed code

### ✅ Playback State Machine and Behavior
- Clear separation of PlaybackIntent (application requested) and PlaybackPhase (actual state)
- Correct implementation of buffering behavior and automatic resumption logic
- Proper handling of ended state and transitions
- Appropriate relationship between intent and phase documented and implemented

### ✅ Error Handling and Recovery (except API-01)
- Proper mapping of AVFoundation errors to PlaybackFailure
- Errors are properly propagated to public API consumers
- Failures leave the engine in a recoverable state (shutdown and reset work correctly)
- Old failures do not affect newer sources due to generation checking
- Error messages do not expose sensitive request information

### ✅ Multiple-Player Isolation
- Each StreamPlayerController instance owns its own AVFoundationPlaybackEngine
- Each engine owns its own AVPlayer and AVPlayerItem instances
- Playback state, intent, and tasks are instance-specific
- Event streams and snapshot subscribers are independent per instance
- Time observers and notifications are not shared between instances
- Audio and subtitle selections are isolated per player instance
- Shutdown and cancellation behavior is properly isolated

### ✅ API Design and Compatibility (except API-01)
- Consistent public API with clear separation of concerns
- Appropriate invalid-input validation (nil URLs, invalid rates, etc.)
- Clear error behavior after shutdown (specific shutdownFailure returned)
- Proper access control (public API vs internal implementation)
- Swift Package configuration correctly targets iOS 16+
- API availability checks for newer AVFoundation APIs (where used)
- Demo deployment requirements align with library requirements (both iOS 16+)

## Phase 1 Completion Assessment Against ROADMAP.md

### Completed Implementation (as claimed in ROADMAP.md)
- ✅ Swift Package architecture targeting iOS 16+
- ✅ PlaybackEngine abstraction and AVFoundationPlaybackEngine
- ✅ Public StreamPlayerController API
- ✅ Independent playback engine/controller instances
- ✅ Normalized playback snapshots, intents, events and errors
- ✅ Loading, cancellation and stale-operation protection
- ✅ Play, pause, seek and shutdown
- ✅ Audio and subtitle selection
- ✅ Playback-speed support and validation
- ✅ Snapshot broadcasting
- ✅ SwiftUI demo player with native audio, subtitle and speed menus
- ✅ Automated unit tests for implemented behavior

### Acceptance Criteria (NOT YET MET - from ROADMAP.md)
- ❌ Lifecycle audit: shutdown safety, resource cleanup, no leaks
  - *Status*: Mostly complete with minor issues (LIFE-01, LIFE-02) to address
- ❌ Cancellation audit: operations cancel cleanly, no stale continuations
  - *Status*: Mostly complete with minor concern (CONC-01) to address
- ❌ Concurrency audit: Swift concurrency correctness, actor isolation
  - *Status*: Complete - no issues found
- ❌ Playback state transitions: intent/phase coordination, buffering behavior
  - *Status*: Complete - implementation matches documentation
- ❌ Error handling: proper error propagation and recovery
  - *Status*: Mostly complete with minor gap (API-01) to address
- ❌ Multiple simultaneous players: isolated instances, no interference
  - *Status*: Complete - no issues found
- ❌ Platform compatibility: iOS 16+ behavior verified
  - *Status*: Not verified in this audit (requires manual testing)
- ❌ Regression tests: existing functionality preserved
  - *Status*: Complete - all existing tests pass
- ❌ Full test suite: all tests pass
  - *Status*: Complete - all 61 tests pass

### Next Steps from ROADMAP.md
The audit has addressed the items listed under Phase 1 "NEXT":
- ✅ Audit lifecycle, cancellation and shutdown (completed with minor findings)
- ✅ Audit Swift concurrency and actor isolation (completed - no issues)
- ✅ Audit playback state transitions and error propagation (completed - minor findings)
- ✅ Verify seeking, buffering, ended state and live streams (partially covered - live streams need more testing)
- ❌ Assess audio interruptions and recovery (not covered in this audit)
- ✅ Test multiple simultaneous players (completed - no issues found)
- ✅ Identify missing regression tests (completed - TEST-01, TEST-02 identified)
- ❌ Fix confirmed issues and rerun the full test suite (pending)
- ❌ Verify supported platform and OS-version behavior (requires manual testing)

## Final Assessment

StreamKit demonstrates strong foundational quality for a production-ready media player SDK. The codebase makes excellent use of modern Swift concurrency patterns, maintains proper isolation between player instances, and handles resource management correctly in most scenarios.

The identified issues are relatively minor and would not prevent production use, but addressing them would further enhance robustness. The test suite provides good coverage of the core functionality, though additional tests for edge cases and stress scenarios would improve confidence.

With the recommended fixes applied, StreamKit would be well-positioned to proceed to Phase 2 (FairPlay DRM integration) of the roadmap.

---
*Report generated based on commit 4451e78 of the StreamKit repository*

## Workspace Reassessment — 2026-10-16

This reassessment applies to the current workspace, whose latest recorded commit is 29d9411 plus uncommitted changes. It supersedes the earlier report where noted above. The original findings remain a historical record of the 4451e78 review; its executive summary, severity labels, and final readiness conclusion should not be used as the current status.

### Verification

- `swift test --scratch-path /tmp/streamkit-swiftpm`: **66 tests passed in 9 suites**.
- The test process ran on macOS arm64 (`arm64e-apple-macos14.0`). This does not verify iOS 16+ runtime behavior, physical devices, or any other supported OS version.
- Added regression coverage for unknown-duration time updates, repeated overlapping loads, repeated explicit load cancellation followed by recovery, cancellation cleanup of an AVPlayerItem, paused-state reporting, and rejection of unsupported request headers.

### Original Finding Reassessment

| Finding | Current assessment |
|---|---|
| LIFE-01 — readiness KVO cleanup on shutdown | The original claim was not demonstrated: readiness completion and cancellation already invalidate the KVO observation, and shutdown also calls the cancellation path. Shutdown now includes an unconditional defensive invalidation. |
| CONC-01 — shutdown event race | The proposed fix in the original report was unsafe. Setting `isShutdown` before awaiting engine shutdown prevents controller updates during the suspension. The order is retained. |
| LIFE-02 — shutdown idempotency | Not a production defect. Retaining the configured playback rate is consistent with the engine's settings; the original report did not show an unsafe second shutdown. |
| API-01 — playback-rate upper bound | A 32× maximum is now an explicit SDK policy and has boundary coverage. It is not established as an AVFoundation limit; product requirements should confirm the range before release. |
| DOC-01 / DOC-02 — outdated implementation descriptions | Architecture and state-machine descriptions have been corrected. |
| TEST-01 — unknown duration | Controller-level behavior is covered with synthetic engine events. Real indefinite-duration HLS behavior remains unverified. |
| TEST-02 — cancellation stress | Repeated and overlapping cancellations are covered with tests. Real device/network cancellation behavior remains unverified. |

### Current Findings and Limitations

#### REQ-01: Arbitrary AVURLAsset Headers Are Not a Supported API

`MediaSource` previously exposed `MediaRequestConfiguration.httpHeaders`, but AVFoundation does not provide a supported `AVURLAsset` option for arbitrary request headers. The commonly circulated `AVURLAssetHTTPHeaderFieldsKey` option is explicitly identified by an Apple engineer as unsupported. The public field has now been removed so callers cannot mistake stored configuration for a supported capability. Apple's documented asset initialization options include cookies and a user-agent option, but not arbitrary headers ([initialization options](https://developer.apple.com/documentation/avfoundation/avurlasset-initialization-options), [Apple engineer clarification](https://developer.apple.com/forums/thread/671139)).

#### LIFE-03: Explicit Load Cancellation Retained the Current Item and Playback Observers

The cancellation handler previously cancelled the readiness continuation but did not detach the current item or remove time, status, and notification observers. The cancellation path now removes those observers, pauses the player, and replaces the current item with `nil`, guarded by the engine generation. A regression test verifies that the item is released.

#### STATE-01: Paused Engine Events Could Leave the Snapshot Reporting Playing

When intent was `.play`, the controller discarded `.paused` events. This could make the public phase stale when AVPlayer stopped outside an explicit controller pause. The controller now reports `.paused` while preserving `.play` intent; an explicit `play()` request can retry. This improves phase accuracy but does not add audio-session interruption notifications or automatic interruption recovery.

#### ERR-01: Failure Codes Remain Coarse

AVFoundation failures are generally normalized to `.playback`; the available `.network` and `.unsupportedFormat` codes are not mapped from concrete AVFoundation errors. Failure propagation exists, but error classification is not yet sufficiently specific for provider-independent recovery or analytics.

#### SAMPLE-01: The Demo Includes Placeholder Destinations and Has No Meaningful Demo Tests

The standalone and concurrent-player screens contain working sample flows. The Playlist and Playback Events destinations render placeholder views; their navigation labels now explicitly say they are planned and not implemented. The demo unit test target contains only the generated empty example test, and the UI test target contains launch scaffolding without behavioral assertions. The 66 passing Swift package tests cover the SDK test target, not the Xcode demo app.

#### SAMPLE-02: Demo Player Ownership and Runtime Failures Are Not Fully Demonstrated

The standalone and concurrent demo views create controllers but do not call `shutdown()` when the player-owning screen leaves. The player component also does not render `snapshot.failure`; the parent views only display errors caught during initial load or play. Thus later engine failures are not visibly surfaced by the sample. The demo has not been built or run on an iOS simulator/device as part of this audit.

### Current Readiness Assessment

- The core architecture is suitable for continued Phase 1 work: per-controller state, an engine abstraction, generation checks, and bounded snapshot streams are present.
- The 66-test suite passes on macOS. It does not satisfy iOS device or OS-version verification criteria.
- The sample demonstrates basic standalone and concurrent playback, but not playlist/event inspection, deterministic screen teardown, runtime failure presentation, or tested integration behavior.
- StreamKit is **not yet production-ready** against the roadmap. Arbitrary authenticated HTTP headers are not supported; error mapping is coarse; interruption/background behavior and real-media/device behavior remain unverified.
- Keep the project in Phase 1. Prioritize a supported authenticated-media strategy, AVFoundation error mapping, and iOS validation before starting FairPlay integration.

## Follow-up — 2026-10-16

This follow-up supersedes the corresponding open items above where code or verification changed.

### Completed in the current workspace

- `MediaRequestConfiguration` offers scoped cookies, a user-agent, and host-scoped bearer authentication. Bearer mode routes HTTPS resources through an `AVAssetResourceLoader`, adds an `Authorization: Bearer` header per request, and rewrites HLS child-resource references. Exact host allowlisting and HTTPS-only transport limit credential exposure. Cookie domain/path scoping must match the media and its HLS child requests.
- The authenticated playback demo is separated in its own Protected Playback menu section. It is prefilled with Mux's public HLS test stream and trusted host; a blank token loads it as ordinary HLS, while a supplied token enables the authenticated request path for a protected URL. The example contains no real credential. The public Mux stream is only a basic playback baseline and does not validate bearer authentication.
- Basic playback in the demo has now been verified by the user on an iOS simulator or device. The exact device, OS version, and stream-run details were not recorded; this confirms the sample's basic playback path but not protected HLS.
- Autoplay no longer reports `.playing` immediately after issuing `AVPlayer.play()`. It reports `.ready` with play intent until AVFoundation emits its observed playback state.
- The authenticated URLSession is ephemeral and disables automatic cookie storage and cookie sending. Only explicit `MediaCookie` values are applied, keeping app-wide cookies out of authenticated media requests.
- Added tests cover token/header creation per resource, host scoping, cookie/user-agent/range request fields, HLS child URL rewriting, HTTPS URL mapping, and rejection of insecure HTTP children.
- Added a UI test that opens the bearer-auth demo and checks its URL, trusted-host, token, and load controls.
- Added regression tests for autoplay state reporting and authenticated-session cookie isolation.
- Added GitHub Actions CI to run `swift test` and compile the demo and UI test bundle using the Xcode 27 runner.
- Added `PlaybackFailureMapping` for `NSURLErrorDomain`, common AVFoundation parse/format errors, and wrapped underlying errors. Messages are stable and do not expose raw URLs or request details. Other AVFoundation failures remain `.playback`.
- The demo player now renders `snapshot.failure`. Standalone and concurrent demo screens shut their controllers down when their owning SwiftUI task is cancelled; the full-screen player presentation shares the owner task and controller.
- Placeholder destinations are labeled as planned, not implemented.

### Verification

- Before the two latest regression tests, `swift test` passed **79 tests in 10 suites** on macOS arm64 (Xcode 27.0 toolchain).
- At that revision, after the state and cookie-isolation fixes, `swift test` passed **81 tests in 10 suites**.
- `git diff --check`: clean.
- `xcodebuild build-for-testing` succeeded for the generic iOS Simulator destination, compiling the SDK, demo, and UI test bundle. Simulator test execution/runtime checks could not run in this audit environment because CoreSimulatorService was unavailable and no simulator runtime could be enumerated. The user later confirmed basic demo playback on a simulator or device; protected playback remains unverified.
- The updated sample menu and flow compiled with `xcodebuild build-for-testing`; its bearer-auth UI test compiled but could not run without CoreSimulator in this environment. The public Mux stream has not been treated as an authenticated-origin test.

### Remaining blockers to Phase 1 completion

- Bearer resource loading and playlist rewriting have unit coverage but have not been exercised against a live protected HLS origin on iOS. No reusable public HLS endpoint with bearer-protected playlists and segments was identified; the public sample only checks basic playback. Use a controlled protected origin to validate segments/keys, ranges, redirects, token expiry/refresh, and AVFoundation cancellation on simulator/device before advertising support broadly.
- Audio-session interruption/background behavior, lifecycle profiling, and minimum-supported iOS behavior still need broader simulator/device validation.
- The user confirmed basic sample playback on a simulator or device; UI automation and teardown behavior still need CI/device execution.
- The GitHub Actions workflow passed hosted run 38916346546 on GitHub's Xcode 27 runner. The run validates package tests and compilation of the demo/UI test bundle; it does not execute playback on a simulator or validate interruptions.
- The 32× rate ceiling remains an SDK policy pending product confirmation.

## Audio Session and Background Playback Follow-up — 2026-10-19

- `PlayerConfiguration.automaticallyResumesAfterAudioInterruption` defaults to `true`. The controller observes iOS audio-session interruption notifications, pauses its engine at interruption start, and resumes only if it had a `.play` intent, playback was in an active or starting phase, the policy is enabled, and the interruption-end notification includes `.shouldResume`.
- If the application calls `pause()` during an interruption, the intent becomes `.pause` and playback will not resume automatically. The controller removes its notification observer during shutdown.
- The host app retains ownership of process-wide `AVAudioSession` category, mode, and activation. Background audio also requires the consuming app to enable the `audio` background mode. The demo now configures `.playback` / `.moviePlayback`, activates the session, enables the background mode, and provides a dedicated example screen.
- The demo activates asynchronously with Apple's iOS 27 API. On earlier supported releases, it calls the legacy activation method on a background queue to avoid blocking the UI thread.
- The Audio Session example includes controls that post synthetic interruption notifications. These validate StreamKit's event parsing and recovery policy in the demo, but do not verify that iOS generates interruptions or that background audio/routing works on a device.
- Unit tests cover allowed resumption, system-disallowed resumption, and explicit pause during an interruption. The controller now receives events through an injected `AudioInterruptionSource`; the system adapter owns notification parsing and cleanup, and tests can drive that boundary without posting process-wide notifications. Tests still do not generate real iOS audio-session notifications.
- Interruption handling is per controller. If multiple controllers have play intent, each independently handles the shared notification and may resume; StreamKit has no shared audio-focus arbiter yet. The host must coordinate active audio ownership until this policy is defined.
- The local iOS Simulator generic build compiles the demo and UI-test bundle. Runtime launch is currently unavailable in this environment because CoreSimulatorService cannot find or connect to an installed Simulator runtime.
- **Not yet device-verified:** interruption notifications, background execution, audio routing, and behavior across iOS versions still require simulator/device validation. The successful hosted CI run compiles the demo/UI-test bundle but does not run the UI tests or validate audio behavior.
- **Latest local verification:** `swift test` passes **86 tests in 10 suites**. `xcodebuild build-for-testing` succeeds for the generic iOS Simulator, and inspection of the built demo confirms `UIBackgroundModes` is an array containing `audio`.
- **Physical-device verification (user-reported, 2026-10-19):** On an iPhone running iOS 26.5, Siri interrupted active demo playback; playback paused and automatically resumed when Siri finished. This verifies one real interruption and resume path. It does not verify user pause during the interruption, other interruption sources, background playback, audio routing, or other OS versions.

**Readiness remains: not production-ready.** Basic demo playback and the Siri interruption/resume path have been user-verified. Phase 2 FairPlay work has started while Phase 1 verification gaps remain open; validate the authenticated resource loader against a controlled protected HLS origin and complete broader iOS runtime checks.

## FairPlay Phase 2 Start — 2026-10-19

The user chose to begin Phase 2 before all Phase 1 acceptance gaps were closed. This is a deliberate roadmap transition, not a claim that Phase 1 is complete. The Phase 1 findings above remain open.

### Added in the current working tree

- Added a public, provider-neutral contract in `MediaSource.swift`: `FairPlayLicenseProvider` supplies the app certificate, maps the HLS key identifier and initialization data to a provider content identifier, and exchanges a `FairPlayLicenseRequest` containing the AVFoundation-generated SPC for raw CKC bytes. `FairPlayConfiguration` attaches that provider to a media source.
- Added `FairPlayContentKeySession`, using AVFoundation `AVContentKeySession` and an `AVURLAsset` recipient. It handles initial and renewal key callbacks, SPC creation, CKC handoff, unsupported persistable-key requests, generic error redaction, and task/resource cleanup on item replacement, cancellation, and shutdown. Active AVFoundation requests are completed at most once even when teardown races with a late provider response.
- Extracted `FairPlayKeyExchange` so the provider handshake is independently testable: it validates content-ID/certificate/SPC/CKC data and checks cancellation between async boundaries. Six focused tests cover successful data flow, invalid empty values, and pre-cancelled tasks. This does not emulate AVFoundation SPC generation or prove real license-service compatibility.
- Kept license-server networking, app-specific certificate retrieval/caching, content-ID conversion, endpoint authentication, and response-envelope parsing in the host app. Bearer authorization for HLS media remains a separate configuration.
- Added a dedicated FairPlay entry/screen to the demo menu. It explains required integration materials but does not pretend to perform protected playback without credentials.
- The FairPlay screen now includes a button-driven mock contract walkthrough. It creates synthetic certificate/SPC/CKC data and displays the mock content ID and payload sizes. It directly demonstrates the public provider method shape; it does not invoke StreamKit's internal key exchange, create an AVContentKeySession, contact a server, or decrypt media. A UI navigation/mock-result assertion was added and compiled, but simulator execution remains unavailable.
- Added `Documentation/FairPlayIntegration.md`, README integration notes, and architecture/roadmap status updates.
- Added tests for configuration identity/equality and FairPlay request payload preservation.

### Verification and limitations

- `swift test` passes **95 tests in 11 suites** locally, compiling the new public API and AVFoundation adapter on the current Xcode 27 SDK. FairPlay tests cover the mocked exchange order/data, renewal propagation, cancellation checkpoints, invalid empty values, and rejection of non-HTTPS media.
- The demo and UI test bundle compile with the FairPlay screen, integration-code sample, and a navigation-content assertion. UI execution/device runtime testing was not possible: CoreSimulatorService refused connection. No FairPlay media was played.
- Code compilation and mockable API tests do not verify the certificate/SPC/CKC exchange. The repository has no app-approved FairPlay certificate, provider-specific license endpoint contract, or protected test stream.
- Offline/persistable keys are not supported in this initial slice. Provider errors are intentionally redacted; product diagnostics may later need a safe, structured failure identifier.
- Current risk to validate: providers must honor task cancellation for network exchanges; load replacement cancels StreamKit's task but cannot force-stop app-owned networking that ignores Swift task cancellation.
- **Device-install compatibility update:** the demo's app and test deployment targets are now set to iOS 26.5 after the user reported an iPhone on iOS 26.5 could not install it. The package remains iOS 16+. A build confirms this target compiles, but the app has not yet been installed on the user's physical phone; this change does not establish compatibility back to iOS 16.

Apple's HLS guidance recommends `AVContentKeySession` for key loading; Apple's current API identifies `AVURLAsset` as an `AVContentKeyRecipient` ([AVContentKeySession](https://developer.apple.com/documentation/avfoundation/avcontentkeysession), [AVContentKeyRecipient](https://developer.apple.com/documentation/avfoundation/avcontentkeyrecipient), [2024 HLS guidance](https://developer.apple.com/streaming/Whats-new-HLS-2024.pdf)).

**Next FairPlay work:** rebuild the demo, add focused failure/cancellation tests for the request processor, then integrate a real app/provider implementation when the user supplies the approved certificate source, key-ID mapping, license request/response contract, and protected HLS test asset. Verify playback and renewal on a physical iOS device before treating FairPlay as production-ready.

## Axinom FairPlay Device-Test Harness — 2026-10-20

The sample has a dedicated **Axinom FairPlay Test** entry, separate from ordinary playback examples. It prepopulates Axinom's public protected HLS vector, public evaluation certificate URL, generic FairPlay license URL, and public evaluation License Service Message token. The token is included in the sample source and app bundle solely to make the public test vector immediately runnable; the token is not persisted in preferences or emitted in diagnostics. The demo adapter fetches the certificate, strips `skd://` from the key identifier as Axinom documents, posts the AVFoundation SPC, sends the token as `X-AxDRM-Message`, and hands the response bytes back as CKC. The shared StreamKit player and fullscreen controls render the asset.

**Verified in a user-provided live run:** license HTTP 200, AVFoundation accepted the FairPlay content-key response, and playback phase reached `.playing`. This establishes successful playback for the public Axinom test asset in the demo. It does not validate the user's own provider, certificates, entitlement service, production content, or license renewal. Renewal, invalid/expired entitlement, network failure, cancellation, and source switching remain open acceptance checks. The adapter is a demo-only integration harness, not a production credential-management design.

### FairPlay loading diagnostics — 2026-10-20

The first device test remained in the loading state. The demo waits for AVFoundation's item readiness before reporting load complete, so a pending FairPlay key exchange can leave the screen waiting. Added sample-only diagnostics for the current exchange stage, certificate HTTP result, license HTTP status, and Axinom's `X-AxDRM-ErrorMessage` response header. Certificate/license requests now use a 30-second timeout. Tokens and SPC/CKC bodies remain hidden. These diagnostics narrow the failure but do not yet identify the user's device-side failure; repeat the test and use the displayed result to determine whether the key callback was reached and whether Axinom accepted the request.

The user reports that the audio/subtitle track menus load but video does not start. This indicates track metadata became available, but it does not prove content decryption or successful playback. Added visible playback phase and intent to the Axinom demo screen so the next device report can distinguish `.waiting`, `.ready` with `.play` intent, and a true failure. Real device playback remains unverified.

The next device attempt returned HTTP 400 with Axinom's message that `X-AxDRM-Message` must have exactly one non-empty value. The demo sets this header from the token field. Added a preflight check showing only whether it is non-empty and its character count, plus destination/response host to expose any redirect behavior. This distinguishes an empty app field from a header being dropped or changed during request routing without revealing the JWT.

The user subsequently reports a successful license HTTP response with playback phase `.waiting` and intent `.play`. Added a timestamped, capped FairPlay exchange log and a **Copy diagnostics** button. The copied report includes phase, intent, request stages, HTTP status, response/destination host, and Axinom error text while excluding credentials, DRM payloads, and full URLs. Device playback is still not confirmed.

The latest copied device report remains `.waiting`/`.play` after a successful HTTP 200 license response. Added an optional redacted diagnostic handler to `FairPlayConfiguration` and wired AVFoundation's content-key request accepted/failed callbacks into the demo's copyable log. This will establish whether the CKC was processed; if accepted while playback remains waiting, investigate HLS segment fetch/buffering and media compatibility next.

### Axinom public-vector playback verified — 2026-10-20

The user supplied a later diagnostic report with phase `.playing` and intent `.play`. The report confirms the certificate fetch returned HTTP 200, the generic Axinom FairPlay license endpoint returned HTTP 200, and AVFoundation accepted the FairPlay content-key response. This is positive end-to-end evidence that the demo can play Axinom's public protected HLS vector. The earlier `.waiting` report is superseded for this run. Renewal, expired/invalid entitlement, network failure, cancellation, protected-to-clear replacement, and production-provider integration are not covered by this result.

### Local verification of the FairPlay integration — 2026-10-20

- Reviewed implementation revision: `0effdeb` (`Add FairPlay playback integration and Axinom demo`).
- `swift test`: **95 tests in 11 suites passed** on macOS arm64.
- `xcodebuild ... build-for-testing`: succeeded for generic iOS Simulator, compiling the package, demo, and UI test bundle.
- UI tests were not executed; CoreSimulatorService is unavailable in this environment. The user's live playback report is separate real-runtime evidence for the Axinom public vector.
- `git diff --check`: passed.

### Match the public Axinom Shaka test configuration — 2026-10-20

The user supplied the public Shaka test-player configuration for the same HLS vector. Its generic FairPlay license endpoint differs from the tenant-specific URL previously prefilled in StreamKit. Updated the demo default to the generic endpoint so the user can test the same endpoint/token configuration in both players; the URL remains editable for tenant-specific tests. The manifest and public evaluation certificate already matched. Initially left the token blank, then the user clarified that the supplied License Service Message is Axinom's public evaluation token for this public test vector. The demo preloads it for convenience. This historical configuration update was followed by a successful live playback report recorded below.

## Real-Device Siri Interruption Verification — 2026-10-19

The user tested the Audio Session example on a physical iPhone running iOS 26.5. While video playback was active, invoking Siri paused playback; when Siri finished, playback resumed automatically. This verifies the real iOS interruption notification and the configured automatic-resume path for this scenario.

This result supersedes earlier statements in this report that all interruption behavior was still awaiting device verification. Remaining unverified cases include explicitly pausing during Siri, other interruption sources (such as calls or alarms), continuing audio while the app is backgrounded, route changes, simultaneous controllers, and behavior on other supported iOS versions. The simulator's synthetic-interruption button remains a separate policy/demo aid and is not the basis for this device verification.

## Full SDK and Demo Reassessment — 2026-10-19

**Revision reviewed:** `cb001e3` (`feat: handle audio interruptions and background playback`). This review covers the package API and AVFoundation engine, authenticated-media loading, the SwiftUI demo, tests, CI, and current project documentation. The 86-test package run and generic iOS Simulator `build-for-testing` succeeded on this exact source tree before the commit was pushed. The built demo contains `UIBackgroundModes = [audio]`. Simulator execution and real-device behavior were not verified. Hosted run 38916346546 predates `cb001e3`; a hosted result for this revision has not been confirmed.

### What is working well

- The controller, playback-engine protocol, and AVFoundation implementation form a clear control boundary. Controller and engine state are `@MainActor` isolated, load generations reject stale work, and snapshot streams are bounded to the newest value and removed on termination.
- Regular media uses AVFoundation's native URL path. Bearer media has a separate loader path with HTTPS enforcement, exact host allowlisting for bearer tokens, explicit cookies, redirect credential scoping, and HLS child-resource rewriting. Unit tests cover the security-sensitive request and rewrite rules, but not a real protected origin.
- The demo presents standalone playback, multiple independent players, fullscreen controls, bearer configuration, and interruption behavior. It shows failures and labels Playlist and Playback Events as planned placeholders rather than implemented examples.
- Interruption handling has a defined per-controller policy and unit coverage. The host owns the process-wide audio session and background capability, as documented.

### Findings and remaining work

1. **High — Demo deployment target does not exercise the SDK's full supported range.** `Package.swift` declares iOS 16+, while the demo currently targets iOS 26.5 to support the user's device. It therefore still does not demonstrate integration on the package's minimum supported OS. Decide whether the demo should support iOS 17 (the demo uses Swift Observation), then build/run against that runtime.
2. **High — Audio behavior remains code- and unit-verified only.** The tests inject interruption notifications; they do not establish that real calls, Siri, route changes, background execution, or device lock behavior work. Validate on a physical iPhone across the declared OS range.
3. **High — Bearer HLS remains unverified against protected media.** Use a controlled HTTPS HLS origin to verify master/child playlists, segments, keys, byte ranges, redirects across trusted and untrusted hosts, token expiry/refresh, cancellation, and real AVFoundation error mapping.
4. **Medium — Multi-player audio focus is undefined.** Every live controller observes the process-wide interruption and can independently resume. Define whether the host coordinates one audible controller or StreamKit offers a shared focus policy; test two controllers through interruption and recovery.
5. **Medium — The audio-session sample does not deactivate the session on exit.** `AudioSessionDemoView` activates `.playback` but its cancellation cleanup only shuts down the controller. Add explicit ownership-aware deactivation or document why the demo intentionally keeps the process-wide session active, and verify that leaving the screen does not suppress other audio.
6. **Medium — CI compiles UI tests but does not execute them.** The workflow runs `build-for-testing` for a generic simulator destination, while package tests run on macOS. Add a simulator runtime job for navigation and UI regressions when runner support permits; preserve device-only behavior checks for manual validation.
7. **Medium — Demo lifecycle behavior lacks a re-entry regression assertion at this revision.** The sample shuts controllers down when their owning SwiftUI tasks are cancelled. The user has confirmed the selected baseline's player-reopen behavior, but CI does not currently assert leaving and reopening each player destination. Keep this user-verified behavior covered by a navigation regression test.
8. **Planned scope remains incomplete.** Playlist selection and public playback-event inspection are placeholders; FairPlay, analytics, advertising, Picture in Picture, AirPlay, live-edge handling, and release/distribution policy remain roadmap work. The SDK is a strong playback foundation, not yet a complete production player package.

### Recommended order

1. Lower the demo deployment target from iOS 26.5 to the chosen supported demo floor (likely iOS 17) and verify on that runtime.
2. Define multi-controller audio focus and make the sample's audio-session lifecycle ownership explicit.
3. Execute the UI tests in a simulator-capable CI job and add navigation re-entry coverage.
4. Perform physical-device interruption, background, route-change, and lifecycle profiling.
5. Validate bearer HLS against a controlled protected origin and refine error mapping from real AVFoundation failures.
6. Close remaining Phase 1 acceptance criteria before starting FairPlay (Phase 2).
