# StreamKit Roadmap

## PROJECT GOAL

StreamKit is a reusable, production-grade iOS media-player SDK built on
AVFoundation. It should support multiple simultaneous player instances,
own playback orchestration and normalized state/events/errors, and provide
separate integration boundaries for DRM and advertising.

## STATUS LEGEND
- **Implemented**: Functionality exists in the codebase
- **Verified**: Acceptance criteria demonstrated through tests/platform verification
- **In progress**: Work started but acceptance criteria incomplete
- **Planned**: Work not started
- **Not assessed**: Implementation/behavior not sufficiently inspected

## PHASE 1 — Core stabilization and production readiness

### COMPLETED IMPLEMENTATION:
- Swift Package architecture targeting iOS 16+.
- PlaybackEngine abstraction and AVFoundationPlaybackEngine.
- Public StreamPlayerController API.
- Independent playback engine/controller instances.
- Normalized playback snapshots, intents, events and errors.
- Loading, cancellation and stale-operation protection.
- Play, pause, seek and shutdown.
- Audio and subtitle selection.
- Playback-speed support and validation.
- Snapshot broadcasting.
- **Partial** — SwiftUI standalone and concurrent-player demos with native audio, subtitle, seeking and speed controls; Playlist and Playback Events remain labeled placeholders.
- Automated unit tests for implemented behavior.

### ACCEPTANCE CRITERIA STATUS:
- **In progress** — Lifecycle audit: shutdown paths and observer cleanup reviewed; device leak profiling remains outstanding.
- **In progress** — Cancellation audit: stale and overlapping loads covered by unit tests; cancellation during live AVFoundation operations needs platform verification.
- **Verified by code review** — Concurrency and actor isolation; this is not a formal data-race proof.
- **Verified by unit tests** — Intent/phase coordination, buffering transitions, and stale event handling.
- **Implemented, unit tested** — AVFoundation network errors, common parse/format failures, and wrapped underlying URL errors map to stable `.network`, `.unsupportedFormat`, and `.playback` categories. Other AVFoundation errors remain coarse.
- **Verified by unit tests** — Multiple controller/engine isolation.
- **Not verified** — iOS 16+ behavior across supported OS versions and physical devices.
- **In progress** — Regression coverage includes unknown-duration updates, repeated overlapping loads, explicit cancellation, and pending-item cleanup; real live AVFoundation behavior remains unverified.
- **Assessed, not implemented** — No audio-session interruption or app-background handling exists in the SDK or demo. The controller now reports `.paused` while preserving `.play` intent when the engine pauses. The host app should configure process-wide `AVAudioSession`; resume policy and background behavior need definition before Phase 5.
- **Implemented, pending live iOS validation** — `MediaBearerAuthentication` supplies per-resource bearer tokens through a custom AVFoundation resource loader; HLS child URLs are rewritten, HTTPS is required, and tokens are scoped to exact trusted hosts. Generic arbitrary-header configuration remains absent.
- **Implemented, not iOS-verified** — The demo has a separate Protected Playback menu section, prefilled with a public Mux HLS baseline and its trusted host. A blank token loads ordinary HLS; entering a token exercises the bearer path for a protected URL. This public sample is not an authenticated stream. Runtime `snapshot.failure` is displayed and player controllers shut down when their owning views leave. Playlist/Playback Events remain planned placeholders; a UI navigation assertion was added.
- **Verified by unit tests** — 79 Swift package tests pass, including per-resource token refresh callbacks, request construction, host scoping, playlist rewriting, insecure-child rejection, and authentication-error propagation.

### NEXT:
- Arrange a controlled HTTPS HLS origin that requires a bearer header, then verify master and child playlists, segments, keys, range requests, CDN redirects, token refresh, and cancellation on iOS. Public HLS samples found so far do not provide reusable bearer-protected media.
- Validate failure mappings against representative real AVFoundation failures and refine unmapped cases.
- Confirm audio-session ownership and interruption-state semantics before Phase 5 implementation.
- Verify playback, cancellation, backgrounding, and routing on iOS 16+ devices and additional supported OS versions.
- Profile lifecycle cleanup and playback behavior with real HLS and progressive media.
- Launch the demo on an iOS simulator and run the new bearer-auth screen when simulator services are available; generic iOS Simulator build succeeds.
- Confirm the 32× playback-rate policy against product requirements before release.

## PHASE 2 — FairPlay DRM

### ACCEPTANCE CRITERIA:
- Modular FairPlay integration boundary defined and implemented
- Certificate acquisition, SPC generation, and CKC processing functional
- License acquisition and renewal integrated where applicable
- Failures and cancellation handled gracefully
- Protected HLS playback verified
- Provider requirements documented

## PHASE 3 — Analytics and diagnostics

### ACCEPTANCE CRITERIA:
- Startup, buffering, failure, and playback metrics normalized
- Provider interfaces defined and implementable
- Analytics integrations kept outside core (no direct dependencies)
- Sensitive information excluded from diagnostics
- Metrics collection verified with test providers

## PHASE 4 — Advertising

### ACCEPTANCE CRITERIA:
- Modular CSAI and SSAI integration boundaries defined
- Ad playback events and transitions modeled
- Seeking restrictions and ad-break behavior defined
- Provider integrations implemented and tested
- Regression tests for ad playback scenarios

## PHASE 5 — Advanced playback

### ACCEPTANCE CRITERIA:
- Picture in Picture functionality implemented and verified
- AirPlay routing supported
- Background playback with audio-session integration
- Live-stream and live-edge behavior handled
- Low-latency HLS assessment completed
- Network recovery mechanisms verified

## PHASE 6 — Commercial SDK readiness

### ACCEPTANCE CRITERIA:
- Public API defined with compatibility policy
- Integration documentation and SwiftUI/UIKit examples provided
- DRM and advertising documentation completed
- CI pipeline and end-to-end tests established
- Semantic versioning and release process defined
- Licensing and distribution review completed
- Migration and deprecation policy established

## DOCUMENTATION RULES

- Distinguish implemented, verified, in progress, planned and not assessed.
- Do not claim production readiness before the relevant audits and tests pass.
- Do not mark a feature complete merely because code exists.
- Include acceptance criteria for each phase.
- Include a short "Current status" section with the latest known commit
  and the next milestone.
- Keep the roadmap concise, maintainable and technically accurate.
- Avoid inventing completion dates or commitments.
- Record uncertainty where repository evidence is insufficient.

## CURRENT STATUS

- **Latest commit**: 048241d (Add bearer-authenticated HLS playback)
- **Current phase**: Phase 1 — Core stabilization and production readiness
- **Workspace changes since that commit**: the protected-playback demo menu separation, prefilled public HLS baseline with optional bearer flow, updated UI test selector, and corresponding documentation updates; these changes are not committed.
- **Latest test result**: 79 Swift tests in 10 suites passed on macOS arm64; generic iOS Simulator build-for-testing succeeded for the SDK, demo, and UI test bundle. CoreSimulatorService was unavailable, so simulator/device runtime and OS-version verification has not been performed.
- **Current audit**: [PRODUCTION_READINESS_AUDIT.md](PRODUCTION_READINESS_AUDIT.md) includes a 2026-10-16 reassessment. StreamKit is not yet production-ready against Phase 1 criteria.
- **Next milestone**: Validate bearer-authenticated HLS on iOS against a protected origin (including child resources, CDN redirects, token refresh, and cancellation), then complete remaining Phase 1 device checks.
