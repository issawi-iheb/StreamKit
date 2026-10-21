# StreamKit Playback Lifecycle and Resource Management Audit

> **Historical checklist, reconciled 2026-10-20.** The findings and “Missing
> Test Coverage” list below describe an earlier review snapshot. Several items
> have since been covered or mitigated. See the [current production readiness
> audit](../../PRODUCTION_READINESS_AUDIT.md) for overall status and the
> [roadmap](../../ROADMAP.md) for next steps. The current working tree based
> Historical verification on `bce7c70` recorded 111 package tests and 8 demo
> unit/UI tests on iPhone 17 Pro / iOS 26.5 Simulator. The 2026-10-21 follow-up
> passes 115 package tests and 4 demo unit tests; its UI test attempt stalled
> and was interrupted, so no current UI result is claimed. See the current
> [production readiness audit](../../PRODUCTION_READINESS_AUDIT.md). PiP and
> rotation still require device validation.

This report analyzes the StreamKit playback lifecycle and resource management for potential issues before adding FairPlay DRM, advertising, or Picture in Picture.

## Inspection Points

### 1. StreamPlayerController lifecycle and shutdown behavior

**Findings:**
- The `StreamPlayerController` has a `shutdown()` method that sets `isShutdown = true`, cancels active tasks, and calls `engine.shutdown()`.
- The `isShutdown` flag is checked at the start of many public methods (`load`, `play`, `pause`, `seek`, etc.) and returns early or throws a `shutdownFailure()`.
- The `loadGeneration` is incremented during shutdown to invalidate ongoing operations.
- Active load and event tasks are cancelled and set to nil.
- The engine's `shutdown()` is awaited.
- The snapshot broadcaster is finished with a final idle snapshot.

**Potential Risks:**
- **Race condition during shutdown**: If `shutdown()` is called multiple times concurrently, the `isShutdown` flag may be set multiple times, but the subsequent checks at the start of the method (`guard !isShutdown else { return }`) prevent re-entry. However, the non-atomic increment of `loadGeneration` (`loadGeneration &+= 1`) could lead to lost increments if two shutdowns happen simultaneously. This is unlikely to cause a correctness issue because the generation is used for invalidation, and an extra increment would only make the generation larger, which is harmless.
- **Task cancellation order**: The `activeLoadTask` and `eventTask` are cancelled before the engine shutdown. This is appropriate because we want to stop loading and event processing before tearing down the engine.
- **Snapshot publication after shutdown**: The `updateSnapshot` method checks `isShutdown` and returns early if true, preventing snapshots from being published after shutdown. However, the `shutdown()` method itself publishes a final snapshot via `snapshotBroadcaster.finish(with: finalSnapshot)`. This is safe because `isShutdown` is set to true before calling `finish`, and the broadcaster's `finish` method checks `isFinished` (not `isShutdown`). The broadcaster does not check the controller's `isShutdown` flag, so it could publish after the controller is shutdown if another reference to the broadcaster exists. However, the broadcaster is private to the controller and not exposed, so this is safe.

**Existing Protections:**
- The `isShutdown` flag is checked early in public methods to prevent operation after shutdown.
- Tasks are cancelled and set to nil to prevent dangling references.
- The snapshot broadcaster is properly finished to avoid leaking continuations.

**Missing Test Coverage:**
- Test for concurrent shutdown calls.
- Test that calling public methods after shutdown throws or returns appropriately.

### 2. AVFoundationPlaybackEngine resource ownership and cleanup

**Findings:**
- The engine owns an `AVPlayer` instance created in `init()`.
- The engine's `shutdown()` method:
  - Sets `isShutdown = true` and increments `loadGeneration`.
  - Cancels pending readiness and removes playback observers.
  - Pauses the player and replaces the current item with nil.
  - Finishes the event continuation and sets it to nil.

**Potential Risks:**
- **Observer removal**: The `removePlaybackObservers()` method invalidates and nilifies the observations, but it does not set `observedItem` to nil until after the observations are invalidated. This is safe because the observations are invalidated first, but note that `observedItem` is set to nil at the end of the method. However, in `installPlaybackObservers`, we set `observedItem = item`. If an observer fires after `removePlaybackObservers` has started but before `observedItem` is set to nil, it could still observe a stale item. However, the observers are invalidated, so they should not fire after invalidation. The order is safe.
- **Player item replacement**: The player's current item is set to nil, which is the correct way to release the item.
- **Event continuation**: The event continuation is finished and set to nil, which prevents further events from being emitted.
- **Load generation increment**: Similar to the controller, the engine increments `loadGeneration` during shutdown, which could have a race condition if shutdown is called concurrently. However, the engine's `shutdown()` method is called from the controller's `shutdown()` under the same isolation (main actor), so concurrent calls are serialized by the actor. Therefore, there is no race condition.

**Existing Protections:**
- The `isShutdown` flag is checked in the `load` method and other places to prevent operation after shutdown.
- Observers are properly invalidated and set to nil.
- The player's current item is set to nil to release resources.
- The event continuation is finished to stop event emission.

**Missing Test Coverage:**
- Test that calling `load` after shutdown throws a shutdown failure.
- Test that the event stream finishes after shutdown.
- Test that the player's current item is nil after shutdown.

### 3. AVPlayerItem status observation and timeControlStatus observation

**Findings:**
- The engine observes the `status` of the `AVPlayerItem` via `itemStatusObservation` (NSKeyValueObservation).
- The engine observes the `timeControlStatus` of the `AVPlayer` via `timeControlStatusObservation` (NSKeyValueObservation).
- Both observations are set up in `installPlaybackObservers` and torn down in `removePlaybackObservers`.
- The status observation handles initial and new values, and transitions to readyToPlay or failed.
- The timeControlStatus observation maps AVPlayer.TimeControlStatus to playback engine events (playing, waiting, paused).

**Potential Risks:**
- **Observation callbacks on invalidated observations**: The observation handlers are weakly captured and check `isShutdown` and generation match before proceeding. However, the observation itself is not invalidated until `removePlaybackObservers` is called. If the observation fires after the item has been replaced but before the observation is invalidated, the handler will check the generation and observed item and return early if they don't match. This is safe.
- **Missing observation for item.currentItemChange**: The engine does not observe changes to the player's current item (e.g., if the item is replaced externally). However, the engine only ever sets the item via `replaceCurrentItem` and relies on its own observation of the item's status. If the item were changed externally (which should not happen because the engine owns the player), it could cause inconsistency. But the engine is the only entity that should modify the player's current item.

**Existing Protections:**
- Observations are weakly captured in the closure and check `isShutdown` and generation.
- Observations are invalidated and set to nil during teardown.
- The engine only ever sets the player's current item and does not expect external changes.

**Missing Test Coverage:**
- Test that status observation correctly handles item replacement (loading a new source).
- Test that timeControlStatus observation correctly translates player status to engine events.

### 4. Periodic time observer registration and removal

**Findings:**
- The engine registers a periodic time observer with `player.addPeriodicTimeObserver` for every 0.5 seconds.
- The observer reads the current time and duration from the current item and emits a `.timeUpdated` event.
- The observer is removed in `removePlaybackObservers` by calling `player.removeTimeObserver(timeObserverToken)` and setting the token to nil.

**Potential Risks:**
- **Observer firing after removal**: The time observer token is invalidated when removed, but there is a window where the observer could fire after `removeTimeObserver` is called but before the token is set to nil? Actually, `removeTimeObserver` invalidates the token immediately, so subsequent firings should not occur. However, if the observer is already in the queue when `removeTimeObserver` is called, it might still fire. The handler checks `isCurrentItem` (which includes `isShutdown` and generation match) and `currentTime.isFinite` and `currentTime >= 0`. If the item has been replaced, the observer will return early. This is safe.
- **Observer not removed**: The token is set to nil after removal, so if `removePlaybackObservers` is called multiple times, the guard `if let timeObserverToken` will prevent trying to remove a nil token.

**Existing Protections:**
- The observer handler validates that it is still the current item and that the time is valid.
- The observer token is checked before removal and set to nil afterward.

**Missing Test Coverage:**
- Test that the time observer stops emitting events after shutdown or source replacement.
- Test that the time observer correctly reports current time and duration.

### 5. Notification observer registration and removal

**Findings:**
- The engine adds two notification observers:
  1. `.AVPlayerItemDidPlayToEndTime` for detecting normal playback completion.
  2. `.AVPlayerItemFailedToPlayToEndTime` for detecting asynchronous playback failures.
- Both observers are removed in `removePlaybackObservers` by calling `NotificationCenter.default.removeObserver` with the observer object and setting it to nil.

**Potential Risks:**
- **Observer firing after removal**: Similar to the time observer, if the notification is already in flight when the observer is removed, it might still be delivered. The handler checks `isCurrentItem` (including `isShutdown` and generation) and returns early if not matched. This is safe.
- **Observer not removed**: The observer objects are set to nil after removal, so subsequent calls to `removePlaybackObservers` will skip them.

**Existing Protections:**
- Notification handlers validate that they are still the current item and not shutdown.
- Observers are removed and set to nil.

**Missing Test Coverage:**
- Test that playback completion observers are removed after shutdown or source replacement.
- Test that failure observers are removed after shutdown or source replacement.

### 6. Pending readiness continuations and cancellation

**Findings:**
- The engine uses a `CheckedContinuation<Void, Error>` to wait for item readiness (status becomes readyToPlay or failed).
- The continuation is stored in `pendingReadiness` and the generation in `pendingLoadGeneration`.
- When the item status changes, `handleItemStatus` calls `completeReadiness` which resumes the continuation with success or failure.
- The continuation can be cancelled by the `load` task's cancellation handler, which calls `cancelPendingReadiness`.
- `cancelPendingReadiness` resumes the continuation with a `CancellationError` and clears the pending state.
- The controller's `load` method also creates a task that can be cancelled, and it checks for shutdown and generation match before proceeding.

**Potential Risks:**
- **Continuation resumed after being cancelled**: The `cancelPendingReadiness` method checks if the pending generation matches the provided generation (or nil) before resuming. This ensures that we only cancel the current pending readiness.
- **Continuation leaked**: If `completeReadiness` or `cancelPendingReadiness` is not called, the continuation would leak. However, every path that sets up the continuation ensures one of these is called:
  - In `load`, the continuation is set up and then either:
    - The item status observation calls `handleItemStatus` -> `completeReadiness`.
    - The task is cancelled -> the cancellation handler calls `cancelPendingReadiness`.
    - An error occurs in the `withTaskCancellationHandler` -> the `onCancel` calls `cancelPendingReadiness`.
  - Note: The `withTaskCancellationHandler` ensures that if the task is cancelled, the `onCancel` is called.
- **Generation mismatch**: The completion or cancellation checks that the pending generation matches the current load generation (or the engine's load generation) to avoid acting on a stale continuation.

**Existing Protections:**
- The continuation is always resumed in either success, failure, or cancellation.
- Generation checks prevent acting on stale continuations.
- The task cancellation handler ensures the continuation is cancelled if the task is cancelled.

**Missing Test Coverage:**
- Test that cancelling the load task results in a CancellationError.
- Test that a stale readiness continuation does not resume after a new load starts.
- Test that the continuation is properly cleaned up on shutdown.

### 7. AsyncStream creation, termination, and event delivery

**Findings:**
- The engine creates an `AsyncStream<PlaybackEngineEventEnvelope>` for its events.
- The continuation is stored in `eventContinuation`.
- Events are emitted via `emit(_:)` which yields an envelope with the current `activeSourceGeneration` and the event.
- The stream is terminated when `shutdown()` is called by finishing the continuation and setting it to nil.
- The controller exposes the engine's events via its `snapshots` property, which uses a `SnapshotBroadcaster` to broadcast snapshots to multiple subscribers.

**Potential Risks:**
- **Event emission after shutdown**: The `emit` method checks `isShutdown` and returns early if true, preventing events from being emitted after shutdown.
- **Continuation not finished**: The `shutdown` method finishes the continuation and sets it to nil, ensuring the stream terminates.
- **Event delivery after source replacement**: The engine's `events` stream is used by the controller's `observeEngineEvents` method, which filters envelopes by generation (`envelope.generation == self.loadGeneration`). This prevents events from a previous source from affecting the current source.
- **Snapshot broadcaster**: The broadcaster holds continuations for each subscriber and yields snapshots to all. When `finish` is called, it yields a final snapshot and finishes all continuations. The broadcaster does not automatically remove finished continuations, but they are removed when the subscriber's task ends (via `onTermination`).

**Existing Protections:**
- Events are checked for `isShutdown` before emission.
- The engine's event stream is filtered by generation in the controller.
- The snapshot broadcaster properly finishes continuations on termination and on explicit finish.

**Missing Test Coverage:**
- Test that events stop being emitted after shutdown.
- Test that events from a previous source are filtered out after a source replacement.
- Test that snapshot broadcaster continuations are cleaned up when subscribers cancel.

### 8. Load generation checks and stale-event protection

**Findings:**
- The controller uses a `loadGeneration` (UInt64) that is incremented at the start of each load.
- The engine also has a `loadGeneration` that is incremented at the start of each load in the engine.
- The controller's `load` method passes the generation to the engine's `load` method.
- The engine stores the generation as `activeSourceGeneration` (for event envelopes) and uses it in event envelopes.
- The controller's `observeEngineEvents` method filters incoming envelopes by comparing `envelope.generation` to `self.loadGeneration`.
- The engine's observer handlers (for item status, time control status, notifications) check that the item is still the current item and that the generation matches (`isCurrentItem` function checks `loadGeneration == generation`).

**Potential Risks:**
- **Generation overflow**: The generation is a UInt64, which is extremely unlikely to overflow in practice.
- **Generation mismatch due to late increment**: In the controller, `beginLoading` increments `loadGeneration` and returns the new generation. The engine's `load` method increments its own `loadGeneration` and sets `activeSourceGeneration`. These two generations are kept in sync because the controller passes its generation to the engine, and the engine increments its own generation and uses that as the active source generation. However, note that the controller's `loadGeneration` and the engine's `loadGeneration` are incremented separately but to the same value because they start at zero and are incremented once per load. They should stay in sync.
- **Stale event protection**: The controller's filter on generation ensures that events from a previous load are ignored. The engine's observers also check generation and item identity.

**Existing Protections:**
- Generation checks are used to filter out stale events.
- The generation is incremented atomically (though not atomic in the strict sense, but since we are on the main actor, it is serial).

**Missing Test Coverage:**
- Test that events from a previous load are ignored after a new load starts.
- Test that the generation increments correctly with each load.

### 9. Pending load and seek operations during source replacement or shutdown

**Findings:**
- The controller's `load` method cancels the existing `activeLoadTask` before starting a new load (in `beginLoading`).
- The controller's `seek` method does not have a pending seek task; it awaits the engine's seek directly. However, the engine's seek is asynchronous and can be awaited. If a new load starts while a seek is pending, the seek task will check for shutdown and generation match after awaiting the engine's seek.
- The engine's `seek` method does not have a cancellation mechanism; it is a simple async function that wraps the player's seek. However, the controller's seek task checks for shutdown and generation match after the await.

**Potential Risks:**
- **Seek completing after source replacement**: The controller's seek task awaits the engine's seek, then checks `!isShutdown` and `loadGeneration == generation`. If a new load has started, the generation will have changed, and the seek task will throw a `CancellationError`. This is correct.
- **Seek completing after shutdown**: The seek task checks `!isShutdown` after the await and throws a `shutdownFailure()` if shutdown is true. This is correct.
- **Load completing after source replacement**: The controller's load task is replaced by a new load task (the old one is cancelled in `beginLoading`). However, note that the old load task is cancelled, but if it was already at the point of awaiting the engine's load, the cancellation will cause the engine's load task to throw (via the cancellation handler). The controller's load task then catches the error and, if it's a cancellation error and the conditions are not met (isShutdown or generation mismatch), it re-throws. This is correct.
- **Load completing after shutdown**: Similar to above, the load task will check for shutdown and generation match and throw appropriately.

**Existing Protections:**
- Load tasks are cancelled when a new load starts.
- Seek and load tasks check for shutdown and generation match after awaiting the engine operation.
- The engine's load and seek operations respect cancellation (via the task's cancellation token).

**Missing Test Coverage:**
- Test that a seek is cancelled if a new load starts before it completes.
- Test that a load is cancelled if a new load starts before it completes.
- Test that a seek or load throws appropriately after shutdown.

### 10. Isolation between multiple player instances

**Findings:**
- Each `StreamPlayerController` creates its own `AVFoundationPlaybackEngine` instance (unless a custom engine is provided).
- Each engine owns its own `AVPlayer` instance.
- The controller's state (snapshot, tasks, generation) is independent per instance.
- The snapshot broadcaster is per controller, so snapshots are not shared.
- The engine's event stream is per engine, so events are not shared.

**Potential Risks:**
- **Shared resources**: There are no obvious shared resources (like static variables) that would break isolation.
- **Audio session**: The AVPlayer uses the shared audio session, but that is expected and not a resource leak.

**Existing Protections:**
- Each controller and engine instance owns its own resources.
- No static state is used that would break isolation.

**Missing Test Coverage:**
- Test that two controllers can operate independently without interfering.
- Test that shutting down one controller does not affect another.

## Existing Protections that are Already Correct

- The use of `isShutdown` flags to prevent operation after shutdown.
- The use of generation counts to stale-protect events and operations.
- Proper cancellation of tasks and resetting of task references.
- Proper invalidation and nilifying of observers and continuations.
- Weak capture of self in closures to avoid retain cycles.
- Checking `isCurrentItem` (or equivalent) in observation handlers to ensure they are still relevant.
- The controller's filtering of engine events by generation.
- The snapshot broadcaster's proper termination of continuations.

## Missing Test Coverage

Based on the above analysis, the following test cases are missing or insufficient:

1. **Concurrent shutdown**: Test calling `shutdown()` multiple times concurrently.
2. **Public methods after shutdown**: Test that `load`, `play`, `pause`, `seek` throw or return appropriately after shutdown.
3. **Event stream termination after shutdown**: Test that the engine's event stream finishes after shutdown.
4. **Observer removal after source replacement**: Test that observers from a previous source do not fire after a new source is loaded.
5. **Readiness continuation cancellation**: Test that cancelling a load task results in a `CancellationError`.
6. **Stale readiness continuation**: Test that a readiness continuation from a previous load does not resume after a new load starts.
7. **Event filtering by generation**: Test that events from a previous source are filtered out after a source replacement.
8. **Snapshot broadcaster cleanup**: Test that continuations are removed when subscribers cancel.
9. **Seek cancellation on new load**: Test that a seek is cancelled if a new load starts before it completes.
10. **Load cancellation on new load**: Test that a load is cancelled if a new load starts before it completes.
11. **Isolation between instances**: Test that two controllers can operate independently and that shutting down one does not affect another.
12. **Player item reset after shutdown**: Test that the player's current item is nil after shutdown.
13. **Time observer event emission**: Test that the time observer stops emitting events after shutdown or source replacement.
14. **Notification observer firing after removal**: Test that playback completion and failure observers do not fire after shutdown or source removal.

## Unnecessary Complexity

- The controller and engine both maintain a `loadGeneration`. While this is useful for stale-proofing, it could be simplified by having only one generation authority (e.g., the controller's generation passed to the engine and used there). However, the current approach is clear and not overly complex.
- The `SnapshotBroadcaster` is a reasonable abstraction for broadcasting snapshots to multiple subscribers. It is not unnecessary.
- The use of `AsyncStream` for events and snapshots is appropriate for the asynchronous nature of playback.

Overall, the codebase demonstrates a good understanding of lifecycle management and resource cleanup, with appropriate use of Swift concurrency and observation patterns. The identified risks are mostly mitigated by existing checks, but adding the missing test coverage would increase confidence before adding new features like FairPlay DRM, advertising, or Picture in Picture.

## Reconciliation Against Current Code and Tests — 2026-10-20

The checklist above is retained as a record of what the earlier review proposed;
these statuses supersede its blanket “missing” labels.

### Covered by current package tests

- Old-source events are ignored after a replacement (`ignoresEventFromPreviousSource`).
- Overlapping and repeatedly cancelled loads are covered, including stale load
  success/failure and a seek completing after a newer load starts.
- Cancellation of a pending AVFoundation load releases its item; shutdown while
  loading is covered at controller level.
- The engine event stream finishes on shutdown.
- Controller and engine isolation across multiple player instances is tested.
- Several operations after shutdown are tested (engine play/seek/rate and
  controller track/rate paths); controller shutdown during a pending load is
  also covered. This is representative coverage, not an assertion that every
  public method has an identical shutdown contract.
- Snapshot broadcasting and termination for a finished broadcaster are tested.

### Protected in code, but direct regression coverage is still absent

- Shutdown runs on the main actor and marks the controller shut down before its
  awaited engine cleanup. This makes the concurrent-shutdown race described in
  the old audit unlikely; a focused re-entrancy/idempotency test would still
  document the contract.
- The engine invalidates KVO observations and removes time/notification
  observers during item replacement and shutdown, with item/generation guards
  on callbacks. Tests do not directly assert that each AVFoundation callback
  source stops firing after teardown.
- The engine clears its current item on shutdown, but the existing direct
  current-item assertion is for a cancelled load, not an explicit shutdown.
- The broadcaster removes a subscriber continuation through `onTermination`,
  but there is no focused assertion that subscriber cancellation removes it.

### Still open at the package/device boundary

- Run UI lifecycle tests in a simulator-capable CI job for menu navigation,
  dismiss/reopen, and fullscreen return; the local UI bundle has compiled but
  simulator execution was unavailable.
- Validate background playback, routing, interruption variants, and repeated
  open/close behavior on devices. Siri pause/resume has been confirmed on one
  iPhone/OS version; that is not broad lifecycle acceptance.
- FairPlay renewal and real entitlement rejection need provider materials.
  Mock-provider error/cancellation tests do not emulate AVFoundation's real
  FairPlay challenge.

## Current Sample Follow-up — 2026-10-20

- Track menus clear and reload when a source changes. A source-revision guard
  prevents a cancelled or late lookup from restoring tracks from the previous
  source.
- The sample's bearer, FairPlay, and audio-session navigation targets now use
  stable accessibility identifiers. UI tests no longer depend on the composed
  title-plus-subtitle VoiceOver label.
- The audio-session playback-phase row also has a stable identifier so the UI
  test can locate it regardless of how SwiftUI composes its label and value.
- The updated CI workflow executes the demo and UI tests on an iOS Simulator.
  Local simulator verification passes; a hosted run remains pending.

## Presentation Follow-up — 2026-10-20

- Added `StreamAVPlayerView` as an optional AVKit-backed presentation surface.
  It uses the same controller/player and delegates standard playback controls,
  PiP, and AirPlay presentation to Apple's `AVPlayerViewController`.
- Added a separate **Presentation** menu example. It activates the playback
  audio session, exposes opt-in automatic PiP, and explains the host app's
  background-audio responsibility.
- Custom fullscreen requests landscape through the active scene and restores
  the orientation that was active before entry.
- Simulator UI coverage checks that the AVKit/PiP destination and its setting
  are reachable, and that the custom fullscreen cover can open and close. PiP
  activation/restoration and actual orientation transitions still require
  physical-device verification.
