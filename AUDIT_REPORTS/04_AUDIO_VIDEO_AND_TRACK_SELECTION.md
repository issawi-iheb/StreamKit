# Audio, video, and track selection

## Audio session

The library does not set the shared `AVAudioSession` category or activate/deactivate it; this is documented as host ownership in `PlayerConfiguration.swift` and README. `SystemAudioInterruptionSource` subscribes to interruption notifications and forwards `.began` / `.ended(shouldResume)` (`AudioSessionInterruption.swift`). Controller records whether play intent existed, pauses the engine, and resumes only when app preference, OS resume option, and prior intent permit (`StreamPlayerController.swift:442-513`). This avoids an SDK silently taking process-wide audio policy. Route changes, media-services reset, ducking policy, and competing apps are not handled: document app responsibilities and add integration scenarios rather than add global session ownership.

## Track selection

Engine loads `.audible` and `.legible` selection groups asynchronously and checks item identity/generation after each await. Public track IDs are positional (`audio:<index>`, `subtitle:<index>`); selection resolves them against the current group and rejects stale/out-of-range indices (`AVFoundationPlaybackEngine.swift:528-637`). This is safe within a current item but IDs are not stable across source replacement or changed manifests. Subtitle `nil` disables selection. No default-language preference policy exists; host app chooses.

**AUDIO-001 — Low, Enhancement:** document that track identifiers are item-scoped, and add language-preference selection only as opt-in policy. Exact code location: `Sources/StreamKit/PublicAPI/MediaTrack.swift:7-10` and engine ID construction `AVFoundationPlaybackEngine.swift:542-562`. Test reordered options and nil locale before adding a persistent identifier API.

## Rendering and presentation

`StreamVideoView` is an iOS SwiftUI wrapper over a `UIViewRepresentable` with `AVPlayerLayer`; controller owns player lifetime, and dismantling detaches PiP then clears player only if not transitioning (`StreamVideoView.swift:14-69, 74-123`). `StreamAVPlayerView` is a UIKit AVPlayerViewController adapter providing standard AVKit controls, AirPlay/PiP affordances, and one-shot restoration completion. It is independent from custom PiP; apps should use one presentation route intentionally. Current public API does not provide custom controls or own fullscreen policy.

**VIDEO-001 — Medium, Test gap:** verify update/dismantle/reparent behavior across SwiftUI identity changes and controller replacement; `updateUIView` assigns the new player and PiP controller but there is no UI lifecycle test. Add an iOS UI integration test that switches controller identity and confirms the layer follows the new controller and old controller remains app-owned. See testing plan.

## Audio/video synchronization and limitations

AVPlayer handles media synchronization. No separate audio/video clocks or buffers exist in package code. `AVPlayerItem` output and rendering are delegated to AVFoundation. Playback continuity across audio route changes, AirPlay, interruptions and PiP must be validated on real devices. No claim of platform behavior is made from source inspection.

## Proposed test matrix

- `audioInterruptionPreservesExplicitPause`: package unit test, existing interruption source seam; ensure user pause during interruption does not resume.
- `trackSelectionRejectsStaleItemOptions`: package unit test at controller seam; source replacement while group load suspended.
- `swiftUIViewRebindsPlayerAfterControllerChange`: iOS simulator UI test in `Examples/StreamKitDemo/StreamKitDemoUITests/StreamKitDemoUITests.swift`.
- `airPlayPiPAndInterruptionContinuity`: physical iOS device with route accessory/system controls.
