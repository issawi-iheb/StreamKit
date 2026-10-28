import AVFoundation
import Foundation

/// Owns the FairPlay key session associated with one AVPlayerItem.
///
/// AVContentKeySession is used for key loading. Apple has directed HLS clients
/// away from AVAssetResourceLoader-based FairPlay key loading.
@MainActor
final class FairPlayContentKeySession: NSObject, AVContentKeySessionDelegate {
    private let session: AVContentKeySession
    private let exchange: FairPlayKeyExchange
    private let diagnosticHandler: (@Sendable (FairPlayKeySessionDiagnostic) -> Void)?
    private let onDiagnostic: ((FairPlayKeySessionDiagnostic) -> Void)?
    private let delegateQueue = DispatchQueue(label: "StreamKit.FairPlayContentKeySession")
    private lazy var requestLifecycle = FairPlayKeyRequestLifecycle<AVContentKeyRequest>(
        processor: { [weak self] request, isRenewal in
            guard let self else { throw CancellationError() }
            return try await self.makeContentKey(for: request, isRenewal: isRenewal)
        },
        successHandler: { request, contentKey in
            request.processContentKeyResponse(
                AVContentKeyResponse(fairPlayStreamingKeyResponseData: contentKey)
            )
        },
        failureHandler: { request, error in
            request.processContentKeyResponseError(error)
        },
        failureMapper: { error in
            FairPlayErrorMapping.playbackFailure(for: error)
        }
    )
    private var isInvalidated = false
    private var recipient: AVURLAsset?

    init(
        configuration: FairPlayConfiguration,
        onDiagnostic: ((FairPlayKeySessionDiagnostic) -> Void)? = nil
    ) {
        self.exchange = FairPlayKeyExchange(provider: configuration.licenseProvider)
        self.diagnosticHandler = configuration.diagnosticHandler
        self.onDiagnostic = onDiagnostic
        self.session = AVContentKeySession(keySystem: .fairPlayStreaming)
        super.init()
        session.setDelegate(self, queue: delegateQueue)
    }

    func addRecipient(_ asset: AVURLAsset) {
        guard !isInvalidated else { return }
        recipient = asset
        session.addContentKeyRecipient(asset)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if let recipient {
            session.removeContentKeyRecipient(recipient)
            self.recipient = nil
        }
        session.setDelegate(nil, queue: nil)
        requestLifecycle.invalidate()
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        Task { @MainActor [weak self] in
            self?.beginProcessing(keyRequest, isRenewal: false)
        }
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        Task { @MainActor [weak self] in
            self?.beginProcessing(keyRequest, isRenewal: true)
        }
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequestDidSucceed keyRequest: AVContentKeyRequest
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let event = FairPlayKeySessionDiagnostic.contentKeyResponseAccepted
            self.onDiagnostic?(event)
            self.diagnosticHandler?(event)
        }
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError error: any Error
    ) {
        let failure = error as NSError
        let event = FairPlayKeySessionDiagnostic.contentKeyRequestFailed(
            errorDomain: failure.domain,
            errorCode: failure.code
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onDiagnostic?(event)
            self.diagnosticHandler?(event)
        }
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        didProvide persistableContentKeyRequest: AVPersistableContentKeyRequest
    ) {
        Task { @MainActor [weak self] in
            self?.requestLifecycle.reject(
                persistableContentKeyRequest,
                with: PlaybackFailure(
                    code: .unsupportedConfiguration,
                    message: "Offline FairPlay keys are not supported by this StreamKit integration."
                )
            )
        }
    }

    private func beginProcessing(
        _ request: AVContentKeyRequest,
        isRenewal: Bool
    ) {
        requestLifecycle.begin(request, isRenewal: isRenewal)
    }

    private func makeContentKey(
        for request: AVContentKeyRequest,
        isRenewal: Bool
    ) async throws -> Data {
        let keyIdentifier: String
        if let keyURI = request.identifier as? URL {
            keyIdentifier = keyURI.absoluteString
        } else if let value = request.identifier as? String {
            keyIdentifier = value
        } else {
            throw PlaybackFailure(
                code: .unsupportedConfiguration,
                message: "The FairPlay key request did not contain a supported identifier."
            )
        }

        return try await exchange.contentKey(
            for: keyIdentifier,
            initializationData: request.initializationData,
            isRenewal: isRenewal
        ) { certificate, contentIdentifier in
            try await self.streamingContentKeyRequestData(
                from: request,
                certificate: certificate,
                contentIdentifier: contentIdentifier
            )
        }
    }

    private func streamingContentKeyRequestData(
        from request: AVContentKeyRequest,
        certificate: Data,
        contentIdentifier: Data
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            request.makeStreamingContentKeyRequestData(
                forApp: certificate,
                contentIdentifier: contentIdentifier,
                options: nil
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: PlaybackFailure(
                            code: .authentication,
                            message: "AVFoundation did not create a FairPlay key request."
                        )
                    )
                }
            }
        }
    }
}
