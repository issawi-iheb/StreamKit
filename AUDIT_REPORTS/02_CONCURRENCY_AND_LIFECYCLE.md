# Concurrency and lifecycle

## Isolation model

`StreamPlayerController`, `AVFoundationPlaybackEngine`, `SnapshotBroadcaster`, `SystemAudioInterruptionSource`, and FairPlay key-session orchestration are `@MainActor`. AVFoundation and NotificationCenter callbacks hop to main actor tasks; authenticated loader and FairPlay delegate queues use explicitly synchronized/isolated boundaries. Public snapshot/source/config/error types are `Sendable`. Two `@unchecked Sendable` completion gates use `NSLock` for one-shot host/AVKit callbacks (`StreamAVPlayerView.swift` and `StreamPictureInPictureController.swift`). These are narrow and have lock-protected mutable state.

Controller event stream tasks capture weak self and stop on stream finish. Shutdown cancels event/audio/load tasks, shuts down source and engine, then finishes snapshots (`StreamPlayerController.swift:613-641`). Engine generations and item identity guard stale callbacks (`AVFoundationPlaybackEngine.swift:467-477` and controller `416-429`). Snapshot subscriber cancellation removes its continuation asynchronously on the main actor (`SnapshotBroadcaster.swift:38-42`). `bufferingNewest(1)` is appropriate for snapshots, where intermediate state is superseded; engine events use unbounded buffering, so time-event volume/lifecycle should be watched (`AVFoundationPlaybackEngine.swift` initialization).

## Scenario audit

| Scenario | Current protection | Residual question / validation |
|---|---|---|
| Load A then B before A completes | Controller increments generation and cancels prior load; engine cancels readiness and rejects stale generation/item; tests cover overlaps | Validate bearer URLSession and FairPlay callbacks also settle after replace, on device/provider (DRM-001). |
| Shutdown during loading | Controller cancels task and increments generation; engine resolves readiness and clears item/resources | Mock/controller tests cover shutdown loading; run suite when host permissions allow. |
| Shutdown during seek | Controller rechecks shutdown after await; engine checks current item/generation after seek | AVPlayer seek completion may remain pending briefly; test cancellation/teardown on device. |
| Rapid concurrent seeks | Each seek checks item generation but lacks per-seek token; controller writes requested target after await | Potential stale snapshot or completion-order mismatch; PLAY-001. |
| Play before item ready | `.loading` changes intent; load completion starts engine if intent still play | Covered by controller tests. |
| Pause while buffering | Intent becomes pause and late playing event is ignored | Covered by tests; verify real AVPlayer status ordering. |
| Old item callback after replacement | Item identity plus generation checks before emit | Correct defensive approach; AVFoundation callback races still need test. |
| Cancel task while callback executing | Main-actor callback/task handoff serializes state; cancellation handlers schedule actor cleanup | Race should remain idempotent; readiness continuation cleared before resume. No defect established. |
| Subscriber terminates during publication | Main actor serializes publish; termination cleanup is queued; stream has newest-one buffering | Fine; test current tests cover normal finish, not explicit cancellation/removal stress. |
| Repeated shutdown | `isShutdown` guards both controller and engine | Idempotent. |
| PiP start/stop during teardown | PiP state retains exact layer while transitioning; view preserves player connection during transition | A consumer must retain controller/view and restoration must complete; no teardown integration tests. PIP-001. |
| Replace DRM source with key pending | key session cancels tasks and resolves active AVContentKeyRequest once using identity guard | SPC callback itself wraps non-cancellable continuation; no cancellation handler. Late callback resumes continuation normally, and task can be canceled, but teardown may retain request until AVFoundation callback returns. DRM-002. |
| Multiple DRM players | engine and key session are per instance; provider can be shared if Sendable | No test proving separate protected AVContentKeySession behavior; DRM-001. |

## Findings

**CONC-001 — Medium, Potential risk:** `LoadHandle` stores a single `Task<Void, Error>` (`Sources/StreamKit/PublicAPI/LoadHandle.swift:10-25`). All callers await the same task, and `cancel()` cancels that shared task. This is explicitly documented, so it is not an undocumented bug, but callers may infer waiter-local cancellation. Either preserve and strengthen the shared-operation contract in API docs, or replace with a controller-owned operation handle whose cancel semantics are explicit and whose waiter cancellation does not implicitly cancel the operation. Add a two-waiter test before changing semantics.

**CONC-002 — Medium, Test gap:** actor hops and event buffering are architecturally reasonable, but no strict-concurrency CI evidence exists. Add a CI build with the package's existing Swift 6.4 settings and a supported iOS target; do not toggle settings to create a new migration in this audit. See DEP-001.

**DRM-002 — Medium, Potential risk:** `FairPlayContentKeySession.streamingContentKeyRequestData` uses `withCheckedThrowingContinuation` without a cancellation handler (`FairPlayContentKeySession.swift:202-227`). Provider tasks are canceled during invalidation, but this AVFoundation callback stage cannot be canceled through this wrapper. Check cancellation before requesting SPC and define how a late SPC completion is ignored after invalidation; prove with a controllable callback seam before editing.

## Suggested exact regressions

- `StreamPlayerControllerTests.overlappingSeeksPublishOnlyCurrentSeek` in `Tests/StreamKitTests/StreamPlayerControllerTests.swift`: hold both engine completions, complete newer then older, assert defined last-request semantics and actual snapshot consistency.
- `LoadHandleTests.cancellingOneWaiterDoesNotCancelOtherWaiters` (new `Tests/StreamKitTests/LoadHandleTests.swift`) **only if contract changes**; otherwise assert cancellation cancels the shared operation for all waiters.
- `FairPlayContentKeySessionTests.replacementWhileSPCRequestPendingDoesNotCompleteStaleRequest` (new package test with injected callback adapter); require real-device follow-up.
- `SnapshotBroadcasterTests.cancelledSubscriberIsRemoved`: cancel iterator/task, publish repeatedly, assert stream ends and no retained subscriber through a test-only count.

No checked continuation double-resume was found in the inspected readiness and FairPlay completion paths: both remove/clear their pending identity before resume/finish. The SPC wrapper has one callback-controlled resume and checked continuation diagnostics would catch a violation, but exactly-once callback behavior remains an AVFoundation assumption to validate.
