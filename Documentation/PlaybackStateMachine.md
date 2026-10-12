# Playback State Machine Overview

This document describes the relationship between `PlaybackIntent` and `PlaybackPhase` in the StreamKit playback core.

## Responsibilities

### PlaybackIntent
- Represents the **desired** playback behavior requested by the application.
- Independent of the player's current state.
- Does not change automatically based on buffering or other transient states.
- Values: `.play` (request playback) and `.pause` (request pause).

### PlaybackPhase
- Represents the **current** playback state of the player.
- Describes what the player is currently doing, not what has been requested.
- Independent of playback intent.
- Does not contain detailed error information (see `PlaybackFailure` for errors).
- Values: `.idle`, `.loading`, `.ready`, `.playing`, `.paused`, `.waiting`, `.ended`, `.failed`.

## Key Principles

- `PlaybackIntent` reflects what the application wants.
- `PlaybackPhase` reflects what the player is currently doing.
- The two values are independent and must not be treated as interchangeable.
- Buffering does not automatically change the playback intent.
- Playback coordination logic will use these types to determine whether playback should resume when the media becomes ready.
- Neither type depends on AVFoundation.

## Representative Intent/Phase Combinations

| PlaybackIntent | PlaybackPhase   | Interpretation                                                                 |
|----------------|-----------------|------------------------------------------------------------------------------|
| `.play`        | `.idle`         | Application wants to play, but no media is loaded.                           |
| `.play`        | `.loading`      | Application wants to play; media is being loaded.                            |
| `.play`        | `.ready`        | Application wants to play; media is ready and waiting for start command.     |
| `.play`        | `.playing`      | Application wants to play; playback is in progress.                          |
| `.play`        | `.waiting`      | Application wants to play; playback is stalled due to buffering.             |
| `.play`        | `.ended`        | Application wants to play, but media has ended.                              |
| `.play`        | `.failed`       | Application wants to play, but an error occurred.                            |
| `.pause`       | `.any`          | Application has requested pause; player should not play regardless of phase. |

## Buffering Examples

### Example 1: Automatic Resume After Buffering
1. Application sets intent to `.play`.
2. Player loads media: phase transitions from `.idle` → `.loading` → `.ready`.
3. Application keeps intent at `.play`; player starts playback: phase becomes `.playing`.
4. During playback, network stalls: phase becomes `.waiting` (buffering).
5. Intent remains `.play` (no pause request).
6. Buffering completes: phase transitions back to `.playing` automatically because intent is still `.play`.

### Example 2: User Pauses During Buffering
1. Application sets intent to `.play`.
2. Player loads media: phase transitions from `.idle` → `.loading`.
3. While still buffering (phase `.waiting`), user pauses: application sets intent to `.pause`.
4. The coordinator processes the request and reports `.paused`.
5. Buffering finishes, but playback does not resume because the intent remains `.pause`.
6. When user resumes: application sets intent to `.play`; if media is ready, phase transitions to `.playing`.
   Note: The implementation must prevent late buffering callbacks from overriding a more recent pause request.

## Note on Implementation

The actual state transition logic and automatic resumption behavior are **not** implemented in this version of the enums.
This documentation outlines the intended behavior for a future implementation of the playback coordination layer.