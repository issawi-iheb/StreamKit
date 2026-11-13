# Global roadmap gap audit — 2026-11-13

This audit checks the four reliability and observability work areas in `ROADMAP.md` against the current `ads/discovery` checkout at `ee12e8d`. It reviews source, tests, demo routes, CI configuration, and checked-in verification notes. It does not treat the roadmap's status labels as evidence by themselves. No tests or device runs were performed for this audit.

Four independent read-only reviews covered CI/platform support, diagnostics, authenticated HLS/FairPlay, and lifecycle/device acceptance. Findings below distinguish implementation, deterministic tests, and external-runtime evidence.

## Executive assessment

The SDK contains substantial implementation and deterministic package coverage for these areas. The major remaining gaps are acceptance evidence on the stated platform range and real services/devices, plus stale roadmap and architecture descriptions. The checked-in CI tests the demo only at its iOS 26.5 deployment target and does not specify a simulator OS matrix, so it does not establish the iOS 18 minimum.

## Findings by roadmap item

### 1. Roadmap status and platform coverage

**Finding — P1: CI does not verify the iOS 18 package minimum.** The package declares iOS 18 in `Package.swift` (lines 7–9). CI runs `swift test` on an `xcode-27` host, then tests the demo on one `iPhone 17 Pro` simulator without an OS-version matrix (`.github/workflows/ci.yml`, lines 11–31). The demo project deployment target is iOS 26.5 (`Examples/StreamKitDemo/StreamKitDemo.xcodeproj/project.pbxproj`, e.g. lines 327, 385, 406, 435, 461, and 483). Host package tests and this demo destination do not demonstrate iOS 18 compilation or runtime behavior. The workflow file describes intended commands; this audit did not verify a hosted run.

**Finding — P2: roadmap status is stale and internally inconsistent.** `ROADMAP.md` names `42e805c` as the latest implementation commit (line 179), while this checkout is at `ee12e8d`. Its Phase 3 status says Live/DVR, multiple-player, audio, and bearer routes lack diagnostics panels (line 116), and `Documentation/Architecture.md` repeats that claim (line 40). The panels are present in those routes; see the diagnostics finding below. Other roadmap entries correctly describe platform/device acceptance as open, but status claims should be reconciled against current code and actual run records.

**Recommendation:** Add an explicit iOS 18 package build/test job or simulator lane, retain a separate current-runtime lane, and record hosted run links/results. Refresh the roadmap commit/status and correct the stale diagnostics statements.

### 2. Shared diagnostics and AVMetrics

**Finding — implementation is connected across the relevant demo routes.** `PlaybackDiagnosticsPanel` consumes both `controller.diagnosticEvents` and `controller.metrics` (`Examples/StreamKitDemo/StreamKitDemo/PlaybackDiagnosticsSheet.swift`, lines 119–134). Calls are present in Live/DVR (line 116), audio (line 87), bearer authentication (line 87), and both concurrent-player cards (`ConcurrentPlayersDemoView.swift`, line 189). The panel is also used by managed, custom-controls, AVKit/PiP, standalone, HLS interstitial, and IMA/VAST examples. FairPlay has a separate provider request report, rather than this shared sheet.

**Finding — multi-player histories have readable demo identity, but no route-level acceptance test was found.** Each concurrent card passes its title into the shared panel (`ConcurrentPlayersDemoView.swift`, lines 150–190); the sheet labels the history and states that its sequence is scoped to that player (`PlaybackDiagnosticsSheet.swift`, lines 76–80). This provides “Player 1” / “Player 2” identity in the demo. The reviewed UI tests do not open both diagnostics sheets and verify the labels or independent histories.

**Finding — AVMetrics normalization exists, physical availability is unverified.** `AVFoundationPlaybackEngine+Metrics.swift` consumes `AVPlayerItem.allMetrics()` and maps resource/playlist/segment/content-key requests, startup-to-likely-to-keep-up, stalls, variant switches, and playback summaries (lines 6–90). The public model is `PlaybackMetricEvent.swift`; the sheet displays normalized values. Package tests verify forwarding of a synthetic metric and bounded stream behavior, not real `AVMetricEvent` production by supported devices or stream types. The repository has no recorded physical-device AVMetrics results or availability matrix.

**Recommendation:** Keep the panels; update the stale docs. Add UI coverage for opening each relevant route's panel and proving the two multi-player histories remain distinct. On a physical iOS 18+ device and a current supported OS, collect results for VOD, live HLS, authenticated HLS, and FairPlay where available; document which AVMetrics types actually arrive and what fields may be absent.

### 3. Authenticated HLS and FairPlay

**Finding — authenticated HLS implementation and deterministic integration coverage are substantial, but no real controlled HTTPS origin was validated.** The loader obtains authorization per resource, scopes credentials to trusted HTTPS hosts, applies cookies/user-agent/range headers, and handles 401/403 (`Sources/StreamKit/Internal/Media/Network/AuthenticatedMediaResourceLoader.swift`, lines 59–95, 149–168, and 240–279). Playlist references are rewritten to the authenticated loader scheme; insecure HTTP child resources are rejected (`HLSPlaylistRewriter.swift`, lines 3–55). Integration tests use AVURLAsset and `ControlledOriginURLProtocol` to cover master/child requests, per-request tokens, byte ranges, trusted and untrusted redirects, HTTPS downgrade rejection, in-flight cancellation, source replacement, and shutdown (`Tests/StreamKitTests/Media/Network/AuthenticatedMediaResourceLoaderIntegrationTests.swift`, lines 9–274). This is controlled URLProtocol interception, not a remote HTTPS origin, real CDN/TLS, or production credential service.

The provider is called per resource, so a host can return fresh credentials. The code does not retry/replay a failed resource request after a 401/403. Expired-token recovery and the desired retry policy therefore remain unverified; this is distinct from the tested cancellation of the token-provider task.

**Finding — FairPlay lifecycle seams are implemented and mock-tested; provider-backed renewal and failure paths remain open.** Core creates and tears down AVContentKeySession state, routes renewal requests, and invalidates the prior session during item replacement (`FairPlayContentKeySession.swift`; `AVFoundationPlaybackEngine+Loading.swift`, lines 24–32 and 132–145). Tests cover renewal flag propagation, single completion, cancellation during provider work, simulated provider rejection/network failure, and redaction (`FairPlayKeyRequestLifecycleTests.swift`; `FairPlayKeyExchangeTests.swift`, lines 90–191). These tests do not exercise AVFoundation's real renewal/expiry callbacks or a customer/provider license service. Checked-in FairPlay notes record public Axinom initial playback reaching `.playing`, while renewal, expiry/failure, cancellation, and source replacement remain unvalidated end to end (`Documentation/FairPlayIntegration.md`, lines 5–9 and 72; `ROADMAP.md`, lines 97–106).

**Recommendation:** Run the loader against a controlled HTTPS origin and record server-side requests/results for child playlists, segments, keys, ranges, redirects, expiry, cancellation, and source replacement. Decide and document whether 401 recovery belongs entirely to the app token provider or whether core should retry. With provider materials, validate actual FairPlay renewal, expired/rejected license, cancellation, and source replacement on device.

### 4. Device and lifecycle coverage

**Finding — controller interruption policy and cancellation are well covered deterministically; route changes are not implemented.** `SystemAudioInterruptionSource` listens for interruption notifications and translates began/ended events. No audio-route-change observer was found. Unit and controller tests cover allowed/denied resumption, user pause, source replacement, shutdown, and suspended operations. The audio demo synthesizes interruption notifications to exercise policy; it does not simulate route changes or establish real device behavior (`AudioSessionDemoView.swift`, lines 63–82 and 146–160). The roadmap records one Siri interruption/resume verification, but additional interruption sources, routing, and supported OS versions remain unverified (`ROADMAP.md`, lines 66 and 83–88).

**Finding — PiP ownership and simulator UI flows exist; system restoration acceptance remains partial.** Managed and advanced demo sessions retain playback during PiP and defer shutdown until PiP stops. Package tests exercise policy/waiter behavior; UI tests include route removal and custom PiP flows (`StreamKitDemoUITests.swift`, around lines 98–159). These do not prove AVKit/system PiP restoration across real app backgrounding, OS versions, or device form factors. The roadmap itself keeps that device coverage open (lines 74 and 88–89).

**Finding — cancellation and shutdown have broad tests, but not live AVFoundation acceptance across supported devices.** Package tests cover overlapping/replaced loads, shutdown during loading and suspended seek, concurrent shutdown callers, and authenticated-loader cancellation/source replacement. These establish deterministic implementation behavior for test seams; they do not replace on-device checks against live media and system callbacks. CI has no iOS 18 destination.

**Recommendation:** Verify interruption/resumption and route changes on iOS 18 and current iOS devices; decide whether route-change behavior is in SDK scope. Run PiP start, background transition, restore, route removal/reopen, and shutdown flows on supported devices. Repeat source replacement and cancellation with live HLS/progressive sources and record the OS/device/runtime for each result.

## Roadmap corrections to make

1. Update the current commit and verification date; distinguish the latest code commit from the commit that last changed behavior.
2. Mark shared diagnostics UI wiring as implemented across the routes found above; leave UI acceptance and physical AVMetrics acceptance open.
3. Describe authenticated-HLS URLProtocol integration tests as deterministic loader integration, not real-origin acceptance; explicitly state that there is no automatic retry after 401/403.
4. Separate FairPlay mock coverage and public Axinom initial playback from provider-backed renewal/expiry/failure acceptance.
5. Keep iOS 18, current simulator, broader device/OS, audio route, and real PiP restoration checks open until run results are recorded.

## Overall status

The next global milestone remains **reliability and developer observability**. The code implementation is further along than parts of the roadmap text suggest. The main work now is accurate documentation plus platform-, provider-, and device-level acceptance, with explicit evidence attached to each result.
