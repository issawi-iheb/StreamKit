# StreamKit Architecture

## Public API Responsibilities
- `StreamPlayerController`: Main interface for applications to control playback
- `MediaSource`: Represents media to be played (URL, file, etc.)
- `PlayerConfiguration`: Immutable settings for player behavior

## PlaybackCore Responsibilities
- `PlaybackIntent`: Describes what the application wants (play/pause)
- `PlaybackPhase`: Describes what the player is currently doing
- `PlaybackSnapshot`: Future - captures playback state at a point in time
- `PlaybackFailure`: Future - detailed error information

## Separation of Concerns
- **PlaybackIntent** (application-driven) is independent of **PlaybackPhase** (player-driven)
- Intent does not change automatically based on buffering or transient states
- Phase reflects actual player state regardless of application requests

## Future Playback Coordinator
- Will reconcile Intent and Phase to drive actual playback behavior
- Handle automatic resumption after buffering when intent is `.play`
- Prevent resumption when intent is `.pause` (even after buffering completes)
- Manage state transitions and observer notifications

## Platform Boundary
- **Platform-independent**: Intent, Phase, Snapshot, Failure enums
- **Platform-dependent**: Actual AVFoundation integration in player implementation
- Core architecture remains testable and reusable across Apple platforms
