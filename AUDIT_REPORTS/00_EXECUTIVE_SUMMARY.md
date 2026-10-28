# StreamKit production-readiness audit

## Current branch addendum — 2026-10-28

The latest focused SDK/demo update is documented in [12_CURRENT_STATE_AND_DEMO_UX.md](12_CURRENT_STATE_AND_DEMO_UX.md). It records the managed, app-owned-controls, and advanced AVKit integration boundaries, refreshed demo visuals, and a passing managed-player fullscreen UI test on iPhone Duo / iOS 27.1 Simulator. This does not supersede the broader open production-readiness findings below; in particular, hardware PiP/restoration and minimum-iOS validation remain open.

## Implementation follow-up — 2026-10-21

The follow-up implementation added controller command-generation guards for stale play/pause completions, suppressed invalid initial AVPlayer paused events during loading, preserved cancellation from bearer token providers, and moved standalone demo controller/PiP ownership into a retained playback session. README and architecture guidance now explain snapshot actor context, route/PiP ownership, and host-side audio focus. These are targeted reliability and integration improvements; they do not close seek-ordering, real PiP, FairPlay lifecycle, or minimum-OS validation gaps.

Latest checks on this checkout: **115 package tests pass**, generic iOS demo build and simulator `build-for-testing` pass, and **4 demo unit tests pass** on iPhone 17 Pro / iOS 26.5 Simulator. UI tests were attempted but produced no result because the run stalled on Xcode debugger-version lookup warnings and was interrupted. Physical-device PiP was not revalidated. StreamKit remains **not yet demonstrated production-ready**.

## Assessment

**Overall: promising early SDK / not yet demonstrated production-ready.** The core has a clear per-controller ownership model, a typed intent/phase snapshot, generation-tagged engine events, isolated subscriber streams, and provider-neutral FairPlay integration. The authored tests cover many controller races and deterministic DRM/auth helpers. No source changes were made by this audit.

**Audited revision:** `bce7c700f2b2191218d73e1be399956e5aa2cbb8` (`main`, `origin/main` at inspection). **Working tree:** already dirty before audit; 11 tracked files modified and 5 untracked paths existed, including player/view source, demo, tests, and docs. These changes were not authored or reverted here and are part of the inspected checkout. Audit files are the only additions made during this task.

## Highest risk

- **PLAY-001 / CONC-001 (potential risk):** overlapping seeks are checked against item generation, but not against seek-operation identity; completion callbacks can arrive after a later seek and controller snapshot writes the requested target. Verify AVPlayer's completion ordering and specify last-request-wins behavior.
- **CONC-002 (potential risk):** `LoadHandle.cancel()` cancels the task shared by readiness waiters. This is documented, but the SDK should clarify whether one consumer is allowed to cancel readiness for every holder of the handle and test concurrent wait/cancel behavior.
- **DRM-001 (test gap):** FairPlay request completion and invalidation have guarded exactly-once handling, but real provider renewal/replacement and simultaneous protected players are not established by mock tests alone.
- **PIP-001 / FULL-001 (test gap):** PiP and custom fullscreen behavior are present; lifecycle, restoration, and orientation validation require device/app integration. No PiP/fullscreen test suite was found.
- **TEST-001 (confirmed limitation):** `swift test` could not compile the manifest because sandbox access to `/Users/ihebI/.cache/clang/ModuleCache` was denied. Re-running with an external scratch path still failed under sandbox setup. No test result is claimed.

No confirmed P0 defect was established by this static audit. The findings register has **17 findings: 0 Critical, 3 High, 12 Medium, 2 Low** (severity is impact if the scenario occurs, not confidence). Classifications are stated per finding.

## Top actions

1. Specify and validate overlapping-seek completion semantics (PLAY-001).
2. Run the package suite in a host with a writable Swift module cache and retain output (TEST-001).
3. Add hardware PiP start/stop/restoration tests and consumer lifecycle instructions (PIP-001).
4. Validate FairPlay renewal, replacement while pending, failure redaction, and two simultaneous protected instances with provider fixtures (DRM-001).
5. Exercise cancellation while AVFoundation's SPC callback is outstanding; bridge cancellation where supported (DRM-002).
6. Clarify `LoadHandle` cancellation ownership and test two waiters (CONC-002).
7. Add a reproducible CI matrix for Swift package resolution, iOS simulator compilation, and package tests (DEP-001).
8. Document and test the public API lifecycle contract in a consumer target (API-001).
9. Verify indefinite/live duration and seekable-range behavior with representative HLS streams (PLAY-002).
10. Maintain a security boundary for app-provided tokens and avoid credentials in sample source except documented public evaluation material (SEC-001).

## Scope and limitations

Inspected `Package.swift`, all `Sources/StreamKit`, package tests, demo/project configuration, and package documentation; mapped actual engine, controller, views, PiP, auth loader, and key session paths. No tests, device runs, Xcode project builds, network/license exchanges, performance measurements, or source edits were performed. The repository documentation reports a prior public Axinom test-vector run; that is recorded as repository-reported evidence, not independently reproduced. Findings requiring runtime confirmation are not presented as proven defects.
