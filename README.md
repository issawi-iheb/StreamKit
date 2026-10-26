# StreamKit

A reusable Swift media-player SDK for iOS 16+ built with Swift 6.4. StreamKit provides independent playback instances with state observation, track selection, and clean resource management.

## Requirements

- iOS 16.0 or later
- Swift 6.4 toolchain

The package declares iOS 16 support. The demo project currently targets iOS 26.5 and does not yet validate the package's minimum deployment target; this is tracked in the roadmap.

## Installation

### Swift Package Manager

1. In Xcode, select File > Add Packages...
2. Enter the repository URL: `https://github.com/issawi-iheb/StreamKit`
3. Choose the `StreamKit` package product
4. Add to your target

## Choose Your Player Surface

StreamKit offers three integration levels:

- **Managed player:** `StreamPlayerSession` plus `StreamPlayerView` loads a `MediaSource` and presents AVKit's standard controls and Picture in Picture.
- **App-owned controls:** `StreamPlayerController` plus `StreamVideoView` gives your app direct control over layout and playback controls.
- **Advanced AVKit integration:** use `StreamAVPlayerView` with a controller and presentation controller when your app needs to own presentation and restoration lifecycles directly.

Start with the managed player for the fewest setup steps. Use `StreamVideoView` when you need app-owned controls. For the lower-level AVKit lifecycle, see [System Player, Picture in Picture, and Fullscreen](#system-player-picture-in-picture-and-fullscreen).

## Quick Start

```swift
import StreamKit
import SwiftUI

@MainActor
struct PlayerRoute: View {
    let source: MediaSource

    var body: some View {
        StreamPlayerView(source: source)
    }
}
```

Create the route with `PlayerRoute(source: MediaSource(url: videoURL))`. This is the normal VOD path: the managed view loads the source automatically, and AVKit's standard controls let the viewer start playback. The managed surface does not select or limit media features. Configure the `MediaSource` first, then pass it in; VOD/live semantics, cookies, user agent, bearer authentication, and FairPlay all travel through the same source configuration used by `StreamPlayerController`.

### Choose VOD or live

Mark live content explicitly. StreamKit does not infer it from duration or seekable ranges; `.live` enables live timeline semantics and live-edge seeking when supported by the stream.

```swift
let vod = MediaSource(url: vodURL, presentationKind: .onDemand)
let live = MediaSource(url: liveHLSURL, presentationKind: .live)

StreamPlayerView(source: vod) // or StreamPlayerView(source: live)
```

`PlayerConfiguration.autoplay` defaults to `false`, so AVKit's controls let the viewer start playback. Set it to `true` to start when ready. For a live stream whose seekable range must continue refreshing while paused, opt in with `keepsLiveTimelineCurrentWhilePaused: true`; this may increase network and power use.

### Add bearer authentication and FairPlay

The managed view accepts the same request configuration. The host app supplies its token provider and its FairPlay provider; StreamKit routes media and key requests through the existing playback engine.

```swift
let mediaAuthentication = MediaBearerAuthentication(
    trustedHosts: ["video.example.com", "cdn.example.com"]
) { resourceURL in
    try await accountSession.validMediaToken(for: resourceURL)
}

let source = MediaSource(
    url: protectedHLSURL,
    requestConfiguration: MediaRequestConfiguration(
        bearerAuthentication: mediaAuthentication,
        fairPlay: FairPlayConfiguration(licenseProvider: appFairPlayProvider)
    ),
    presentationKind: .onDemand
)

StreamPlayerView(source: source)
```

Both authentication settings are optional and independent. Add bearer authentication only when the HLS origin requires it; add FairPlay only for FairPlay-protected content. Bearer tokens authorize HLS media resources on the exact trusted HTTPS hosts. The FairPlay provider separately handles the certificate, key-ID/content-ID mapping, license-server authentication and protocol, and CKC response parsing. If the host's license server also needs credentials, provide them inside `appFairPlayProvider`.

The same `MediaRequestConfiguration` can also carry explicitly scoped cookies and a user agent when your service requires them:

```swift
let requestConfiguration = MediaRequestConfiguration(
    cookies: [MediaCookie(name: "session", value: sessionCookie,
                          domain: "video.example.com")],
    userAgent: "ExampleApp/1.0",
    bearerAuthentication: mediaAuthentication,
    fairPlay: FairPlayConfiguration(licenseProvider: appFairPlayProvider)
)
```

Pass this as `requestConfiguration: requestConfiguration` when constructing `MediaSource`. The isolated authenticated HLS loader uses only explicitly supplied cookies; it does not import cookies from the app's shared URL session store.

### Picture in Picture and session ownership

AVKit supplies standard playback controls and the system Picture in Picture affordance where supported. To opt into automatic PiP when the app leaves the foreground, set `automaticallyStartsPictureInPictureWhenLeavingApp: true`. The one-argument `StreamPlayerView(source:)` owns and shuts down its session when removed, after active PiP stops. Retain a `StreamPlayerSession` above the player route when playback/PiP must survive navigation or when the host needs to provide a route restoration handler:

```swift
@MainActor
struct PlayerOwnerView: View {
    let source: MediaSource
    @StateObject private var session: StreamPlayerSession

    init(source: MediaSource) {
        self.source = source
        _session = StateObject(wrappedValue: StreamPlayerSession(
            source: source,
            automaticallyStartsPictureInPictureWhenLeavingApp: true
        ))
    }

    var body: some View {
        StreamPlayerView(session: session)
    }
}
```

Pass a `restorationHandler` to `StreamPlayerSession` when the host needs to restore its navigation route; call its completion with `true` only after the route is available. Use `StreamPlayerController` with `StreamVideoView` instead when you need app-owned controls. The advanced AVKit integration remains available when the host needs to own the presentation lifecycle directly.

Keep `StreamPlayerSession` in an owner above the player route when playback or Picture in Picture must survive route changes. `shutdown()` waits for PiP to stop before releasing playback; if that wait is cancelled, the session stays alive.

## State Observation

Observe playback state changes using the `snapshots` property, which provides an `AsyncStream<PlaybackSnapshot>`:

```swift
// Start observation (typically in init or viewDidLoad)
let snapshotStream = controller.snapshots
Task { @MainActor in
    for await snapshot in snapshotStream {
        // Handle state transitions:
        // snapshot.phase: .idle, .loading, .ready, .playing, .paused, .waiting, .ended, .failed
        // snapshot.currentTime: current playback position in seconds
        // snapshot.duration: total media duration in seconds (if available)
        // snapshot.intent: .play or .pause (application requested state)
        // snapshot.failure: error details if phase is .failed
    }
}

// To stop observation when no longer needed:
// The stream automatically ends when the controller is shut down
// or you can break from the loop/task as needed
```

The controller publishes snapshots from the MainActor. `AsyncStream` does not isolate its consumer, so UI code should consume snapshots from a MainActor task (as shown above) or explicitly hop to the UI actor before updating view state.

## Playback Controls

### Play
```swift
try await controller.play()
```
- Throws if no media is loaded or playback fails
- If media is loading, sets intent to play (playback starts when ready)
- If the current item has ended and has a known finite duration, seeks to the start and resumes after the seek completes. Unknown-duration media is not rewound automatically.

### Pause
```swift
await controller.pause()
```
- Never throws
- Pauses playback if playing, otherwise sets intent to pause

### Seek
```swift
try await controller.seek(to: 85.5) // Seek to 85.5 seconds
```
- Requires media to be ready (not idle, loading, or failed)
- Throws if seeking fails or controller is shut down

## Audio and Subtitles

### Discover Tracks
```swift
let audioTracks = try await controller.availableAudioTracks()
let subtitleTracks = try await controller.availableSubtitleTracks()
// Returns [MediaTrack] with id, type, name, languageCode properties
```

### Select Tracks
```swift
// Select audio track
try await controller.selectAudioTrack(id: "track-id-123")

// Select subtitle track or disable subtitles
try await controller.selectSubtitleTrack(id: "subtitle-track-456")
// To disable: try await controller.selectSubtitleTrack(id: nil)
```

Track selection requires media to be ready (not idle, loading, or failed).

## System Player, Picture in Picture, and Fullscreen

Use `StreamVideoView` when you want to build custom controls. For Apple's standard playback interface, including system Picture in Picture and AirPlay controls where supported, use `StreamAVPlayerView`:

```swift
@StateObject private var playbackSession = PlayerPresentationSession()

StreamAVPlayerView(
    controller: playbackSession.playerController,
    presentationController: playbackSession.presentationController,
    automaticallyStartsPictureInPictureWhenLeavingApp: false
)
.frame(height: 240)
```

Keep the playback controller and presentation controller in a session object above the player route. Report restoration success only after the route appears; report failure if the host cannot restore it. The presentation controller retains AVKit's delegate and source view controller until the PiP stop lifecycle completes.

```swift
import SwiftUI

@MainActor
final class PlayerPresentationSession: ObservableObject {
    @Published var isPlayerPresented = false
    let playerController = StreamPlayerController()
    private var isPlayerRouteVisible = false
    private var restorationCompletions: [@Sendable (Bool) -> Void] = []

    lazy var presentationController = StreamAVPlayerPresentationController { [weak self] completion in
        guard let self else {
            completion(false)
            return
        }
        self.restorePlayerRoute(completion)
    }

    func restorePlayerRoute(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard !isPlayerRouteVisible else {
            completion(true)
            return
        }

        restorationCompletions.append(completion)
        isPlayerPresented = true
    }

    func playerRouteDidAppear() {
        isPlayerRouteVisible = true
        let completions = restorationCompletions
        restorationCompletions.removeAll()
        completions.forEach { $0(true) }
    }

    func playerRouteDidDisappear() {
        isPlayerRouteVisible = false
    }

    func playerRouteRestorationFailed() {
        let completions = restorationCompletions
        restorationCompletions.removeAll()
        completions.forEach { $0(false) }
    }
}

// Keep this session above the navigation destination.
@StateObject private var playbackSession = PlayerPresentationSession()

.navigationDestination(isPresented: $playbackSession.isPlayerPresented) {
    PlayerScreen(presentationController: playbackSession.presentationController)
        .onAppear { playbackSession.playerRouteDidAppear() }
        .onDisappear { playbackSession.playerRouteDidDisappear() }
}
```

Automatic PiP is opt-in and should only be enabled when the inline player is the primary content. PiP requires device support, a playback audio session, and the app's `audio` background mode. The host app owns those settings. The demo's **AVKit Player & Picture in Picture** entry lets you switch between `StreamAVPlayerView` and custom `StreamVideoView` rendering. Automatic PiP is available in the AVKit mode; custom controls can start PiP from a user action when the controller reports that PiP is possible. The standalone custom-control demo requests landscape while fullscreen is open, then restores the orientation that was active before fullscreen.

For custom controls, share one `StreamPictureInPictureController` across every `StreamVideoView` rendering the same player. Keep both it and the `StreamPlayerController` in a session owner above the player route so route removal cannot release the PiP source or playback session:

```swift
@StateObject private var pipController = StreamPictureInPictureController()

StreamVideoView(
    controller: controller,
    pictureInPictureController: pipController
)

Button("Start PiP") {
    pipController.startPictureInPicture()
}
.disabled(!pipController.isPictureInPicturePossible)

// Before shutting down or replacing the playback controller:
Task {
    do {
        try await pipController.stopAndWaitUntilStopped()
    } catch {
        // PiP may still be active, so retain the playback controller.
        return
    }
    await controller.shutdown()
}
```

`StreamAVPlayerView` and `StreamVideoView` are alternative renderers for one controller; do not display both at the same time.

## Audio Sessions, Interruptions, and Background Playback

StreamKit observes iOS audio-session interruptions for each controller. By default, it resumes playback only when playback was requested before the interruption and iOS reports that resuming is appropriate. An explicit `pause()` during the interruption cancels automatic resumption. Set `automaticallyResumesAfterAudioInterruption: false` in `PlayerConfiguration` to disable that behavior.

`AVAudioSession` is process-wide, so the host application owns its category, mode, and activation policy. For background audio, the host must also enable the `audio` background mode in its app target. The StreamKit demo's **Audio Session & Background Playback** example shows this setup; the package cannot add app capabilities to a consuming application.

Controllers that should share a single-active-player policy can receive the same `AudioPlaybackFocusCoordinator`. A new playback request then pauses the previously focused StreamKit controller. Controllers without a shared coordinator stay independent:

```swift
let audioFocus = AudioPlaybackFocusCoordinator()
let first = StreamPlayerController(audioPlaybackFocusCoordinator: audioFocus)
let second = StreamPlayerController(audioPlaybackFocusCoordinator: audioFocus)
```

The coordinator only arbitrates among controllers that share it. The host app still owns `AVAudioSession` configuration, activation, and decisions about interruptions involving other apps.

## Live and DVR playback

Declare a source as `.live` to enable live-edge seeking and live timeline semantics. AVFoundation supplies the seekable ranges; the newest range end is a seekable-window boundary, not a guarantee of zero latency. The ranges can be discontinuous. The demo's **Live & DVR Playback** screen accepts an HTTPS HLS live manifest, displays the current ranges and media date, and provides live-edge and behind-live seeks. The user must supply a stream with an actual DVR window to exercise behind-live seeking. If the app needs the timeline to stay fresh while paused, set `PlayerConfiguration(keepsLiveTimelineCurrentWhilePaused: true)`. AVFoundation may use network resources while paused in that mode, increasing network and power use; this setting is off by default. See Apple's [`canUseNetworkResourcesForLiveStreamingWhilePaused`](https://developer.apple.com/documentation/avfoundation/avplayeritem/canusenetworkresourcesforlivestreamingwhilepaused) documentation.

The demo displays AVFoundation's reported ranges. Verify live-window behavior against the target stream on a device.

The demo uses asynchronous audio-session activation on iOS 27 and later. On earlier supported versions, it runs the legacy activation call away from the main thread. Its simulated interruption controls exercise StreamKit's response to begin/end events; real Siri, call, route, and background behavior still needs OS/device verification.

```swift
let controller = StreamPlayerController(
    configuration: PlayerConfiguration(
        automaticallyResumesAfterAudioInterruption: true
    )
)
```

Interruption and background behavior should be validated on the target iOS versions and devices. A simulator build alone does not verify runtime audio routing or background execution.

## Lifecycle and Cancellation

### Loading Operations
Each `load(_:)` call returns a `LoadHandle`:
- `waitUntilReady()`: Async throws when media is ready to play
- `cancel()`: Requests cancellation of the loading operation; termination is cooperative and depends on the loading task checking for cancellation

### Controller Lifecycle
- Call `shutdown()` when the player is no longer needed
- Releases AVFoundation resources and ends observation streams
- Safe to call multiple times
- After shutdown, all methods will fail or return immediately

Removing a player view does not stop or shut down its controller. Put the controller in a playback-session owner whose lifetime matches the product's playback policy. Do not call `shutdown()` from renderer teardown because a renderer may disappear during fullscreen presentation or PiP.

For the custom `StreamVideoView` PiP path, request a stop and wait for AVKit's final callback before shutting down playback:

```swift
try await pictureInPictureController.stopAndWaitUntilStopped()
await controller.shutdown()
```

If the custom PiP wait is cancelled, it throws `CancellationError`; AVKit's stop request continues, but the caller must keep the playback controller alive until a later wait completes. For `StreamAVPlayerView`, AVKit owns the PiP stop action and doesn't expose a programmatic stop method. Keep the playback session alive until AVKit reports that PiP stopped, then shut it down:

```swift
try await presentationController.waitUntilStopped()
try Task.checkCancellation()
await controller.shutdown()
```

`waitUntilStopped()` only waits; it doesn't stop PiP. If its task is cancelled, it throws `CancellationError` and leaves the PiP session running. A new route creates a fresh controller after terminal shutdown.

The demo's standalone player follows this pattern: the root retains its session, the player route reports appearance and disappearance, and the session releases the controller after the route and custom PiP are both inactive. A new route creates a fresh controller after shutdown because shutdown is terminal.

## Bearer-Authenticated HLS

Use `MediaBearerAuthentication` when the media server requires an `Authorization: Bearer` token. Supply exact HTTPS host names that are allowed to receive credentials. StreamKit invokes the async token provider for the master playlist and each rewritten HLS resource, so the application can refresh credentials as needed.

```swift
let authentication = MediaBearerAuthentication(
    trustedHosts: ["video.example.com", "cdn.example.com"]
) { resourceURL in
    try await accountSession.validMediaToken(for: resourceURL)
}

let source = MediaSource(
    url: URL(string: "https://video.example.com/master.m3u8")!,
    requestConfiguration: MediaRequestConfiguration(
        bearerAuthentication: authentication
    )
)
let handle = controller.load(source)
try await handle.waitUntilReady()
```

The token provider is called for media requests, not just the initial playlist. List every exact host that may serve playlists, segments, keys, or redirects. Tokens are never sent to non-HTTPS or non-allowlisted hosts. Authenticated HLS playlists that reference insecure HTTP resources fail instead of downgrading transport. Regular HTTPS playback without bearer authentication keeps using AVFoundation's native loading path. To use this with the managed player, pass the configured `source` to `StreamPlayerView(source:)` instead of calling `controller.load(source)`; see [Add bearer authentication and FairPlay](#add-bearer-authentication-and-fairplay).

Authenticated loading uses an isolated URL session. It does not read cookies from the app's shared URL session store; pass any required cookies explicitly with `MediaRequestConfiguration` so StreamKit can apply their domain and path scope.

Bearer mode uses an AVFoundation resource loader and rewrites HLS resource URLs. Finite and open-ended byte-range responses are validated against `Content-Range`, and body bytes are bounded to the returned range. Validate it with your CDN, redirects, byte-range behavior, token refresh policy, and supported HLS features before shipping. Cookies and user-agent configuration remain available for services that use those mechanisms instead.

## FairPlay Streaming

StreamKit includes the first provider-neutral FairPlay key-loading integration. Configure `FairPlayConfiguration` on the media request and implement `FairPlayLicenseProvider` in the host app. StreamKit owns the AVContentKeySession lifecycle, SPC generation, renewal callback routing, and CKC handoff; the app owns the FairPlay certificate, key-URI/content-ID mapping, license-server authentication/protocol, and CKC envelope parsing.

```swift
let source = MediaSource(
    url: protectedHLSURL,
    requestConfiguration: MediaRequestConfiguration(
        fairPlay: FairPlayConfiguration(licenseProvider: appFairPlayProvider)
    )
)
let handle = controller.load(source)
try await handle.waitUntilReady()
```

See [FairPlay Streaming Integration](Documentation/FairPlayIntegration.md) for the provider contract and request lifecycle. The example above passes FairPlay through the managed player; the demo's dedicated Axinom screen demonstrates the same provider contract using lower-level controller APIs so the request lifecycle and diagnostics remain visible. Its public protected HLS vector is preconfigured. A user-provided live run confirmed HTTP 200 from the license endpoint, AVFoundation key acceptance, and playback reaching `.playing`. The token is included in the demo source and compiled sample solely for Axinom's public test asset; do not put production tokens in source. You can enter your own tenant values at runtime. Diagnostics omit the token and DRM payloads. This is an evaluation harness, not production credential management: use your app-approved FPS certificate and secure entitlement/token flow in production. End-to-end renewal and real entitlement-rejection behavior require provider-issued test materials. Package tests simulate provider rejection/network errors, empty CKC, cancellation, and public-error redaction; they do not simulate HTTP parsing, AVFoundation key challenges, or real renewal. Offline/persistable keys are not supported. If the HLS origin also needs bearer authorization, configure that separately; FairPlay license-server authentication remains the provider's responsibility.

## Documentation

- [Architecture Overview](Documentation/Architecture.md) - Core design principles
- [Contributor Guide](Documentation/Contributing.md) - Source map, playback flow, ownership rules, and validation commands
- [Playback State Machine](Documentation/PlaybackStateMachine.md) - Intent vs Phase details
- [Multi-Player Architecture](Documentation/MultiPlayerArchitecture.md) - Instance isolation
- [FairPlay Streaming Integration](Documentation/FairPlayIntegration.md) - Provider contract and protected HLS flow
- [Demo Application](Examples/StreamKitDemo/) - Complete integration examples

## Current Limitations

- iOS only (no macOS/tvOS/watchOS support)
- AVFoundation-based playback only
- No StreamKit-designed custom controls; use the managed AVKit view or build app-owned controls with `StreamVideoView`
- No advertising; the public Axinom FairPlay vector is verified, while customer-provider renewal and failure scenarios remain unverified
- StreamKit does not provide a full playback-controls UI or set a package-wide orientation policy. Pair `StreamVideoView` with `StreamPictureInPictureController` for app-owned controls, or use `StreamAVPlayerView` for AVKit's standard controls. The demo requests landscape for its custom fullscreen mode.
- Offline playback requires application-level file handling

## Example Application

See the [StreamKitDemo](Examples/StreamKitDemo/) target for a complete example showing:
- Basic playback controls
- Managed one-session AVKit player view
- State observation
- Track selection UI
- Concurrent independent players
- Error handling scenarios
- Host-scoped bearer authentication for protected HLS streams
- Dedicated Axinom public FairPlay test vector and provider-integration guide
- Audio-session interruption recovery and background audio setup
- AVKit system controls, Picture in Picture, AirPlay affordances, and custom fullscreen landscape behavior

The demo's separate **Protected Playback** section is prefilled with a public Mux HLS sample (`https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`) and its trusted host. Leave the token blank to check ordinary HLS playback. To exercise bearer authentication, replace the URL and trusted-host list with a protected stream you control and enter its valid development token. The public sample is not bearer-protected and does not verify authenticated playback.

## Continuous Integration

GitHub Actions is configured to run the Swift package tests and demo unit/UI tests on an iOS Simulator using the Xcode 27 runner. The hosted Xcode 27 image is currently a public preview, and a hosted run of the latest workflow state is pending. Latest local validation passed the package tests and four demo unit tests on iPhone 17 Pro / iOS 26.5; the UI test run stalled on Xcode debugger-version lookup warnings and was interrupted, so no latest UI test result is claimed.
