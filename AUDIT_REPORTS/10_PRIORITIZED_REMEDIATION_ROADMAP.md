# Prioritized remediation roadmap

P0 means a confirmed critical defect; **no P0 action is warranted by this audit**.

## P1 — High priority

### P1.1 Specify concurrent seek behavior (PLAY-001)
- **Files:** `Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift`, `Sources/StreamKit/PublicAPI/StreamPlayerController.swift`, protocol/mock if return semantics change, controller tests.
- **Approach:** prove AVPlayer callback behavior; add seek operation token and publish only the latest accepted seek result/actual playhead.
- **Order/dependencies:** first, after device or AVFoundation API verification.
- **Risk/compatibility:** changing protocol return shape is internal; cancellation/failure behavior is observable public behavior and needs documentation.
- **Tests/acceptance:** out-of-order completion regression; snapshot matches AVPlayer current time and stale completion is not published.
- **Effort:** M — cross-layer behavior plus deterministic async test.

### P1.2 Validate PiP and FairPlay in real integration (PIP-001, DRM-001, DRM-002)
- **Files:** new tests `Tests/StreamKitTests/PictureInPictureControllerTests.swift`, `FairPlayContentKeySessionTests.swift`; existing demo UI tests; only source if reproduced defect justifies it.
- **Approach:** deterministic callback seams first, then physical device with provider-approved test media/credentials; cover cancellation, renewal, source switch, multiple players and restoration.
- **Dependencies:** device, app capability setup, external DRM fixture.
- **Risk/compatibility:** tests must never store or log protected payloads or production credentials.
- **Acceptance:** each AVFoundation key request completes at most once; PiP restoration returns to correct host UI; two instances remain isolated.
- **Effort:** L — requires seam and hardware/provider coordination.

## P2 — Reliability

### P2.1 CI and validation baseline (DEP-001, CONC-002, TEST-001)
- **Files:** new `.github/workflows/` config; possibly test destination setup only if necessary.
- **Approach:** run `swift test`, release build, and iOS simulator consumer build; one minimum supported OS compile. Keep package dependencies unchanged.
- **Ordering:** prerequisite for ongoing changes; capture test results from a writable runner.
- **Risk:** simulator versions differ; pin only maintained runner/toolchain.
- **Acceptance:** green CI on PR; no unsupported platform assumptions; Swift 6.4 manifest and target compile.
- **Effort:** M — workflow and stable simulator provisioning.

### P2.2 Bearer redirects and cancellation tests (SEC-001, CONC-001)
- **Files:** `AuthenticatedMediaResourceLoaderTests.swift`, `StreamPlayerControllerTests.swift`; source only if a test proves policy defect.
- **Approach:** redirect matrix (trusted HTTPS, untrusted HTTPS, downgrade), token refresh/cancellation and two waiters sharing handle.
- **Dependencies:** injectable URL loading or local test server; settle LoadHandle contract.
- **Acceptance:** no bearer token reaches an untrusted/insecure destination; handle cancellation follows documented shared-operation semantics.
- **Effort:** M — async networking seam and race cases.

### P2.3 Public integration contract and view lifecycle tests (API-001, VIDEO-001, FULL-001)
- **Files:** `README.md` or new public integration guide; demo UI test file; external consumer target.
- **Approach:** document ownership/cleanup/audio/PiP/track ID lifetime; compile public-only integration; verify SwiftUI rebind and fullscreen demo flow.
- **Risk:** docs must match package API at the inspected revision.
- **Acceptance:** app can follow integration example without internal imports; tests exercise lifecycle and orientation transitions.
- **Effort:** M — public guide plus simulator/device coverage.

## P3 — Strategic enhancements

### P3.1 Live seekable-range API (PLAY-002)
- **Files:** `PlaybackSnapshot.swift`, `AVFoundationPlaybackEngine.swift`, events/tests/docs.
- **Approach:** add seekable ranges only if live-stream UX is a supported requirement; expose absolute time ranges and update on discontinuity/window movement.
- **Dependencies:** product semantics and representative HLS fixtures.
- **Risk:** public API compatibility and timeline semantics.
- **Acceptance:** live window seeks and unknown duration represented correctly.
- **Effort:** L — model, events, API evolution and live integration tests.

### P3.2 Optional rendering seam and track API refinements (ARCH-001, AUDIO-001, API-002)
- **Files:** controller/render view boundary and MediaTrack docs/API tests.
- **Approach:** only introduce a render protocol when a second backend exists; document track IDs as current-item handles.
- **Acceptance:** no unnecessary abstractions; external API compiles and explicitly marks item lifetime.
- **Effort:** S for docs; M if a second backend drives an abstraction.
