# DRM and security

## Actual DRM scope

FairPlay Streaming is implemented for protected HLS through `AVContentKeySession`, per-item recipient ownership, provider-neutral `FairPlayLicenseProvider`, certificate retrieval, content-ID mapping, SPC generation, CKC exchange/response and renewal request routing. Offline/persistable keys are explicitly rejected (`FairPlayContentKeySession.swift:99-110`). The app owns certificate source, content identifier mapping, license protocol/authentication and CKC envelope parsing. Do not describe Widevine/PlayReady or offline DRM as supported.

For bearer-authenticated HLS, loader uses an ephemeral URLSession with shared cookie storage disabled, exact HTTPS host allowlisting, per-request token retrieval, cookie/path scoping, URI rewriting, byte-range validation, and playlist size cap (`AuthenticatedMediaResourceLoader.swift:140-230, 353-426`). FairPlay server authentication is separate from media bearer auth. Playback failure mapping redacts FairPlay provider errors.

## Findings

**DRM-001 — High, Test gap:** no committed deterministic test establishes actual AVContentKeySession renewal, late callback behavior during source replacement, or two simultaneous protected player instances. Existing `FairPlayKeyExchangeTests` cover provider-level orchestration; engine tests reject insecure FairPlay URLs. Repository docs report a live public Axinom test vector reaching `.playing`, but this audit did not reproduce it. Add mock session-boundary tests plus real-device provider acceptance using entitlement-approved test materials. Exact locations: `FairPlayContentKeySession.swift:32-53, 57-129, 131-200`; tests `FairPlayKeyExchangeTests.swift` and `AVFoundationPlaybackEngineTests.swift`.

**DRM-002 — Medium, Potential risk:** SPC callback bridges with checked continuation but no cancellation handler (`FairPlayContentKeySession.swift:202-227`). On invalidation, task is canceled and active request is completed with cancellation; if callback has not returned, a task can remain suspended and retain request/session context. Add a cancellation-aware adapter or document AVFoundation callback lifetime after verifying whether its API supports cancellation. Ensure late callback cannot process a second response; existing `finish` checks active request identity (`184-199`).

**SEC-001 — Medium, Security review:** security controls are well scoped, but redirect behavior is not demonstrated by source-level test evidence across every rewrite path. Authenticated requests use `URLSessionTaskDelegate` to validate redirects; inspect/test all redirected playlist, segment, and key-host combinations before shipping. Exact path `AuthenticatedMediaResourceLoader.swift:489-555`; add tests proving authorization is stripped/denied when redirected to an untrusted host and HTTPS downgrade is rejected. The public sample's Axinom evaluation token is described by repository docs as public test material; do not classify it as a confirmed secret leak. Production credentials must remain app-managed and never be copied into sample source.

## Lifecycle

`FairPlayContentKeySession.invalidate()` removes the recipient, clears delegate, cancels each task, and resolves active requests once. Per-request IDs are `ObjectIdentifier(AVContentKeyRequest)` and removed before resolving, protecting late replies from double completion. Session is per engine/source, which provides a sound isolation default. Provider is `Sendable`, but apps must still make shared token/certificate services concurrency-safe and honor cancellation.

The package rejects non-HTTPS FairPlay source URL (`AVFoundationPlaybackEngine.swift:69-79`) and maps provider errors to generic public failure (`FairPlayContentKeySession.swift:170-180`). Diagnostics provide only safe domain/code and accepted/failure events. Check provider logs outside this boundary; SDK cannot prevent app-side secret logging.

## Required validation

Use vendor-approved certificate/content and a physical device: initial playback, renewal, expiration, entitlement denial, malformed/empty CKC, network cancellation, source switch with SPC/license pending, shutdown, and concurrent players. Capture no SPC/CKC/certificate/token values in test logs. Include a host app authentication review. Offline key persistence is not supported and must not be promised.
