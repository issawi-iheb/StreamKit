# Current SDK and demo status — 2026-10-28

This note updates the audit trail with the current branch's integration and demo evidence. It is a focused code and demo review, not a new full production-readiness audit. The historical findings remain applicable unless explicitly superseded below.

**Revision:** `81496beb630a89348943236f4acdf5392bfc8112` (`engineplayer-refactoring`, also at `origin/engineplayer-refactoring` when recorded).

## Integration and architecture

The SDK now documents three practical integration levels in the README and `Documentation/Architecture.md`:

- `StreamPlayerView(source:)` is the managed route. The SDK creates and owns the session for the view's lifetime, presents AVKit's standard controls, and supports system PiP. The host supplies `MediaSource`, provider configuration, and app-wide audio-session policy. Autoplay remains opt-in; the demo turns it on for its managed sample.
- `StreamPlayerController` with `StreamVideoView` is for app-owned controls and layout. Hosts own controller lifetime and may add the custom PiP controller.
- Retained `StreamPlayerSession` or explicit AVKit presentation types are for hosts coordinating route retention, restoration, or presentation lifecycle.

These routes share the same controller and AVFoundation playback engine. Live/VOD semantics, bearer authentication, cookies, user-agent configuration, and FairPlay provider setup remain source-level concerns. The app retains ownership of its credentials, FairPlay service protocol, and `AVAudioSession` configuration. Internal playback and interruption protocols are test seams, not public backend extension points.

This is a useful separation for a small player SDK: the managed facade reduces routine setup while explicit controller/session APIs preserve lifecycle control. The controller remains an orchestrator; further extraction should follow a concrete stable responsibility.

## Demo visuals

The demo home screen now presents the player examples as a more coherent showcase and removes the redundant open-player action from the hero. Player layouts adapt their aspect ratio and supporting panels to available width, including larger iPhone Duo layouts. Managed playback autoplays in the demo only. Two simulator captures are included in the README:

- `Documentation/Screenshots/home-iphone-duo.png` — demo home screen.
- `Documentation/Screenshots/managed-player-fullscreen-iphone-duo.png` — managed AVKit fullscreen during the fullscreen lifecycle UI test.

These images document appearance and the tested fullscreen transition. They do not establish visual acceptance on every device size, orientation, Dynamic Type setting, or OS release.

## Verification recorded for this revision

- Swift source parsing for the changed demo files — passed.
- iOS Simulator demo `build-for-testing` — passed.
- `StreamKitDemoUITests.testManagedPlayerCanEnterAndExitFullscreen` — passed on iPhone Duo simulator running iOS 27.1. The test completed in 39.724 seconds; Xcode emitted debugger-version lookup warnings during launch, but the test result was successful.
- `git diff --check` — passed before the documentation follow-up.
- The repository's prior package validation remains 115 tests across 11 suites, as recorded in the 2026-10-21 audit. This documentation/demo update did not rerun the full package suite.

## Remaining validation limits

The focused fullscreen UI test does not validate physical-device PiP, PiP route restoration, all supported orientations, minimum iOS deployment, live/DVR stream behavior, or FairPlay renewal against production services. Continue to use the findings register and roadmap for production-readiness work; the screenshots are evidence of the demo's current presentation, not a release certification.
