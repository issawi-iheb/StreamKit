# StreamKit

A reusable Swift media-player SDK for iOS 16+ built with Swift 6.4. StreamKit provides independent playback instances with state observation, track selection, and clean resource management.

## Requirements

- iOS 16.0 or later
- Swift 6.4 toolchain

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

Bearer mode uses an AVFoundation resource loader and rewrites HLS resource URLs. Validate it with your CDN, redirects, byte-range behavior, token refresh policy, and supported HLS features before shipping. Cookies and user-agent configuration remain available for services that use those mechanisms instead.

## Documentation

- [Architecture Overview](Documentation/Architecture.md) - Core design principles
- [Playback State Machine](Documentation/PlaybackStateMachine.md) - Intent vs Phase details
- [Multi-Player Architecture](Documentation/MultiPlayerArchitecture.md) - Instance isolation
- [Demo Application](Examples/StreamKitDemo/) - Complete integration examples

## Current Limitations

- iOS only (no macOS/tvOS/watchOS support)
- AVFoundation-based playback only
- No built-in UI controls (use StreamVideoView with custom controls)
- No advertising or DRM/FairPlay support
- Picture-in-Picture requires additional implementation
- Offline playback requires application-level file handling

## Example Application

See the [StreamKitDemo](Examples/StreamKitDemo/) target for a complete example showing:
- Basic playback controls
- State observation
- Track selection UI
- Concurrent independent players
- Error handling scenarios
- Host-scoped bearer authentication for protected HLS streams
