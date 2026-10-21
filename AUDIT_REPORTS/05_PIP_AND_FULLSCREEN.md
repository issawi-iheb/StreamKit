# Picture in Picture and fullscreen

## Existing PiP paths

The custom path is already implemented in `Sources/StreamKit/PublicAPI/StreamPictureInPictureController.swift`. It checks support and possibility, retains a protected layer during transition, tracks mounted layers weakly, avoids controller replacement while starting/active, invalidates queued KVO updates by generation, responds to start/stop/failure delegate callbacks, and wraps restoration completion in a lock-protected idempotency gate. `StreamVideoView` registers/unregisters layers and preserves their player connection during PiP transition.

A separate `StreamAVPlayerView` wraps AVPlayerViewController and forwards restoration to host app. This path delegates standard AVKit UI; do not conflate it with the custom-layer controller. Both depend on host app audio/background configuration. PiP must be started in response to user action as documented.

**PIP-001 — High, Test gap:** source logic has defensive lifecycle handling, but no PiP tests exist in `Tests/StreamKitTests` or demo UI tests by inspection. No claim that PiP starts, restores UI, or survives view teardown was reproduced. Add device tests for unsupported device, not-possible state, start/stop, failed start, host restoration callback once/never, view removal while active, and teardown. Restoration completion can remain outstanding if the host handler never calls it; define that as a host contract and test with timeout diagnostics. Exact implementation target: `StreamPictureInPictureController.swift:65-85, 230-295`; `Sources/StreamKit/PublicAPI/StreamAVPlayerView.swift:107-120` restoration delegate. No speculative AVKit behavior patch is justified without a device reproduction.

## Fullscreen

The SDK has no fullscreen controller or orientation policy; demo includes custom fullscreen presentation/orientation helpers (including uncommitted current-tree files). Treat fullscreen as consumer/demo behavior. The host owns presentation, orientation policy, dismissal, and restoration. Do not present the demo as SDK-managed fullscreen.

**FULL-001 — Medium, Test gap:** no package fullscreen API exists; validate demo's custom presentation lifecycle on iPad/iPhone, orientation lock changes, interactive dismissal, and PiP/fullscreen handoff. This is a demo integration risk, not a missing core feature.

## State/ownership sequence

```mermaid
sequenceDiagram
  participant Host
  participant View as StreamVideoView
  participant P as StreamPictureInPictureController
  participant AV as AVPictureInPictureController
  Host->>View: construct with controller and shared PiP coordinator
  View->>P: attach(layer)
  P->>AV: create controller; observe possible
  Host->>P: start from user action
  P->>P: retain protected layer, mark starting
  AV-->>P: didStart / failedToStart
  Host->>P: stop
  AV-->>P: didStop
  P->>P: clear transition state; attach latest mounted layer
  AV-->>Host: restore UI callback
  Host-->>AV: completion exactly once
```

Use one `StreamPictureInPictureController` for all views rendering the same playback controller; do not share it across independent players. Retain the `StreamPlayerController` during PiP and call `shutdown()` only when that playback session is truly finished, not merely when its inline view disappears.

## Runtime acceptance

Run on supported physical iPhone/iPad with background audio capability and host audio session configured. Verify custom PiP and AVKit system controls separately. Simulator-only tests can test view wiring but cannot establish supported device PiP behavior. Record OS/device, exact user action, callbacks and final visibility state.
