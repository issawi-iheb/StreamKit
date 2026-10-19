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
    private let delegateQueue = DispatchQueue(label: "StreamKit.FairPlayContentKeySession")
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var isInvalidated = false
    private var recipient: AVURLAsset?

    init(configuration: FairPlayConfiguration) {
        self.exchange = FairPlayKeyExchange(provider: configuration.licenseProvider)
        self.diagnosticHandler = configuration.diagnosticHandler
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
        for (identifier, task) in tasks {
            task.cancel()
            if let request = activeRequests[identifier] {
                finish(
                    request,
                    identifier: identifier,
                    response: nil,
                    error: CancellationError()
                )
            }
        }
        tasks.removeAll()
        activeRequests.removeAll()
    }

    private var activeRequests: [ObjectIdentifier: AVContentKeyRequest] = [:]

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
            self?.diagnosticHandler?(.contentKeyResponseAccepted)
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
            self?.diagnosticHandler?(event)
        }
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        didProvide persistableContentKeyRequest: AVPersistableContentKeyRequest
    ) {
        Task { @MainActor in
            persistableContentKeyRequest.processContentKeyResponseError(
                PlaybackFailure(
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
        guard !isInvalidated else {
            request.processContentKeyResponseError(CancellationError())
            return
        }

        let identifier = ObjectIdentifier(request)
        guard tasks[identifier] == nil else { return }
        activeRequests[identifier] = request
        tasks[identifier] = Task { [weak self] in
            guard let self else { return }
            await self.process(request, identifier: identifier, isRenewal: isRenewal)
        }
    }

    private func process(
        _ request: AVContentKeyRequest,
        identifier: ObjectIdentifier,
        isRenewal: Bool
    ) async {
        defer {
            tasks[identifier] = nil
        }

        do {
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

            let ckc = try await exchange.contentKey(
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
            finish(
                request,
                identifier: identifier,
                response: AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc),
                error: nil
            )
        } catch is CancellationError {
            finish(request, identifier: identifier, response: nil, error: CancellationError())
        } catch {
            // Do not expose provider payloads, URLs, SPCs, or CKCs through the
            // public playback failure.
            finish(
                request,
                identifier: identifier,
                response: nil,
                error: FairPlayErrorMapping.playbackFailure(for: error)
            )
        }
    }

    private func finish(
        _ request: AVContentKeyRequest,
        identifier: ObjectIdentifier,
        response: AVContentKeyResponse?,
        error: Error?
    ) {
        // Remove first so an invalidation racing with a late provider reply
        // cannot resolve the same AVFoundation request twice.
        guard activeRequests[identifier] === request else { return }
        activeRequests[identifier] = nil

        if let response {
            request.processContentKeyResponse(response)
        } else if let error {
            request.processContentKeyResponseError(error)
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
