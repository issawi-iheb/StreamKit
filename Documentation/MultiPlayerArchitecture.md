# Multi-Player Architecture

## Instance Isolation Model
Each `StreamPlayerController` instance owns or references its own independent playback session. The design ensures that playback state, intent, observers, and resources are not accidentally shared between instances.

## Isolation Requirements
- **Playback State**: Each instance maintains its own `PlaybackPhase`
- **Playback Intent**: Each instance manages its own `PlaybackIntent`
- **Observers**: Callback handlers and observers are instance-specific
- **Resources**: Timers, buffers, and playback-related allocations are not shared

## Permitted Sharing
Shared immutable configuration or services may be appropriate when:
- Configuration values are identical across all instances
- Services are stateless and thread-safe (e.g., format parsers, utility functions)
- Resource pools are explicitly designed for sharing (with proper synchronization)
- Controllers that intentionally share one active-player policy receive the same `AudioPlaybackFocusCoordinator`; it pauses the previous focused controller without sharing engines, playback state, or AVAudioSession configuration

## Extension Boundaries
Extensions must preserve instance isolation unless sharing is explicit and injected:
- **DRM/FairPlay**: License handling and key storage must be instance-specific
- **Advertising**: Ad playback sessions must not interfere with primary content per instance
- **Picture-in-Picture**: PiP routing must respect the originating instance's boundaries

## Implementation Approach
- Instance properties should never be `static` or `class` unless explicitly intended for sharing
- Initializers must establish clear ownership of playback resources
- Deinitializers must completely clean up instance-specific resources
- Shared services must be injected, not accessed via globals or singletons
