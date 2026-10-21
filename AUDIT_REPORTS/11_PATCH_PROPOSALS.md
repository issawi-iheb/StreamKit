# Patch proposals (proposed and unapplied)

All code below is **proposed only**. No production file has been edited. Line numbers and excerpts refer to the audited checkout at `bce7c700f2b2191218d73e1be399956e5aa2cbb8` plus the pre-existing dirty working-tree edits. Re-run `nl -ba` before implementation because line numbers move as soon as changes land.

## PLAY-001 — Gate concurrent seek completions

- **Severity/confidence:** High / Potential risk; verify AVPlayer ordering before committing behavior.
- **Files/current lines:** `Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift:714-753`; `Sources/StreamKit/PublicAPI/StreamPlayerController.swift:377-411`.
- **Current code:** engine captures `let generation = loadGeneration`, awaits `player.seek(...)`, then checks only `isCurrentItem(item, generation:)`; controller awaits engine and writes `currentTime: time`.
- **Proposed internal patch (concept; exact API depends on behavior verification):**

```diff
@@ AVFoundationPlaybackEngine stored state
     private var loadGeneration: UInt64 = 0
+    private var seekGeneration: UInt64 = 0
@@ func seek(to time: TimeInterval)
-        let generation = loadGeneration
+        let generation = loadGeneration
+        seekGeneration &+= 1
+        let request = seekGeneration
@@ after await player.seek(...)
         guard isCurrentItem(item, generation: generation) else {
             throw CancellationError()
         }
+        guard seekGeneration == request else {
+            throw CancellationError()
+        }
         guard completed else {
             throw CancellationError()
         }
```

Controller-side improvement: return actual current time from engine or have the engine emit the authoritative time after accepted completion; do not assign the old requested target after an obsolete continuation. If the protocol changes, update `PlaybackEngine.swift`, `MockPlaybackEngine.swift`, and controller tests. The token alone prevents stale controller completion only if every seek increments it before awaiting and the check occurs before state publication.

- **Why:** generation distinguishes source, not seek requests. Per-seek token is the smallest targeted guard.
- **Alternative:** serialize seeks in controller. Easier to reason about but adds latency and queue/cancellation policy; prefer token if AVPlayer supports concurrent replacement safely.
- **Tests:** `StreamPlayerControllerTests.overlappingSeeksPublishOnlyCurrentSeek`, complete newer then older; run AVFoundation device case.
- **Expected:** no stale snapshot update. **Compatibility:** public error/cancel semantics may change; document superseded seeks.
- **Validation:** `swift test`; iOS device seek test with instrumentation that records actual player time.

## CONC-001 — Make shared load cancellation explicit

- **Severity/confidence:** Medium / Potential risk.
- **File/lines:** `Sources/StreamKit/PublicAPI/LoadHandle.swift:10-25`.
- **Current excerpt:** one stored `Task<Void, Error>`; `waitUntilReady()` awaits its value; `cancel()` cancels it.
- **Proposal A (smallest):** expand API docs to state cancellation cancels the shared load operation for every waiter and awaiting-task cancellation does not cancel it. Add two-waiter test. **Proposal B:** operation-owned cancellation token controlled by controller, with waiter cancellation isolated. Do not choose B without consumer requirement because it changes API semantics and lifetime ownership.
- **Tests:** `loadHandleCancellationContract` in `StreamPlayerControllerTests.swift` with two waiters.
- **Expected:** deterministic documented semantics. No implementation patch selected until contract is decided.

## DRM-002 — Make SPC callback cancellation observable

- **Severity/confidence:** Medium / Potential risk.
- **File/lines:** `Sources/StreamKit/PlaybackCore/FairPlayContentKeySession.swift:202-227`.
- **Current excerpt:** `withCheckedThrowingContinuation` resumes from `makeStreamingContentKeyRequestData` callback; no cancellation handler.
- **Proposal:** first extract a small internal SPC requester protocol/closure injectable in tests. On cancellation/invalidation, mark request token stale and ensure late callback does not proceed to network exchange or finish AVFoundation request twice. Do not simply abandon a checked continuation: it must still be resumed when callback arrives. If AVFoundation provides no cancellation operation, document that this stage drains on callback and ensure state does not retain payloads longer than required.
- **Tests:** controlled callback held across `invalidate()`, then released; assert one cancellation result and no license request.
- **Expected:** safe teardown and no stale exchange. Exact unified diff is unsafe until callback semantics/seam are established.

## PIP-001 — PiP lifecycle validation, no speculative source patch

- **Severity/confidence:** High / Test gap.
- **Files/lines:** `Sources/StreamKit/PublicAPI/StreamPictureInPictureController.swift:65-85, 230-295`; `Sources/StreamKit/PublicAPI/StreamAVPlayerView.swift` restoration delegate.
- **Current code evidence:** transitions retain source layer; delegate finishes start/fail/stop; restoration gate is idempotent.
- **Proposal:** add unit test for completion gate and physical-device integration tests. Document that host restoration handler must invoke completion exactly once; implementation's one-shot wrapper safely ignores duplicate calls. Establish timeout behavior as a policy before adding timeout code, since AVKit callback lifetime requirements need verification.
- **Tests:** `piPRestorationCompletesOnce`; device tests described in `05_PIP_AND_FULLSCREEN.md`.
- **Expected:** validated lifecycle; no source change recommended without reproduced bug.

## DEP-001 — Add CI (new file)

- **Severity/confidence:** Medium / Test gap.
- **File:** new `.github/workflows/streamkit.yml` (directory absent at audit).
- **Proposal:** run `swift test`, release build, public consumer compile and iOS simulator demo build. Use runner toolchain matching Swift tools 6.4 and a deployment target no higher than iOS 16 for package API validation. Avoid adding third-party actions/dependencies beyond an approved CI baseline.
- **Acceptance:** all jobs green and output retained. No existing workflow to patch.

## SEC-001 — Redirect matrix

- **Severity/confidence:** Medium / Test gap.
- **File/lines:** `Sources/StreamKit/PlaybackCore/AuthenticatedMediaResourceLoader.swift:489-555` and `Tests/StreamKitTests/AuthenticatedMediaResourceLoaderTests.swift`.
- **Proposal:** tests for redirect to exact allowlisted HTTPS host, untrusted HTTPS host and HTTP downgrade; assert no bearer token crosses prohibited boundary. Only modify delegate implementation if tests expose a defect. Preserve cookies/path scope and do not log authorization headers.

## Report-only improvements without patch-ready source changes

ARCH-001, API-001, PLAY-002, PLAY-003, AUDIO-001, VIDEO-001, FULL-001, DRM-001 and API-002 are architectural, documentation, or validation actions. Exact types/files/current lines and proposed approaches are supplied in reports 01-10. Introducing public APIs for live seek ranges, stable track IDs, rendering protocols, or retries is not safe without explicit product semantics; no fabricated diffs are supplied.
