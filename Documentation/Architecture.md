# StreamKit Architecture

## Public API Responsibilities
- `StreamPlayerController`: Main interface for applications to control playback
- `MediaSource`: Represents media to be played (URL, file, etc.)
- `PlayerConfiguration`: Immutable settings for player behavior

## PlaybackCore Responsibilities
- `PlaybackIntent`: Describes what the application wants (play/pause)
- `PlaybackPhase`: Describes what the player is currently doing
- `PlaybackSnapshot`: Captures playback state at a point in time
- `PlaybackFailure`: Carries normalized playback error information
- `MediaBearerAuthentication`: Supplies per-resource bearer tokens scoped to exact HTTPS hosts
- `FairPlayConfiguration` and `FairPlayLicenseProvider`: Bind a source to the app-owned FairPlay certificate/content-ID/license-server integration

## Separation of Concerns
- **PlaybackIntent** (application-driven) is independent of **PlaybackPhase** (player-driven)
- Intent does not change automatically based on buffering or transient states
- Phase reflects actual player state regardless of application requests

## Playback Coordinator
- `StreamPlayerController` reconciles Intent and Phase to drive playback behavior
- Playback resumes after buffering when intent is `.play`
- Playback remains paused after buffering when intent is `.pause`
- State changes are published through playback snapshots
- Each controller consumes interruption events from an injected `AudioInterruptionSource`. The system adapter owns the iOS notification subscription and translates notifications into small `Sendable` events; the controller applies policy, pauses its own engine, and conditionally resumes when the interruption ends. Resumption requires a prior play intent, the configured policy, and iOS's `shouldResume` indication.

## Audio Session Ownership
- `AVAudioSession` is process-wide; the host app owns its category, mode, activation, and background-audio capability.
- StreamKit observes interruptions per controller. The adapter owns and removes its notification observer during `shutdown()`, while tests inject a controllable source without depending on global notification state.
- `PlayerConfiguration.automaticallyResumesAfterAudioInterruption` defaults to `true`; explicit user pause during an interruption prevents resumption.
- Every live controller independently handles the same process-wide interruption. StreamKit does not yet arbitrate audio focus when multiple controllers have play intent; hosts should manage that policy until a shared focus policy is defined.
- The demo configures `.playback` / `.moviePlayback`, activates the session asynchronously on iOS 27+ (and off the main thread on earlier supported releases), and opts into the `audio` background mode. A consuming app must configure its own target similarly if it needs background audio.
- The demo's synthetic interruption controls exercise notification translation and controller policy; they do not emulate iOS audio routing, Siri, calls, or background execution.

## Runtime architecture diagram

```mermaid
flowchart LR
    App[Host app or StreamKit demo] -->|MediaSource + configuration| Controller[StreamPlayerController]
    Controller --> Engine[AVFoundation playback engine]
    Engine --> Asset[AVURLAsset and AVPlayerItem]
    Asset --> Player[AVPlayer renders media]
    Engine -->|clear or ordinary HTTPS| Native[AVFoundation native loading]
    Engine -->|bearer-authenticated HLS| Loader[Authenticated resource loader]
    Loader --> TokenProvider[Host token provider]
    Loader --> Origin[HLS origin]
    Asset -->|FairPlay key request| KeySession[FairPlayContentKeySession]
    KeySession --> Exchange[FairPlayKeyExchange]
    Exchange --> Provider[Host FairPlayLicenseProvider]
    Provider --> Certificate[App certificate source]
    Provider --> License[License service]
    License -->|CKC bytes| Provider
    Provider --> Exchange
    Exchange -->|CKC| KeySession
    KeySession -->|AVContentKeyResponse| Asset
    Engine --> Snapshots[Playback snapshots]
    Controller --> Snapshots
    KeySession -. redacted key result .-> Diagnostics[Optional host diagnostics]
```

The diagram shows ownership and data flow, not a deployment topology. FairPlay certificate retrieval, key-identifier mapping, license HTTP/authentication, and response-envelope parsing belong to the host provider. The demo's Axinom provider is sample-only. The Axinom public test vector has now played successfully in a live demo run; production-provider and lifecycle acceptance checks remain open.

## Platform Boundary
- **Platform-independent**: Intent, Phase, Snapshot, Failure enums
- **Platform-dependent**: Actual AVFoundation integration in player implementation
- Core architecture remains testable and reusable across Apple platforms

## Authenticated Media Requests
- Regular HTTPS media continues through AVFoundation's native `AVURLAsset` loading path.
- Bearer-authenticated media uses an `AVAssetResourceLoader` owned by the playback engine.
- HLS playlist references are rewritten to the resource-loader scheme so tokens can be requested for segments, keys, and child playlists.
- The async token provider is called per resource, allowing the host app to refresh credentials.
- Exact host allowlisting and HTTPS-only transport prevent credentials from being sent to unrelated or cleartext origins.
- The authenticated loader uses an ephemeral URL session with automatic cookie storage disabled; only explicitly configured `MediaCookie` values are attached.
- The demo presents bearer-authenticated playback as a separate example. It is prefilled with a public Mux HLS stream so ordinary playback can be checked without credentials; supplying a token enables the bearer-authenticated path for a protected origin. The public sample does not verify bearer authentication.
- Autoplay keeps the snapshot at `.ready` with `.play` intent until AVFoundation reports `.playing` or `.waiting`, so observed phase reflects the engine instead of the play request.

## FairPlay key loading
- The playback engine owns one `FairPlayContentKeySession` per FairPlay-enabled media item and attaches its `AVURLAsset` as the key recipient.
- `FairPlayContentKeySession` delegates certificate acquisition, content-ID mapping, and SPC-to-CKC server exchange through the `Sendable` app-provided `FairPlayLicenseProvider`.
- StreamKit uses AVFoundation's `AVContentKeySession` API for key loading. It handles initial and renewal requests and removes/cancels the per-item session resources on replacement, cancellation, or shutdown.
- License-server HTTP, server authentication, response-envelope parsing, and certificate retrieval/caching stay outside the core SDK. This keeps DRM vendor dependencies out of StreamKit and makes the provider mockable.
- The bearer loader and FairPlay session are separate. Bearer authentication covers HLS media resources; the FairPlay provider independently authenticates license requests. A source can configure both when required.
- The demo's Axinom FairPlay test adapter is sample-only: it fetches a configured certificate, strips `skd://` from the Axinom key identifier, posts the SPC, and supplies the public test token in `X-AxDRM-Message`. It uses standard `URLSession` and is not a dependency of the StreamKit package. The public test token is embedded only for Axinom's public test asset; diagnostics do not log it. The UI displays request stage and safe HTTP/AxDRM error diagnostics.
- `FairPlayConfiguration` can optionally deliver redacted content-key response accepted/failed events to the host for diagnostics. It excludes content identifiers and DRM payloads; the sample uses it to tell key-response processing apart from later media buffering.
- Persistable/offline keys are rejected as unsupported in this first slice. Playback of Axinom's public FairPlay test vector is verified in a live demo run. Provider-specific renewal, expiry, cancellation, source replacement, and production FPS materials still require validation.
