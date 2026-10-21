# Playback engine and state machine

`PlaybackIntent` and `PlaybackPhase` are separate, immutable snapshot fields. The controller owns state publication; engine KVO/time/end/failure observations translate AVFoundation signals to internal events. The controller filters all incoming envelopes by current load generation and filters `.playing`/`.waiting` against play intent (`StreamPlayerController.swift:515-569`). The engine filters item callbacks by both item identity and engine generation (`AVFoundationPlaybackEngine.swift:467-500`). This is a strong foundation; enum definitions alone do not enforce legal transitions.

## Load and state path

`load()` advances generation and publishes `.loading`; engine replaces item, installs observers and awaits status (`StreamPlayerController.swift:110-221`; `AVFoundationPlaybackEngine.swift:69-167`). The engine's checked continuation is stored alongside `pendingLoadGeneration`; status completion clears it and invalidates KVO before resuming. Failure mapping normalizes common URL and AVFoundation failures (`PlaybackFailureMapping.swift`). Controller load failure sets `.failed` and maps cancellation separately.

Pause updates intent before awaiting engine pause; a reentrant late event will be ignored if it conflicts with intent. Event task and snapshot publication are main-actor isolated. `timeUpdated` preserves unknown duration if AVFoundation reports no finite duration. Durations are optional, which is compatible with live media, but seekability is not represented in `PlaybackSnapshot`.

## Findings

**PLAY-001 — High, Potential risk:** engine `seek(to:)` captures item generation and checks only that the same item is current after awaiting `AVPlayer.seek` (`Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift:714-753`). Controller `seek(to:)` captures load generation and writes its argument into snapshot after await (`Sources/StreamKit/PublicAPI/StreamPlayerController.swift:377-411`). Two concurrent seeks to one item can both pass generation checks; unless AVPlayer guarantees the earlier completion is canceled/reported false in all relevant cases, an older continuation may publish a target inconsistent with the final playhead. Add monotonically increasing seek identity per item and define last-request-wins; after completion, publish actual player current time or a verified result. Do not assume temporal ordering. Suggested test in concurrency report. Severity High reflects user-visible timeline/control corruption, but confidence is Potential risk pending device reproduction.

**PLAY-002 — Medium, Enhancement/test gap:** controller exposes only scalar time and duration (`PlaybackSnapshot.swift:12-19`). For live/indefinite HLS, duration may be unknown and seekable window can move. Seeking validates finite nonnegative values, but does not expose seekable ranges or clarify clamping (`AVFoundationPlaybackEngine.swift:714-738`). Keep current API for VOD; before marketing full live HLS support, add a separate seekable-range model and map AVPlayerItem.seekableTimeRanges, with tests for sliding windows and discontinuities.

**PLAY-003 — Medium, Test gap:** event handling covers end/failure/time/time-control; network retry policy is absent. This is an SDK policy choice, not an automatic defect. Document that retries/recovery are consumer-managed or add an opt-in bounded policy only after requirements define retryable failures, backoff, and source idempotency. Tests currently cover state transitions and stale load results, not AVPlayer live recovery.

## Evidence and test inventory

`StreamPlayerControllerTests.swift` includes overlapping-load, stale-load, stale-failure, stale-seek-after-reload, pause/intent, waiting, end/replay, tracks, interruption, multi-controller and rate scenarios. `AVFoundationPlaybackEngineTests.swift` verifies shutdown, invalid source, independent engines and rate constraints. Unit tests with AVPlayer on macOS cannot substitute for iOS simulator/device streaming behavior.

## Exact proposed change

PLAY-001: target `Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift:714-753` and `Sources/StreamKit/PublicAPI/StreamPlayerController.swift:377-411`. Add a `seekGeneration` counter incremented before each engine seek; after await require both item generation and seek token match. Return a seek result (or expose actual current time) so controller does not blindly write an obsolete requested value. If the engine protocol's `seek` return type changes, update `PlaybackEngine.swift` and `MockPlaybackEngine.swift`. Proposed pseudocode/diff and test are in `11_PATCH_PROPOSALS.md`; validate AVFoundation `completed` semantics before choosing whether superseded seeks throw `CancellationError` or return superseded status.
