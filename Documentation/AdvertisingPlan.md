# Advertising Integration Plan

**Status:** Both HLS interstitials and client-side ads are in scope for the first advertising release. The client-side provider is still to be selected.

**Implementation:** The shared HLS path observes active interstitials, publishes normalized ad-break state and diagnostics, and enforces active and scheduled forward-seek restrictions. Managed and advanced controls show the active break and honor its restrictions; AVKit applies its linear-playback policy. The demo has an HLS interstitial route prefilled with Apple's sample manifest and a selector for all three surfaces. **Device verification:** the user confirmed the ad played, begin/end diagnostics appeared, and all three surfaces were checked. Integrated content/ad timeline semantics remain future work.

## Goal

Support ad breaks consistently through all three StreamKit player surfaces:

- **Managed:** `StreamPlayerView` and its managed session.
- **Advanced:** `StreamPlayerController` with `StreamVideoView` and app-owned controls.
- **AVKit:** `StreamAVPlayerView` and its presentation controller.

All three surfaces use the same controller and AVFoundation playback pipeline. Ad state, events, source replacement, seeking policy, and teardown must therefore be owned by that shared pipeline. A surface may present the state differently, while preserving the same playback behavior.

## First-release scope

Support both delivery paths:

- **HLS interstitials authored into the stream.** Apple exposes these through `AVPlayerInterstitialEventMonitor`; AVFoundation performs interstitial playback using the primary player's output configuration. The monitor and event APIs are available from iOS 15, below StreamKit's iOS 18 minimum.
- **Client-side ads.** Select one concrete provider for the first integration. Its adapter must own ad requests and provider callbacks, coordinate content pause/resume, expose an ad display surface, and report normalized ad events. Client-side systems commonly render ads in a separate player over the content player, so this requires a real overlay/container lifecycle on each StreamKit surface. Keep vendor dependencies outside the core AVFoundation engine; avoid promising an abstract plug-in for untested providers.

Treat the two paths as explicit per-source modes in the first release. If a source both carries HLS interstitials and configures a client-side provider, reject the ambiguous setup or require an explicit precedence policy; never play both schedules accidentally. Do not set an `AVPlayerInterstitialEventController` schedule by default: Apple documents that setting one overrides interstitial events already present in the source.

## Shared behavior contract

Before adding a public ad API, define a provider-neutral contract for:

- Break lifecycle: scheduled, started, completed, skipped, and unscheduled/failed where AVFoundation provides enough information to distinguish outcomes.
- Current playback state while the interstitial player temporarily takes over output.
- Seeking and skip policy for mandatory and optional breaks, including programmatic seeks from the controller.
- The difference between primary-content time, interstitial playout time, and the integrated timeline shown by each surface.
- Source replacement, load cancellation, shutdown, and stale interstitial events.
- What playback diagnostics expose, while omitting media URLs, ad asset URLs, request headers, and provider credentials.

Keep the existing playback intent (`play` or `pause`) independent of interstitial state. Do not represent an ad break as a second primary media load. The public shape should follow a focused API review after the behavior contract is agreed.

## Surface acceptance

| Surface | Required behavior |
| --- | --- |
| Managed `StreamPlayerView` | AVKit presents native HLS interstitials. For client-side ads, the managed view hosts the provider's ad display surface. Public state and diagnostics report the same break lifecycle as the other surfaces. |
| Advanced controller + `StreamVideoView` | App-owned controls display ad state, host client-side ad UI, and enforce the same seek/skip rules, including controller-issued seeks. |
| `StreamAVPlayerView` | AVKit presents native HLS interstitials and hosts the client-side ad display surface. The presentation applies the required linear-playback/navigation behavior while a mandatory break is active. |

No surface may silently skip an event that the shared policy treats as mandatory. PiP, fullscreen restoration, live/DVR, audio interruptions, bearer-authenticated resources, and FairPlay interaction need explicit acceptance results wherever the chosen ad streams use those capabilities.

Provider capabilities must be part of surface acceptance. For example, Google IMA documents iPad PiP support with extra display/proxy setup, while also requiring ads to start in standard playback mode; an ad break that becomes due while already in PiP needs a defined policy. IMA's current compatibility guide says it does not support AirPlay. These constraints are provider-specific and need confirmation before choosing IMA.

## Work sequence

1. **Finish remaining HLS work.** Complete integrated timeline semantics, then verify source replacement, cancellation, and teardown across all three surfaces. Playback and diagnostics have already been verified on device with Apple's sample stream.
2. **Select the client-side provider.** Confirm whether the first adapter targets Google IMA or another vendor, and verify the ad formats and device/presentation features it supports.
3. **Finalize shared playback semantics.** Document break states, normalized events, timeline semantics, seek/skip policy, failure behavior, source-mode selection, and ambiguous hybrid handling before finalizing public API names.
4. **Build the client-side provider adapter.** Define provider lifecycle, ad-overlay/container, content playhead, pause/resume, and teardown hooks for all three surfaces. Keep vendor dependencies and provider policy outside the core AVFoundation engine.
5. **Cover each surface and mode.** Add a client-side playback fixture. Verify identical normalized event/state transitions and clearly distinguish content time from ad playout time in managed, advanced, and AVKit modes.
6. **Validate behavior.** Add unit coverage for both adapters, event mapping, seek restrictions, source replacement, cancellation, and teardown. Exercise all three surfaces with controlled HLS and client-side ad responses. Record physical-device PiP and AirPlay results, plus auth/FairPlay results when those are requirements of the ad streams.

## Open product questions

- Which client-side provider and ad formats should the first adapter support?
- Must a single source combine manifest-scheduled HLS interstitials with client-side ad requests, or are they selected as separate source modes?
- Must the first release support customer-scheduled breaks or only stream-authored schedules?
- Which breaks are mandatory, and what should seeking do before and after a break?
- Is AirPlay required during client-side ads, and what should happen if the selected provider does not support it?
- What should happen when a mandatory client-side break becomes due while the player is already in PiP?
- Must ad assets support the same bearer authentication and FairPlay flows as primary content?

## References

- [Apple: AVPlayerInterstitialEventMonitor](https://developer.apple.com/documentation/avfoundation/avplayerinterstitialeventmonitor)
- [Apple: Providing an integrated view of the timeline for HLS interstitials](https://developer.apple.com/documentation/avfoundation/providing-an-integrated-view-of-the-timeline-when-playing-hls-interstitials)
- [Apple: Working with interstitial content in AVKit](https://developer.apple.com/documentation/avkit/working-with-interstitial-content)
- [Google IMA for iOS: support and compatibility](https://developers.google.com/interactive-media-ads/docs/sdks/ios/client-side/compatibility)
- [Google IMA for iOS: Picture in Picture support](https://developers.google.com/interactive-media-ads/docs/sdks/ios/client-side/picture_in_picture)
