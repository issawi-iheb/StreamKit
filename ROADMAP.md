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
- SwiftUI demo player with native audio, subtitle and speed menus.
- Automated unit tests for implemented behavior.

### ACCEPTANCE CRITERIA (NOT YET MET):
- Lifecycle audit: shutdown safety, resource cleanup, no leaks
- Cancellation audit: operations cancel cleanly, no stale continuations
- Concurrency audit: Swift concurrency correctness, actor isolation
- Playback state transitions: intent/phase coordination, buffering behavior
- Error handling: proper error propagation and recovery
- Multiple simultaneous players: isolated instances, no interference
- Platform compatibility: iOS 16+ behavior verified
- Regression tests: existing functionality preserved
- Full test suite: all tests pass

### NEXT:
- Audit lifecycle, cancellation and shutdown.
- Audit Swift concurrency and actor isolation.
- Audit playback state transitions and error propagation.
- Verify seeking, buffering, ended state and live streams.
- Assess audio interruptions and recovery.
- Test multiple simultaneous players.
- Identify missing regression tests.
- Fix confirmed issues and rerun the full test suite.
- Verify supported platform and OS-version behavior.

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

- **Latest commit**: 29d9411 (Add playback rate support and improve demo player controls)
- **Current phase**: Phase 1 — Core stabilization and production readiness
- **Next milestone**: Complete the audit items listed under Phase 1 "NEXT" and rerun the full test suite.
