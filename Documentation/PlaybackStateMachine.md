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
- `StreamPlayerController` uses intent to decide whether to start after loading and preserves it across waiting states.
- Neither type depends on AVFoundation.

## Representative Intent/Phase Combinations

| PlaybackIntent | PlaybackPhase | Interpretation |
|---|---|---|
| `.play` | `.loading` | Playback is requested while the source is loading. |
| `.play` | `.playing` | Playback is requested and currently progressing. |
| `.play` | `.waiting` | Playback is requested but currently waiting for data or another condition. |
| `.play` | `.paused` | Playback is still requested, but the player is currently paused; an explicit play request can retry. |
| `.pause` | `.paused` | Playback is not requested and is currently paused. |
| `.pause` | `.ready` | The source is ready and playback is not requested. |
| either | `.failed` | A failure occurred; the snapshot carries its details. |

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
4. The controller requests a pause and reports `.paused`.
5. Buffering finishes, but playback does not resume because the intent remains `.pause`.
6. When user resumes: application sets intent to `.play`; if media is ready, phase transitions to `.playing`.
   Late playback callbacks do not change the intent; a `.playing` event is ignored while intent is `.pause`.

## Note on Implementation

The enums define the state values; `StreamPlayerController` and
`AVFoundationPlaybackEngine` implement the transition and coordination behavior,
including resumption after buffering when playback intent remains `.play`.
