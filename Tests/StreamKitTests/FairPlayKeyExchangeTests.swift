import Foundation
import Testing
@testable import StreamKit

@Suite("FairPlay key exchange")
struct FairPlayKeyExchangeTests {

    @Test("Maps the key identifier, creates SPC, and returns provider CKC")
    func completesProviderExchange() async throws {
        let exchange = FairPlayKeyExchange(
            provider: FairPlayExchangeTestProvider()
        )

        let ckc = try await exchange.contentKey(
            for: "skd://asset/episode-7",
            initializationData: Data([9]),
            isRenewal: true
        ) { certificate, contentIdentifier in
            #expect(certificate == Data([1, 2]))
            #expect(contentIdentifier == Data("skd://asset/episode-7:1".utf8))
            return Data([3, 4])
        }

        #expect(ckc == Data([7, 3, 4]))
    }

    @Test("Rejects an empty content identifier before certificate or license calls")
    func rejectsEmptyContentIdentifier() async {
        let exchange = FairPlayKeyExchange(
            provider: FairPlayExchangeTestProvider(mappedContentIdentifier: Data())
        )

        await #expect(throws: PlaybackFailure.self) {
            try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data([3]) }
        }
    }

    @Test("Rejects an empty application certificate before SPC generation")
    func rejectsEmptyCertificate() async {
        let exchange = FairPlayKeyExchange(
            provider: FairPlayExchangeTestProvider(returnedCertificate: Data())
        )

        await #expect(throws: PlaybackFailure.self) {
            try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in
                Issue.record("SPC generation must not run without a certificate.")
                return Data()
            }
        }
    }

    @Test("Rejects empty SPC data before contacting the license provider")
    func rejectsEmptySPC() async {
        let exchange = FairPlayKeyExchange(
            provider: FairPlayExchangeTestProvider()
        )

        await #expect(throws: PlaybackFailure.self) {
            try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data() }
        }
    }

    @Test("Rejects an empty CKC")
    func rejectsEmptyCKC() async {
        let exchange = FairPlayKeyExchange(
            provider: FairPlayExchangeTestProvider(returnedContentKey: Data())
        )

        await #expect(throws: PlaybackFailure.self) {
            try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data([3]) }
        }
    }

    @Test("Propagates a provider license rejection to the key-session boundary")
    func propagatesProviderLicenseRejection() async {
        let exchange = FairPlayKeyExchange(
            provider: ThrowingFairPlayExchangeProvider(
                failure: .licenseRejected(statusCode: 403, body: "private entitlement details")
            )
        )

        do {
            _ = try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data([3]) }
            Issue.record("Expected the provider's license rejection to propagate.")
        } catch let error as FairPlayProviderTestError {
            #expect(error == .licenseRejected(
                statusCode: 403,
                body: "private entitlement details"
            ))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Propagates provider network failures")
    func propagatesProviderNetworkFailure() async {
        let exchange = FairPlayKeyExchange(
            provider: ThrowingFairPlayExchangeProvider(
                failure: .networkUnavailable
            )
        )

        do {
            _ = try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data([3]) }
            Issue.record("Expected the provider's network failure to propagate.")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Redacts provider details from the public playback failure")
    func redactsProviderFailure() {
        let failure = FairPlayErrorMapping.playbackFailure(
            for: FairPlayProviderTestError.licenseRejected(
                statusCode: 403,
                body: "private entitlement details and bearer secret"
            )
        )

        #expect(failure.code == .authentication)
        #expect(failure.message == "The FairPlay license request failed.")
        #expect(!failure.message.contains("private entitlement details"))
        #expect(!failure.message.contains("bearer secret"))
    }

    @Test("Stops before provider work when the task is already cancelled")
    func respectsPreexistingCancellation() async {
        let exchange = FairPlayKeyExchange(
            provider: FairPlayExchangeTestProvider()
        )
        let task = Task {
            try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data([3]) }
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Stops when cancelled during the provider license request")
    func respectsCancellationDuringProviderRequest() async {
        let started = AsyncTestSignal()
        let exchange = FairPlayKeyExchange(
            provider: BlockingFairPlayExchangeProvider(started: started)
        )
        let task = Task {
            try await exchange.contentKey(
                for: "skd://asset/episode-7",
                initializationData: nil,
                isRenewal: false
            ) { _, _ in Data([3]) }
        }

        await started.wait()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

private enum FairPlayProviderTestError: Error, Equatable {
    case licenseRejected(statusCode: Int, body: String)
    case networkUnavailable
}

private struct ThrowingFairPlayExchangeProvider: FairPlayLicenseProvider {
    let failure: FairPlayProviderTestError

    func applicationCertificate() async throws -> Data { Data([1, 2]) }

    func contentIdentifier(
        for keyIdentifier: String,
        initializationData: Data?
    ) throws -> Data {
        Data("\(keyIdentifier):\(initializationData?.count ?? 0)".utf8)
    }

    func contentKey(for request: FairPlayLicenseRequest) async throws -> Data {
        switch failure {
        case .licenseRejected:
            throw failure
        case .networkUnavailable:
            throw URLError(.notConnectedToInternet)
        }
    }
}

private actor AsyncTestSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
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

private struct BlockingFairPlayExchangeProvider: FairPlayLicenseProvider {
    let started: AsyncTestSignal

    func applicationCertificate() async throws -> Data { Data([1, 2]) }

    func contentIdentifier(
        for keyIdentifier: String,
        initializationData: Data?
    ) throws -> Data {
        Data(keyIdentifier.utf8)
    }

    func contentKey(for request: FairPlayLicenseRequest) async throws -> Data {
        await started.signal()
        try await Task.sleep(for: .seconds(60))
        return Data([7])
    }
}

private struct FairPlayExchangeTestProvider: FairPlayLicenseProvider {
    var returnedCertificate = Data([1, 2])
    var mappedContentIdentifier: Data? = nil
    var returnedContentKey = Data([7])

    func applicationCertificate() async throws -> Data {
        returnedCertificate
    }

    func contentIdentifier(
        for keyIdentifier: String,
        initializationData: Data?
    ) throws -> Data {
        mappedContentIdentifier ?? Data("\(keyIdentifier):\(initializationData?.count ?? 0)".utf8)
    }

    func contentKey(for request: FairPlayLicenseRequest) async throws -> Data {
        if request.isRenewal {
            return returnedContentKey + request.streamingContentKeyRequest
        }
        return returnedContentKey
    }
}
