# FairPlay Streaming Integration

## Run the Axinom device test

The StreamKit demo includes a live Axinom FairPlay test screen for the public Axinom protected HLS vector. Run the demo on a physical iPhone or iPad (FairPlay playback is not reliably testable in the Simulator) and open **Protected Playback → Axinom FairPlay Test**. The manifest, public evaluation certificate, generic FairPlay license URL, and Axinom public evaluation token for this vector are prefilled to match the public test-player configuration. The token is part of the demo source and compiled sample app, but diagnostics and preferences do not log or persist it. Keep this prefilled value limited to the public test asset; never replace it with a production token in source. You can enter your own tenant values at runtime when testing a tenant-issued token.

The demo obtains the certificate over HTTPS, converts the HLS `skd://` identifier to Axinom's expected UTF-8 content identifier by removing the scheme, posts the AVFoundation-generated SPC as the request body, sends the token in `X-AxDRM-Message`, and returns the response bytes as CKC. It shows playback phase/intent and a timestamped exchange log; before sending, it confirms the token header is non-empty and displays only its character count and destination host. The optional `FairPlayConfiguration` diagnostic handler reports whether AVFoundation accepted the CKC or failed its content-key request, with only the error domain/code. On HTTP failure, the demo shows the status, response host, and Axinom's `X-AxDRM-ErrorMessage` response header. **Copy diagnostics** copies the phase, intent, and exchange log without the token, certificate, SPC, CKC, or full URLs. The demo is an integration harness, not a production credential store. Use a short-lived test token and never place a management API key in the license-token field.

The demo's Axinom public-vector run has been verified: the license request succeeded, AVFoundation accepted the content-key response, and playback reached `.playing`. This exercises the package's real AVContentKeySession and Axinom exchange with an evaluation certificate and test content. It does not establish production readiness: production apps must use their approved FPS certificate, protected content and entitlement policy, and secure token delivery. Validate renewal, expiry, network failure, cancellation, and source replacement as well.

StreamKit has a provider-neutral FairPlay key-loading path for protected HLS. It uses Apple's `AVContentKeySession` API, attaches the session to the `AVURLAsset`, asks AVFoundation to generate the SPC, and returns the license provider's CKC to AVFoundation. Apple's current HLS guidance says to use `AVContentKeySession` for key loading rather than the older `AVAssetResourceLoader` key-loading approach.

## Integration boundary

The consuming app implements `FairPlayLicenseProvider` because the certificate source, key URI/content-ID mapping, license request format, server authentication, and CKC response envelope are specific to the content provider.

```swift
struct AppFairPlayProvider: FairPlayLicenseProvider {
    func applicationCertificate() async throws -> Data {
        // Fetch or return the FairPlay application certificate.
        try await certificateStore.certificate()
    }

    func contentIdentifier(
        for keyIdentifier: String,
        initializationData: Data?
    ) throws -> Data {
        // Convert the HLS skd:// key identifier to the identifier your
        // FairPlay license service expects.
        try contentIDResolver.resolve(keyIdentifier, initializationData: initializationData)
    }

    func contentKey(for request: FairPlayLicenseRequest) async throws -> Data {
        // POST request.streamingContentKeyRequest (the SPC) to your license
        // service, authenticate that request, and return the raw CKC bytes.
        try await licenseClient.requestCKC(
            spc: request.streamingContentKeyRequest,
            contentID: request.contentIdentifier,
            renewing: request.isRenewal
        )
    }
}

let source = MediaSource(
    url: protectedHLSURL,
    requestConfiguration: MediaRequestConfiguration(
        fairPlay: FairPlayConfiguration(licenseProvider: AppFairPlayProvider())
    )
)
let handle = controller.load(source)
try await handle.waitUntilReady()
```

The example is illustrative; `certificateStore`, `contentIDResolver`, and `licenseClient` are app-owned dependencies. StreamKit does not bundle or fetch a certificate, implement a vendor-specific license protocol, or include secrets.

## Request lifecycle

1. A FairPlay-enabled `MediaSource` is loaded. StreamKit creates an `AVContentKeySession` for that source and attaches its `AVURLAsset` as a recipient.
2. AVFoundation supplies a content-key request. StreamKit reads the key URI and initialization data and asks the provider to convert them to the license service's content identifier.
3. StreamKit obtains the application certificate and calls `makeStreamingContentKeyRequestData` to create the SPC.
4. The provider sends the SPC to its license server and returns the raw CKC bytes. Renewal callbacks use the same exchange and are identified by `isRenewal`.
5. StreamKit wraps the CKC in `AVContentKeyResponse` and gives it back to AVFoundation.
6. Replacing or cancelling a load, or shutting down the controller, cancels outstanding key tasks and removes the asset recipient.

Provider methods are `async`/`Sendable` so apps can use their own isolated networking and refresh logic. They should honor task cancellation, avoid logging SPC/CKC/certificate data, and return raw CKC bytes rather than a JSON/base64 envelope. StreamKit redacts provider errors before passing failures to playback state.

## Scope and validation

- FairPlay is separate from bearer authentication. Bearer configuration authorizes HLS playlists/segments on trusted media hosts. License-server authentication belongs inside the app's `FairPlayLicenseProvider`. A source may need both configurations.
- StreamKit rejects a FairPlay-configured source unless its media URL uses HTTPS. Keep the license-server transport secure inside the provider as well.
- Offline/persistable keys are explicitly unsupported in this first integration slice.
- Package tests exercise the isolated certificate/content-ID/SPC/CKC orchestration with a mock provider, including empty-data rejection and cancellation checkpoints. They do not emulate AVFoundation's SPC output or prove FairPlay playback. End-to-end acceptance requires the app's approved FPS certificate, a provider-compatible license endpoint, a protected HLS asset, and device testing for initial keys, renewal, expiry/failure, cancellation, and stream switching.
- The demo has a live Axinom test screen for its public protected HLS vector and a prefilled public evaluation token. It performs real certificate retrieval and license exchange through the package's AVContentKeySession path. The public vector is now verified to reach `.playing` in a live run. A separate package-level mock exchange test remains useful for deterministic orchestration checks; it does not replace validation against production content and credentials.
