import Foundation

/// Testable orchestration for the provider-specific part of one FairPlay
/// exchange. AVFoundation SPC generation is injected by the key-session
/// adapter; certificate, content-ID, and CKC behavior remains app-owned.
struct FairPlayKeyExchange: Sendable {
    let provider: any FairPlayLicenseProvider

    func contentKey(
        for keyIdentifier: String,
        initializationData: Data?,
        isRenewal: Bool,
        makeSPC: @Sendable (_ certificate: Data, _ contentIdentifier: Data) async throws -> Data
    ) async throws -> Data {
        try Task.checkCancellation()

        let contentIdentifier = try provider.contentIdentifier(
            for: keyIdentifier,
            initializationData: initializationData
        )
        guard !contentIdentifier.isEmpty else {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "The FairPlay provider returned an empty content identifier."
            )
        }

        let certificate = try await provider.applicationCertificate()
        try Task.checkCancellation()
        guard !certificate.isEmpty else {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "The FairPlay application certificate is empty."
            )
        }

        let spc = try await makeSPC(certificate, contentIdentifier)
        try Task.checkCancellation()
        guard !spc.isEmpty else {
            throw PlaybackFailure(
                code: .authentication,
                message: "AVFoundation did not create a FairPlay key request."
            )
        }

        let ckc = try await provider.contentKey(
            for: FairPlayLicenseRequest(
                contentIdentifier: contentIdentifier,
                streamingContentKeyRequest: spc,
                isRenewal: isRenewal
            )
        )
        try Task.checkCancellation()
        guard !ckc.isEmpty else {
            throw PlaybackFailure(
                code: .authentication,
                message: "The FairPlay license provider returned an empty content key."
            )
        }

        return ckc
    }
}

/// Keeps provider details and DRM payload metadata out of public playback errors.
enum FairPlayErrorMapping {
    static func playbackFailure(for _: any Error) -> PlaybackFailure {
        PlaybackFailure(
            code: .authentication,
            message: "The FairPlay license request failed."
        )
    }
}
