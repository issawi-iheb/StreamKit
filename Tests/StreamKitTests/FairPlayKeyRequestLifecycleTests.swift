import Foundation
import Testing
@testable import StreamKit

@Suite("FairPlay key-request lifecycle")
struct FairPlayKeyRequestLifecycleTests {

    @MainActor
    @Test("Renewal requests are marked and duplicate callbacks resolve once")
    func processesRenewalOnce() async {
        let processingStarted = FairPlayLifecycleSignal()
        let releaseProcessing = FairPlayLifecycleSignal()
        let completed = FairPlayLifecycleSignal()
        let request = FakeFairPlayKeyRequest()
        var renewalValues: [Bool] = []
        var successCount = 0
        var failureCount = 0

        let lifecycle = makeLifecycle(
            processor: { _, isRenewal in
                renewalValues.append(isRenewal)
                await processingStarted.signal()
                await releaseProcessing.wait()
                return Data([7])
            },
            successHandler: { _, response in
                #expect(response == Data([7]))
                successCount += 1
                Task { await completed.signal() }
            },
            failureHandler: { _, _ in failureCount += 1 }
        )

        lifecycle.begin(request, isRenewal: true)
        lifecycle.begin(request, isRenewal: false)
        await processingStarted.wait()
        await releaseProcessing.signal()
        await completed.wait()
        lifecycle.begin(request, isRenewal: true)

        #expect(renewalValues == [true])
        #expect(successCount == 1)
        #expect(failureCount == 0)
    }

    @MainActor
    @Test("Invalidation fails an in-flight request once and ignores its late result")
    func invalidationWinsAgainstLateSuccess() async {
        let processingStarted = FairPlayLifecycleSignal()
        let releaseProcessing = FairPlayLifecycleSignal()
        let processorReturned = FairPlayLifecycleSignal()
        let request = FakeFairPlayKeyRequest()
        var successCount = 0
        var failureCount = 0

        let lifecycle = makeLifecycle(
            processor: { _, _ in
                await processingStarted.signal()
                // Deliberately ignore cancellation until the test releases this work.
                await releaseProcessing.wait()
                await processorReturned.signal()
                return Data([9])
            },
            successHandler: { _, _ in successCount += 1 },
            failureHandler: { _, error in
                #expect(error is CancellationError)
                failureCount += 1
            }
        )

        lifecycle.begin(request, isRenewal: false)
        await processingStarted.wait()

        lifecycle.invalidate()
        lifecycle.invalidate()
        #expect(failureCount == 1)

        await releaseProcessing.signal()
        await processorReturned.wait()
        await Task.yield()

        #expect(successCount == 0)
        #expect(failureCount == 1)
    }

    @MainActor
    @Test("A request delivered after invalidation is rejected only once")
    func rejectsLateRequestOnce() {
        let request = FakeFairPlayKeyRequest()
        var processorCount = 0
        var successCount = 0
        var failureCount = 0

        let lifecycle = makeLifecycle(
            processor: { _, _ in
                processorCount += 1
                return Data([1])
            },
            successHandler: { _, _ in successCount += 1 },
            failureHandler: { _, error in
                #expect(error is CancellationError)
                failureCount += 1
            }
        )

        lifecycle.invalidate()
        lifecycle.begin(request, isRenewal: false)
        lifecycle.begin(request, isRenewal: false)

        #expect(processorCount == 0)
        #expect(successCount == 0)
        #expect(failureCount == 1)
    }

    @MainActor
    @Test("Unsupported requests are rejected once even if AVFoundation repeats the callback")
    func rejectsDuplicateUnsupportedRequestOnce() {
        let request = FakeFairPlayKeyRequest()
        var failureCount = 0
        let lifecycle = makeLifecycle(
            processor: { _, _ in Data() },
            successHandler: { _, _ in Issue.record("Unsupported request unexpectedly succeeded.") },
            failureHandler: { _, _ in failureCount += 1 }
        )

        lifecycle.reject(request, with: PlaybackFailure(
            code: .unsupportedConfiguration,
            message: "Unsupported in this test."
        ))
        lifecycle.reject(request, with: CancellationError())

        #expect(failureCount == 1)
    }
}

@MainActor
private func makeLifecycle(
    processor: @escaping FairPlayKeyRequestLifecycle<FakeFairPlayKeyRequest>.Processor,
    successHandler: @escaping FairPlayKeyRequestLifecycle<FakeFairPlayKeyRequest>.SuccessHandler,
    failureHandler: @escaping FairPlayKeyRequestLifecycle<FakeFairPlayKeyRequest>.FailureHandler
) -> FairPlayKeyRequestLifecycle<FakeFairPlayKeyRequest> {
    FairPlayKeyRequestLifecycle(
        processor: processor,
        successHandler: successHandler,
        failureHandler: failureHandler,
        failureMapper: { $0 }
    )
}

private final class FakeFairPlayKeyRequest {}

private actor FairPlayLifecycleSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
