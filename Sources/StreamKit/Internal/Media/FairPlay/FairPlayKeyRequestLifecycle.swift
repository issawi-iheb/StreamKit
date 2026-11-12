import Foundation

/// Coordinates asynchronous FairPlay work and exactly-once request completion.
/// AVFoundation-specific request and response objects stay at the adapter edge.
@MainActor
final class FairPlayKeyRequestLifecycle<Request: AnyObject> {
    typealias Processor = @MainActor (Request, Bool) async throws -> Data
    typealias SuccessHandler = @MainActor (Request, Data) -> Void
    typealias FailureHandler = @MainActor (Request, Error) -> Void
    typealias FailureMapper = @MainActor (Error) -> Error

    private struct ActiveRequest {
        let request: Request
        let task: Task<Void, Never>
    }

    private let processor: Processor
    private let successHandler: SuccessHandler
    private let failureHandler: FailureHandler
    private let failureMapper: FailureMapper

    private var activeRequests: [ObjectIdentifier: ActiveRequest] = [:]
    private var seenRequests: [WeakRequestReference<Request>] = []
    private var isInvalidated = false

    init(
        processor: @escaping Processor,
        successHandler: @escaping SuccessHandler,
        failureHandler: @escaping FailureHandler,
        failureMapper: @escaping FailureMapper
    ) {
        self.processor = processor
        self.successHandler = successHandler
        self.failureHandler = failureHandler
        self.failureMapper = failureMapper
    }

    func begin(_ request: Request, isRenewal: Bool) {
        guard markAsSeen(request) else { return }

        guard !isInvalidated else {
            failureHandler(request, CancellationError())
            return
        }

        let identifier = ObjectIdentifier(request)
        let processor = self.processor
        let failureMapper = self.failureMapper

        let task = Task { @MainActor [weak self] in
            do {
                let responseData = try await processor(request, isRenewal)
                try Task.checkCancellation()
                self?.finish(request, identifier: identifier, result: .success(responseData))
            } catch is CancellationError {
                self?.finish(
                    request,
                    identifier: identifier,
                    result: .failure(CancellationError())
                )
            } catch {
                let mappedError = Task.isCancelled
                    ? CancellationError()
                    : failureMapper(error)
                self?.finish(
                    request,
                    identifier: identifier,
                    result: .failure(mappedError)
                )
            }
        }

        activeRequests[identifier] = ActiveRequest(request: request, task: task)
    }

    /// Rejects an unsupported request while preserving duplicate-callback safety.
    func reject(_ request: Request, with error: Error) {
        guard markAsSeen(request) else { return }
        failureHandler(request, error)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        let pendingRequests = Array(activeRequests.values)
        activeRequests.removeAll()

        for activeRequest in pendingRequests {
            activeRequest.task.cancel()
            failureHandler(activeRequest.request, CancellationError())
        }
    }

    private func finish(
        _ request: Request,
        identifier: ObjectIdentifier,
        result: Result<Data, Error>
    ) {
        guard let activeRequest = activeRequests.removeValue(forKey: identifier),
              activeRequest.request === request else {
            return
        }

        switch result {
        case let .success(responseData):
            successHandler(request, responseData)
        case let .failure(error):
            failureHandler(request, error)
        }
    }

    private func markAsSeen(_ request: Request) -> Bool {
        seenRequests.removeAll { $0.value == nil }
        guard !seenRequests.contains(where: { $0.value === request }) else {
            return false
        }

        seenRequests.append(WeakRequestReference(request))
        return true
    }
}

private final class WeakRequestReference<Request: AnyObject> {
    weak var value: Request?

    init(_ value: Request) {
        self.value = value
    }
}
