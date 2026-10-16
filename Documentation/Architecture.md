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

## Separation of Concerns
- **PlaybackIntent** (application-driven) is independent of **PlaybackPhase** (player-driven)
- Intent does not change automatically based on buffering or transient states
- Phase reflects actual player state regardless of application requests

## Playback Coordinator
- `StreamPlayerController` reconciles Intent and Phase to drive playback behavior
- Playback resumes after buffering when intent is `.play`
- Playback remains paused after buffering when intent is `.pause`
- State changes are published through playback snapshots

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
