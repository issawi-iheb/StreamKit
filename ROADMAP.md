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
- **Implemented, unit tested; runtime verification pending** — Controllers observe audio-session interruptions, pause their own engine, and resume only when playback was requested before the interruption, automatic resumption is enabled, and iOS supplies `.shouldResume`. An explicit pause during the interruption cancels resumption. The host app owns process-wide audio-session configuration and the background-audio capability; the demo configures playback mode and includes an Audio Session & Background Playback example. Multiple controllers handle the same interruption independently; shared audio-focus arbitration is not implemented.
- **Implemented, pending live iOS validation** — `MediaBearerAuthentication` supplies per-resource bearer tokens through a custom AVFoundation resource loader; HLS child URLs are rewritten, HTTPS is required, and tokens are scoped to exact trusted hosts. Generic arbitrary-header configuration remains absent.
- **Implemented, not iOS-verified** — The demo has a separate Protected Playback menu section, prefilled with a public Mux HLS baseline and its trusted host. A blank token loads ordinary HLS; entering a token exercises the bearer path for a protected URL. This public sample is not an authenticated stream. Runtime `snapshot.failure` is displayed and player controllers shut down when their owning views leave. Playlist/Playback Events remain planned placeholders; a UI navigation assertion was added.
- **Verified by unit tests** — 86 Swift package tests pass, including per-resource token refresh callbacks, request construction, host scoping, playlist rewriting, interruption recovery policy, autoplay state, and cookie isolation.
- **User-verified** — Basic playback works in the demo on an iOS simulator or device. The exact device and OS version were not recorded; protected HLS is still awaiting suitable test materials.
- **Implemented and unit-tested** — Autoplay now waits for AVFoundation's observed playing/waiting state before reporting the phase. Authenticated requests use only explicitly configured cookies, not shared app cookie storage.
- **Verified in hosted CI** — GitHub Actions passed package tests and built the demo and UI test bundle on the Xcode 27 runner (run 38916346546). This compiles the UI tests but does not execute simulator playback or interruption tests.

### NEXT:
- When protected-stream test materials are available, verify bearer authentication against a controlled HTTPS HLS origin: master and child playlists, segments, keys, ranges, redirects, token refresh, and cancellation on iOS. Public samples do not provide reusable bearer-protected media.
- Validate failure mappings against representative real AVFoundation failures and refine unmapped cases.
- Verify interruption begin/end, user pause during interruption, background playback, cancellation, and audio routing on iOS 16+ devices and additional supported OS versions.
- Define and verify audio-focus behavior when multiple controllers have play intent; decide whether the host or StreamKit coordinates which controller resumes.
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
- **Partial** — Audio-session interruption recovery and demo background-audio configuration are implemented; device and supported-OS verification remains open.
- Live-stream and live-edge behavior handled
- Low-latency HLS assessment completed
- Network recovery mechanisms verified

## PHASE 6 — Commercial SDK readiness

### ACCEPTANCE CRITERIA:
- Public API defined with compatibility policy
- Integration documentation and SwiftUI/UIKit examples provided
- DRM and advertising documentation completed
- CI pipeline and end-to-end tests established
- **Partial** — GitHub Actions has a successful hosted run for package tests and demo/UI-test-bundle compilation. End-to-end playback tests remain outstanding.
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

- **Baseline commit before this work**: 9e5e160 (Fix autoplay state and isolate authenticated cookies)
- **Current phase**: Phase 1 — Core stabilization and production readiness
- **Latest test result**: 86 Swift tests in 10 suites passed locally on macOS arm64, including an injected audio-interruption-source integration test; the demo and UI test bundle build for generic iOS Simulator succeeds, and the built app declares `UIBackgroundModes = [audio]`. Demo audio-session activation is asynchronous on iOS 27+ and dispatched off the main thread on earlier supported versions. Hosted CI run 38916346546 succeeded on the prior commit; the new interruption changes are not yet hosted-verified. Basic playback was confirmed by the user on a simulator or device; protected HLS and automated UI runtime tests remain unverified. Interactive Simulator launch could not be attempted because CoreSimulatorService has no available runtime in this environment.
- **Current audit**: [PRODUCTION_READINESS_AUDIT.md](PRODUCTION_READINESS_AUDIT.md) includes a 2026-10-16 reassessment. StreamKit is not yet production-ready against Phase 1 criteria.
- **Next milestone**: Define multi-controller audio-focus behavior, then validate real interruption notifications and background-audio behavior on supported iOS devices and versions. Continue lifecycle and minimum-supported-iOS verification. Resume protected-HLS verification when a controlled origin and credentials are available.
