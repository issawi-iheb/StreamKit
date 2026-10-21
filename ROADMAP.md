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
- **Implemented; Siri interruption verified on a physical iPhone running iOS 26.5** — Playback paused when Siri took audio focus and resumed afterward. Unit tests also cover allowed resumption, system-disallowed resumption, and explicit pause during an interruption. Background playback, other interruption sources, routing changes, and behavior across supported OS versions remain unverified. The host app owns process-wide audio-session configuration and the background-audio capability; multiple controllers handle interruptions independently, without shared audio-focus arbitration.
- **Implemented, pending live protected-origin validation** — `MediaBearerAuthentication` supplies per-resource bearer tokens through a custom AVFoundation resource loader; HLS child URLs are rewritten, HTTPS is required, tokens are scoped to exact trusted hosts, and finite/open-ended byte ranges validate status, `Content-Range`, and response length. Generic arbitrary-header configuration remains absent.
- **Implemented, simulator-verified** — The demo has a separate Protected Playback menu section. It resets track choices by source revision and rejects stale track-discovery results after a source change. Stable accessibility identifiers support its navigation tests. Playlist/Playback Events remain planned placeholders.
- **Verified by unit tests** — 111 Swift package tests pass, including range construction/validation, stale range sizes, replay behavior, token refresh callbacks, host scoping, playlist rewriting, interruption recovery, cookie isolation, and FairPlay exchange failures/redaction/cancellation.
- **Verified on iOS Simulator** — All 8 demo unit/UI tests pass on iPhone 17 Pro / iOS 26.5. This confirms sample navigation, fullscreen enter/exit, and presentation configuration UI, not actual system PiP or physical-device orientation behavior.
- **User-verified** — Basic playback works in the demo; the user also verified protected playback of the public Axinom FairPlay vector. This does not verify a customer-controlled origin or production DRM configuration.
- **Implemented and unit-tested** — Autoplay now waits for AVFoundation's observed playing/waiting state before reporting the phase. Authenticated requests use only explicitly configured cookies, not shared app cookie storage.
- **CI updated; hosted run pending** — GitHub Actions now runs the demo and UI tests on an iPhone 17 Pro simulator instead of only compiling the test bundle. Local simulator verification passes; the updated workflow still needs a hosted run.
- **Implemented, simulator/build verification pending** — Public `StreamAVPlayerView` presents the same controller through `AVPlayerViewController` with system playback/PiP/AirPlay controls and opt-in automatic PiP. The demo has a separate AVKit/PiP entry, configures playback audio, and requests landscape for custom fullscreen; device PiP and rotation acceptance remain required.

### NEXT:
- When protected-stream test materials are available, verify bearer authentication against a controlled HTTPS HLS origin: master and child playlists, segments, keys, ranges, redirects, token refresh, and cancellation on iOS. Public samples do not provide reusable bearer-protected media.
- Validate failure mappings against representative real AVFoundation failures and refine unmapped cases.
- Verify user pause during a real interruption, background playback, other interruption sources, cancellation, and audio routing on iOS 16+ devices and additional supported OS versions. Siri interruption and automatic resumption were confirmed on the user's iPhone running iOS 26.5.
- Define and verify audio-focus behavior when multiple controllers have play intent; decide whether the host or StreamKit coordinates which controller resumes.
- The demo target is currently set to iOS 26.5 to allow installation on the user's iOS 26.5 device. This still does not demonstrate the package's iOS 16+ support floor; decide whether to lower the demo to iOS 17 (Swift Observation floor) and verify against that runtime.
- Make the audio-session sample's deactivation/ownership behavior explicit when leaving the example screen.
- Run the updated simulator test action in hosted CI and add leave/reopen lifecycle coverage; the current eight demo tests cover menu navigation, fullscreen enter/exit, and input presentation but not repeated leave/reopen or system PiP lifecycle.
- Verify PiP start, background transition, restoration to the demo route, and stop on a physical device; verify custom fullscreen enters landscape and restores the prior orientation on iPhone and iPad. Simulator tests can verify navigation and configuration UI, not system PiP behavior.
- Decide whether StreamKit needs its own custom-controls PiP coordinator. The current public option intentionally delegates PiP behavior and restoration to AVKit's standard player UI.
- Profile lifecycle cleanup and playback behavior with real HLS and progressive media.
- Launch the demo on an iOS simulator and run the new bearer-auth screen when simulator services are available; generic iOS Simulator build succeeds.
- Confirm the 32× playback-rate policy against product requirements before release.

## PHASE 2 — FairPlay DRM

### CURRENT IMPLEMENTATION STATUS — IN PROGRESS
- **Implemented, package-compiled; exchange unit-tested** — Public `FairPlayLicenseProvider`, `FairPlayLicenseRequest`, and `FairPlayConfiguration` define the app/SDK boundary. The AVFoundation engine creates an `AVContentKeySession` for configured media, attaches the `AVURLAsset`, generates SPC data, sends it to the provider, wraps returned CKC data, routes renewal requests, and cancels/removes item resources on teardown. The isolated exchange validates the content ID, certificate, SPC, CKC, and cancellation checkpoints; request responses are guarded against double completion during teardown races.
- **Axinom public test playback verified in a live run** — The demo has a dedicated FairPlay screen for Axinom's public protected HLS vector. It preloads the public evaluation License Service Message token, fetches the evaluation FPS certificate, sends the AVFoundation SPC to the configurable license endpoint with `X-AxDRM-Message`, and returns CKC bytes. The public generic FairPlay endpoint is prefilled; tenant-specific values remain editable. User-provided diagnostics confirm license HTTP 200, AVFoundation accepted the content-key response, and playback reached `.playing`. Renewal, expiry/failure, cancellation, and source-switching still need validation. The app-specific provider lives in the demo and adds no vendor dependency to StreamKit.
- **Unsupported** — Persistable/offline content keys are rejected by this initial online-playback implementation.

### ACCEPTANCE CRITERIA:
- **Verified in code/package compilation; public-vector playback user-verified** — Modular FairPlay integration boundary and Axinom demo harness implemented; device diagnostics confirm public test playback
- **Implemented, requires provider validation** — Certificate acquisition, SPC generation, and CKC processing path
- **Implemented; renewal callback is unit-tested, end-to-end renewal is provider-dependent** — License acquisition and renewal callbacks
- **Implemented, package behavior verified only** — Failure redaction and cancellation/teardown handling. Mock provider tests cover a simulated license rejection, a network error, empty CKC, redaction, and cancellation while awaiting the provider. They verify exchange behavior, not HTTP parsing, AVFoundation's real FairPlay exchange, or renewal.
- **Verified in the live Axinom public-vector run** — Protected HLS playback reached `.playing` after a successful license response and AVFoundation content-key acceptance
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

## PHASE 5 — Advanced playback and presentation

### ACCEPTANCE CRITERIA:
- **Implemented, device validation pending** — System PiP and AirPlay controls are available through the optional AVKit-backed `StreamAVPlayerView`. Custom-layer PiP is available through `StreamPictureInPictureController`; a bespoke control overlay inside PiP is not included.
- **Implemented in demo, device validation pending** — Custom fullscreen requests landscape and restores the orientation active before presentation. No package-wide orientation policy is imposed on consuming apps.
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

- **Latest commit**: `bce7c70` (fix: harden playback ranges and replay lifecycle). The current working tree contains the presentation follow-up described below; it is not committed yet.
- **Current phase**: Phase 2 — FairPlay core and public Axinom test-vector playback are implemented/verified; DRM lifecycle and production-provider acceptance remain in progress. Phase 1 production-readiness issues remain open.
- **Latest local test result (2026-10-20)**: `swift test` passes **111 tests in 11 suites**; `xcodebuild test` passes **8 demo unit/UI tests** on iPhone 17 Pro / iOS 26.5 Simulator. The UI suite covers navigation to AVKit/PiP settings and custom fullscreen enter/exit. It cannot verify real PiP or device rotation. The updated GitHub workflow's hosted run remains pending. Protected-origin playback, FairPlay renewal/rejection, background/routing behavior, and the package's iOS 16 floor remain unverified.
- **Current audit**: [PRODUCTION_READINESS_AUDIT.md](PRODUCTION_READINESS_AUDIT.md) includes the 2026-10-19 full SDK reassessment and the 2026-10-20 architecture and SDK comparison. StreamKit is not yet production-ready against Phase 1 criteria.
- **Next milestone**: Build and run the new AVKit/PiP presentation sample, then verify user-started and automatic PiP, restoration, and fullscreen orientation on a physical iPhone/iPad. The system-player API delegates PiP and AirPlay UI to AVKit; custom UI PiP remains a separate future design decision. Then close the iOS support-floor and hosted-CI lifecycle gaps. Protected-origin and FairPlay lifecycle acceptance remain dependent on suitable provider materials.
