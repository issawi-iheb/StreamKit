# Contributing to StreamKit

This guide is a map for making a change without first reading the whole player. Start with the API or behavior you want to change, follow its ownership below, and keep asynchronous state changes on the existing controller and engine path.

## Follow one source through playback

```text
MediaSource
  → StreamPlayerView / StreamPlayerSession (optional managed SwiftUI layer)
  → StreamPlayerController (intent, commands, state and cancellation)
  → PlaybackEngine
  → AVFoundationPlaybackEngine (AVPlayer, AVPlayerItem and observations)
  → StreamAVPlayerView or StreamVideoView
```

The managed session does not implement a second playback pipeline. It creates a controller, loads the `MediaSource`, publishes its snapshot and PiP state, and coordinates teardown with AVKit. Bearer and FairPlay configuration stays on the source and is consumed by the AVFoundation item factory and its request/key-loading collaborators.

The large controller and engine are split into same-type extension files by responsibility so navigation is local while mutable state still has one owner. Keep the loading, command, event/observation, state, track, and lifecycle boundaries aligned with those jobs. If a future change introduces an independently owned lifecycle, extract a collaborator; do not create one just to move methods.

## Source map

| Area | Start here | Owns |
| --- | --- | --- |
| Managed SwiftUI integration | [`StreamPlayerView.swift`](../Sources/StreamKit/PublicAPI/StreamPlayerView.swift), [`StreamPlayerSession.swift`](../Sources/StreamKit/PublicAPI/StreamPlayerSession.swift) | Session setup, SwiftUI presentation, snapshot exposure, and PiP-aware shutdown. |
| App-facing playback | [`StreamPlayerController.swift`](../Sources/StreamKit/PublicAPI/StreamPlayerController.swift), [`+Loading`](../Sources/StreamKit/PublicAPI/StreamPlayerController+Loading.swift), [`+Commands`](../Sources/StreamKit/PublicAPI/StreamPlayerController+Commands.swift), [`+Events`](../Sources/StreamKit/PublicAPI/StreamPlayerController+Events.swift), [`+State`](../Sources/StreamKit/PublicAPI/StreamPlayerController+State.swift), [`+Lifecycle`](../Sources/StreamKit/PublicAPI/StreamPlayerController+Lifecycle.swift), [`+Tracks`](../Sources/StreamKit/PublicAPI/StreamPlayerController+Tracks.swift) | One `@MainActor` controller grouped by responsibility. The extensions share module-internal state; they do not create additional owners or actors. |
| Media input | [`MediaSource.swift`](../Sources/StreamKit/PublicAPI/MediaSource.swift), [`MediaRequestConfiguration.swift`](../Sources/StreamKit/PublicAPI/MediaRequestConfiguration.swift), [`FairPlayConfiguration.swift`](../Sources/StreamKit/PublicAPI/FairPlayConfiguration.swift) | Source kind, request settings, cookies, bearer credentials, and the provider-neutral FairPlay contract. |
| Rendering and PiP | [`StreamVideoView.swift`](../Sources/StreamKit/PublicAPI/StreamVideoView.swift), [`StreamAVPlayerView.swift`](../Sources/StreamKit/PublicAPI/StreamAVPlayerView.swift), [`StreamPictureInPictureController.swift`](../Sources/StreamKit/PublicAPI/StreamPictureInPictureController.swift) | App-owned video surfaces, AVKit presentation, and PiP lifecycle. |
| Playback state | [`PlaybackIntent.swift`](../Sources/StreamKit/PlaybackCore/PlaybackIntent.swift), [`PlaybackPhase.swift`](../Sources/StreamKit/PlaybackCore/PlaybackPhase.swift), [`PlaybackSnapshot.swift`](../Sources/StreamKit/PlaybackCore/PlaybackSnapshot.swift), [`PlaybackEventReducer.swift`](../Sources/StreamKit/PlaybackCore/PlaybackEventReducer.swift) | Platform-independent state values and event-to-snapshot transitions. |
| Playback diagnostics | [`PlaybackDiagnosticEvent.swift`](../Sources/StreamKit/PlaybackCore/PlaybackDiagnosticEvent.swift), [`PlaybackDiagnosticsBroadcaster.swift`](../Sources/StreamKit/PlaybackCore/PlaybackDiagnosticsBroadcaster.swift), [`StreamPlayerController+Events.swift`](../Sources/StreamKit/PublicAPI/StreamPlayerController+Events.swift) | Safe lifecycle values, bounded replay/fan-out, and controller-boundary normalization. |
| Engine contract and AVFoundation | [`PlaybackEngine.swift`](../Sources/StreamKit/PlaybackCore/PlaybackEngine.swift), [`AVFoundationPlaybackEngine.swift`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine.swift), [`+Loading`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine+Loading.swift), [`+Observations`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine+Observations.swift), [`+Tracks`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine+Tracks.swift), [`+Commands`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine+Commands.swift), [`+Lifecycle`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackEngine+Lifecycle.swift), [`AVFoundationPlaybackItemFactory.swift`](../Sources/StreamKit/PlaybackCore/AVFoundationPlaybackItemFactory.swift) | Engine seam, AVPlayer operations, readiness, timeline observations, and item construction. The engine extensions share one `@MainActor` AVPlayer/resource owner. |
| Media authorization and DRM internals | [`AuthenticatedMediaResourceLoader.swift`](../Sources/StreamKit/PlaybackCore/AuthenticatedMediaResourceLoader.swift), [`FairPlayContentKeySession.swift`](../Sources/StreamKit/PlaybackCore/FairPlayContentKeySession.swift), [`FairPlayKeyExchange.swift`](../Sources/StreamKit/PlaybackCore/FairPlayKeyExchange.swift), [`FairPlayKeyRequestLifecycle.swift`](../Sources/StreamKit/PlaybackCore/FairPlayKeyRequestLifecycle.swift) | HLS resource authorization and FairPlay key request lifecycle. |
| Internal platform support | [`InternalSupport/`](../Sources/StreamKit/InternalSupport/) | System audio-interruption subscription and PiP stop-waiting utilities; these are not app-facing APIs. |
| Demo screens | [`StreamKitDemo/`](../Examples/StreamKitDemo/StreamKitDemo/) | Runnable user flows. `PlayerComponents/` contains demo-only controls and shared screen support; [`AxinomFairPlayDemoSupport.swift`](../Examples/StreamKitDemo/StreamKitDemo/AxinomFairPlayDemoSupport.swift) keeps the sample license adapter and diagnostics out of the view. |
| Tests | [`StreamKitTests/`](../Tests/StreamKitTests/) | State reducer, engine behavior, provider lifecycles, request loading, PiP policies, and controller concurrency. |

## Where to make common changes

- **Add a public source option:** define it with the related media configuration type, propagate it through the item factory, and document who supplies the value. Do not place provider-specific license HTTP in the playback engine.
- **Change a playback state transition:** update `PlaybackEventReducer` when the transition is a pure event rule. Keep async command policy and generation checks in `StreamPlayerController`.
- **Change AVFoundation behavior:** update `AVFoundationPlaybackEngine` or the focused item/authentication/FairPlay collaborator. Keep `PlaybackEngine` small enough to serve as the test seam.
- **Change managed-player lifecycle:** update `StreamPlayerSession`/`StreamPlayerView`; do not duplicate source loading or playback state in the SwiftUI view.
- **Change a demo-only service protocol:** keep its adapter and diagnostics outside the SwiftUI screen. The Axinom adapter is an example integration, not production SDK behavior.

## Concurrency and lifecycle rules

- Controller and AVFoundation engine coordination is `@MainActor` isolated. Keep UIKit/AVFoundation state mutation on that actor.
- Async engine and provider calls can complete after a source change, a newer command, or shutdown. Preserve the generation/cancellation checks around those suspension points.
- Engine events carry their source generation. Reject stale events before they update the current snapshot.
- Keep diagnostic publication on the controller's existing MainActor boundary. Do not call app-provided logging callbacks inline with playback handling; bounded async streams keep consumer work out of engine callbacks.
- Diagnostics are bounded and best-effort. Preserve sequence numbers so consumers can detect dropped events; never imply that the stream is durable or complete.
- The host owns process-wide `AVAudioSession` configuration. StreamKit observes interruptions and coordinates only its own player controllers.
- PiP may outlive the route displaying a player. Retain its session/controller until AVKit reports PiP stopped; do not release the playback engine just because a SwiftUI view disappeared.
- Do not log bearer tokens, certificates, SPCs, CKCs, URLs, request headers, provider response text, or provider secrets. Redact diagnostic events when constructing them, not only when formatting a report.

## Validation

Run the package tests after changing source behavior:

```sh
swift test
```

Build the demo after changing a demo screen or managed presentation flow:

```sh
xcodebuild -project Examples/StreamKitDemo/StreamKitDemo.xcodeproj \
  -scheme StreamKitDemo \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

FairPlay, device audio behavior, and PiP restoration also need device/service acceptance; a simulator build or unit test does not establish those integrations end to end. See [FairPlay Streaming Integration](FairPlayIntegration.md) for the provider-specific checks.
