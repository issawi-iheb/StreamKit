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
