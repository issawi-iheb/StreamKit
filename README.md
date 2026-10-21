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

## Quick Start

```swift
import StreamKit
import SwiftUI

@MainActor
class PlayerViewModel: ObservableObject {
    private let controller = StreamPlayerController()
    @Published var snapshot: PlaybackSnapshot
    private var observationTask: Task<Void, Never>? = nil

    init() {
        // Observe playback state changes
        self.snapshot = controller.snapshot
        self.observationTask = Task { [weak self] in
            for await snapshot in controller.snapshots {
                self?.snapshot = snapshot
            }
        }
    }

    func loadMedia(url: URL) {
        let mediaSource = MediaSource(url: url)
        let loadHandle = controller.load(mediaSource)

        Task {
            do {
                try await loadHandle.waitUntilReady()
                // Media is ready; playback starts automatically if autoplay=true
                // Manual start: try await controller.play()
            } catch {
                // Handle loading errors (network, invalid URL, etc.)
                print("Failed to load media: \(error)")
            }
        }
    }

    func togglePlayback() {
        Task {
            if snapshot.phase == .playing || snapshot.phase == .waiting {
                await controller.pause()
            } else {
                try? await controller.play()
            }
        }
    }

    func seek(to time: TimeInterval) {
        Task {
            try? await controller.seek(to: time)
        }
    }

    // Call when view disappears or player is no longer needed
    func cleanup() async {
        observationTask?.cancel()
        observationTask = nil
        await controller.shutdown()
    }
}
```

## State Observation

Observe playback state changes using the `snapshots` property, which provides an `AsyncStream<PlaybackSnapshot>`:

```swift
// Start observation (typically in init or viewDidLoad)
let snapshotStream = controller.snapshots
Task {
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

All snapshot delivery occurs on the MainActor due to the `@MainActor` annotation on `StreamPlayerController`.

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
StreamAVPlayerView(
    controller: controller,
    automaticallyStartsPictureInPictureWhenLeavingApp: false
)
.frame(height: 240)
```

If your app can dismiss the player screen while PiP remains active, supply a restoration handler that presents the appropriate screen before calling its completion with `true`:

```swift
StreamAVPlayerView(controller: controller) { completion in
    // Restore the owning player screen here.
    completion(true)
}
```

Automatic PiP is opt-in and should only be enabled when the inline player is the primary content. PiP requires device support, a playback audio session, and the app's `audio` background mode. The host app owns those settings. The demo's **AVKit Player & Picture in Picture** entry lets you switch between `StreamAVPlayerView` and custom `StreamVideoView` rendering. Automatic PiP is available in the AVKit mode; custom controls can start PiP from a user action when the controller reports that PiP is possible. The standalone custom-control demo requests landscape while fullscreen is open, then restores the orientation that was active before fullscreen.

For custom controls, share one `StreamPictureInPictureController` across every `StreamVideoView` rendering the same player:

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
```

`StreamAVPlayerView` and `StreamVideoView` are alternative renderers for one controller; do not display both at the same time.

## Audio Sessions, Interruptions, and Background Playback

StreamKit observes iOS audio-session interruptions for each controller. By default, it resumes playback only when playback was requested before the interruption and iOS reports that resuming is appropriate. An explicit `pause()` during the interruption cancels automatic resumption. Set `automaticallyResumesAfterAudioInterruption: false` in `PlayerConfiguration` to disable that behavior.

`AVAudioSession` is process-wide, so the host application owns its category, mode, and activation policy. For background audio, the host must also enable the `audio` background mode in its app target. The StreamKit demo's **Audio Session & Background Playback** example shows this setup; the package cannot add app capabilities to a consuming application.

Each live controller responds to process-wide interruptions independently. If an app has multiple controllers with play intent, each may resume when iOS allows it; the host app remains responsible for choosing which player owns audio until StreamKit defines a shared audio-focus policy.

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

The token provider is called for media requests, not just the initial playlist. List every exact host that may serve playlists, segments, keys, or redirects. Tokens are never sent to non-HTTPS or non-allowlisted hosts. Authenticated HLS playlists that reference insecure HTTP resources fail instead of downgrading transport. Regular HTTPS playback without bearer authentication keeps using AVFoundation's native loading path.

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

See [FairPlay Streaming Integration](Documentation/FairPlayIntegration.md) for the provider contract and request lifecycle. The demo includes a dedicated Axinom FairPlay test screen for its public protected HLS vector. The manifest, public evaluation certificate, generic FairPlay license endpoint, and public evaluation token for that vector are prefilled. A user-provided live run confirmed HTTP 200 from the license endpoint, AVFoundation key acceptance, and playback reaching `.playing`. The token is included in the demo source and compiled sample solely for Axinom's public test asset; do not put production tokens in source. You can enter your own tenant values at runtime. Diagnostics omit the token and DRM payloads. This is an evaluation harness, not production credential management: use your app-approved FPS certificate and secure entitlement/token flow in production. End-to-end renewal and real entitlement-rejection behavior require provider-issued test materials. Package tests simulate provider rejection/network errors, empty CKC, cancellation, and public-error redaction; they do not simulate HTTP parsing, AVFoundation key challenges, or real renewal. Offline/persistable keys are not supported. If the HLS origin also needs bearer authorization, configure that separately; FairPlay license-server authentication remains the provider's responsibility.

## Documentation

- [Architecture Overview](Documentation/Architecture.md) - Core design principles
- [Playback State Machine](Documentation/PlaybackStateMachine.md) - Intent vs Phase details
- [Multi-Player Architecture](Documentation/MultiPlayerArchitecture.md) - Instance isolation
- [FairPlay Streaming Integration](Documentation/FairPlayIntegration.md) - Provider contract and protected HLS flow
- [Demo Application](Examples/StreamKitDemo/) - Complete integration examples

## Current Limitations

- iOS only (no macOS/tvOS/watchOS support)
- AVFoundation-based playback only
- No built-in UI controls (use StreamVideoView with custom controls)
- No advertising; the public Axinom FairPlay vector is verified, while customer-provider renewal and failure scenarios remain unverified
- StreamKit does not provide a full playback-controls UI or set a package-wide orientation policy. Pair `StreamVideoView` with `StreamPictureInPictureController` for app-owned controls, or use `StreamAVPlayerView` for AVKit's standard controls. The demo requests landscape for its custom fullscreen mode.
- Offline playback requires application-level file handling

## Example Application

See the [StreamKitDemo](Examples/StreamKitDemo/) target for a complete example showing:
- Basic playback controls
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

GitHub Actions runs the Swift package tests and the demo unit/UI tests on an iOS Simulator using the Xcode 27 runner. The hosted Xcode 27 image is currently a public preview. The workflow change has been validated locally on iPhone 17 Pro / iOS 26.5 Simulator; a hosted run of that change is still pending.
