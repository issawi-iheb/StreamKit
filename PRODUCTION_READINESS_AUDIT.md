# StreamKit Production Readiness Audit Report

## Executive Summary

This report presents the findings of a production-readiness audit of the StreamKit iOS media-player SDK. The audit focused on verifying the core stabilization and production readiness aspects outlined in Phase 1 of the project roadmap.

Overall, StreamKit demonstrates a solid foundation with proper use of Swift concurrency, resource management, and isolation patterns. The codebase follows modern Swift practices with correct `@MainActor` usage, proper task cancellation, and comprehensive error handling. All 61 unit tests pass, indicating good test coverage for the implemented functionality.

However, several areas for improvement were identified, primarily related to:
- Edge cases in shutdown sequence and state transitions
- Potential improvements in observer cleanup
- Documentation accuracy regarding certain behaviors
- Additional test coverage for concurrency and cancellation scenarios

No critical defects were found that would prevent production use, but addressing the identified issues would enhance robustness and reliability.

## Audit Scope and Limitations

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

## Commands Run and Actual Results

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
- Added tests cover token/header creation per resource, host scoping, cookie/user-agent/range request fields, HLS child URL rewriting, HTTPS URL mapping, and rejection of insecure HTTP children.
- Added a UI test that opens the bearer-auth demo and checks its URL, trusted-host, token, and load controls.
- Added `PlaybackFailureMapping` for `NSURLErrorDomain`, common AVFoundation parse/format errors, and wrapped underlying errors. Messages are stable and do not expose raw URLs or request details. Other AVFoundation failures remain `.playback`.
- The demo player now renders `snapshot.failure`. Standalone and concurrent demo screens shut their controllers down when their owning SwiftUI task is cancelled; the full-screen player presentation shares the owner task and controller.
- Placeholder destinations are labeled as planned, not implemented.

### Verification

- `swift test`: **79 tests passed in 10 suites** on macOS arm64 (Xcode 27.0 toolchain).
- `git diff --check`: clean.
- `xcodebuild build-for-testing` succeeded for the generic iOS Simulator destination, compiling the SDK, demo, and UI test bundle. Simulator test execution/runtime checks could not run because CoreSimulatorService was unavailable and no simulator runtime could be enumerated. No physical iOS device verification was possible.
- The updated sample menu and flow also compiled with `xcodebuild build-for-testing`; its bearer-auth UI test compiled but could not run without CoreSimulator. The public Mux stream has not been treated as an authenticated-origin test.

### Remaining blockers to Phase 1 completion

- Bearer resource loading and playlist rewriting have unit coverage but have not been exercised against a live protected HLS origin on iOS. No reusable public HLS endpoint with bearer-protected playlists and segments was identified; the public sample only checks basic playback. Use a controlled protected origin to validate segment/key requests, range behavior, CDN redirects, token expiry/refresh, and AVFoundation cancellation on simulator/device before advertising support broadly.
- Audio-session interruption/background behavior, real media/network playback, and minimum-supported iOS behavior still need simulator/device validation.
- Demo UI behavior and teardown compile for the generic iOS Simulator target but have not been exercised at runtime because simulator services are unavailable.
- The 32× rate ceiling remains an SDK policy pending product confirmation.

**Readiness remains: not production-ready.** Keep work in Phase 1; validate the authenticated resource loader against real protected HLS origins and iOS runtime behavior before Phase 2.
