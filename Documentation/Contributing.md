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
| Public playback API | [`PublicAPI/Playback/`](../Sources/StreamKit/PublicAPI/Playback/), including [`StreamPlayerController.swift`](../Sources/StreamKit/PublicAPI/Playback/StreamPlayerController.swift) and its public command extensions | Exported playback controls, configuration, timeline, state, and failures. Controller state is still owned by one `@MainActor` instance. |
| Public media API | [`PublicAPI/Media/`](../Sources/StreamKit/PublicAPI/Media/) | Media source/request configuration, tracks, FairPlay provider contract, and expensive-network limits. |
| Public advertising API | [`PublicAPI/Advertising/`](../Sources/StreamKit/PublicAPI/Advertising/) | Provider/session contracts, ad modes, break state, and display container. Provider implementations remain optional adapters. |
| Public presentation API | [`PublicAPI/Presentation/`](../Sources/StreamKit/PublicAPI/Presentation/) | Managed SwiftUI integration, direct AVKit presentation, custom video rendering, and PiP APIs. |
| Public diagnostics API | [`PublicAPI/Diagnostics/`](../Sources/StreamKit/PublicAPI/Diagnostics/) | Normalized playback diagnostics and AVFoundation metrics exposed to applications. |
| Internal playback | [`Internal/Playback/`](../Sources/StreamKit/Internal/Playback/) | Playback engine seam, AVFoundation engine, reducer, state coordination, and diagnostic broadcasters. No backend/plugin API is exported. |
| Internal media | [`Internal/Media/`](../Sources/StreamKit/Internal/Media/) | Authenticated resource loading and FairPlay key-session implementation. |
| Internal feature coordination | [`Internal/Advertising/`](../Sources/StreamKit/Internal/Advertising/) and [`Internal/Support/`](../Sources/StreamKit/Internal/Support/) | Ad-session coordination, audio interruption plumbing, and PiP waiters. These remain module-internal. |
| Demo screens | [`StreamKitDemo/`](../Examples/StreamKitDemo/StreamKitDemo/) | Runnable user flows. `PlayerComponents/` contains demo-only controls and shared screen support; [`AxinomFairPlayDemoSupport.swift`](../Examples/StreamKitDemo/StreamKitDemo/AxinomFairPlayDemoSupport.swift) keeps the sample license adapter and diagnostics out of the view. |
| Tests | [`StreamKitTests/`](../Tests/StreamKitTests/) | Test folders mirror playback, diagnostics, advertising, media, presentation, and shared test support. |

The directory names do not alter Swift access control. Public declarations remain public in `PublicAPI`; implementation seams and helpers remain internal or private under `Internal` and the test target.

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
