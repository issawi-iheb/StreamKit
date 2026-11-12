import Foundation
import Testing
@testable import StreamKit

@Suite("Client-side ad integration")
@MainActor
struct ClientSideAdIntegrationTests {

    @Test("Each controller gets an independent provider session and container")
    func sessionsAndContainersAreIndependentPerController() async throws {
        let provider = ControlledAdProvider()
        let firstEngine = MockPlaybackEngine()
        let secondEngine = MockPlaybackEngine()
        let firstController = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: firstEngine
        )
        let secondController = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: secondEngine
        )

        let firstLoad = firstController.load(source(using: provider, name: "first"))
        let secondLoad = secondController.load(source(using: provider, name: "second"))
        await firstEngine.waitForLoad(id: 1)
        await secondEngine.waitForLoad(id: 1)
        firstEngine.completeLoad(id: 1)
        secondEngine.completeLoad(id: 1)

        await provider.waitForSessionCount(2)
        #expect(provider.sessions.count == 2)
        #expect(provider.sessions[0] !== provider.sessions[1])

#if os(iOS)
        #expect(firstController.clientSideAdContainer !== secondController.clientSideAdContainer)
        #expect(provider.contexts[0].container !== provider.contexts[1].container)
#endif

        for session in provider.sessions {
            session.emit(.ready(hasPreRoll: false))
        }
        try await firstLoad.waitUntilReady()
        try await secondLoad.waitUntilReady()

        await firstController.shutdown()
        await secondController.shutdown()
        #expect(provider.sessions.allSatisfy { $0.isInvalidated })
    }

    @Test("Source replacement invalidates its session and user pause survives break end")
    func replacementAndUserPauseRespectAdLifecycle() async throws {
        let provider = ControlledAdProvider()
        let engine = MockPlaybackEngine()
        let controller = StreamPlayerController(
            configuration: PlayerConfiguration(autoplay: false),
            engine: engine
        )

        let firstLoad = controller.load(source(using: provider, name: "first"))
        await engine.waitForLoad(id: 1)
        engine.completeLoad(id: 1)
        await provider.waitForSessionCount(1)
        let firstSession = provider.sessions[0]
        firstSession.emit(.ready(hasPreRoll: false))
        try await firstLoad.waitUntilReady()

        let replacementLoad = controller.load(source(using: provider, name: "replacement"))
        await engine.waitForLoad(id: 2)
        engine.completeLoad(id: 2)
        await provider.waitForSessionCount(2)
        let replacementSession = provider.sessions[1]
        #expect(firstSession.isInvalidated)

        replacementSession.emit(.ready(hasPreRoll: false))
        try await replacementLoad.waitUntilReady()
        try await controller.play()

        replacementSession.emit(.breakStarted(ClientSideAdBreakInfo(cuePoint: 12)))
        await waitUntil { controller.snapshot.adBreak != nil }
        await waitUntil { engine.pauseCallCount > 0 }

        await controller.pause()
        #expect(replacementSession.pauseBreakCount == 1)

        replacementSession.emit(.breakEnded(.completed))
        await waitUntil { controller.snapshot.adBreak == nil }

        #expect(controller.snapshot.intent == .pause)
        #expect(engine.playCallCount == 1)
        #expect(!engine.isPlaying)
        #expect(!replacementSession.isInvalidated)

        await controller.shutdown()
        #expect(replacementSession.isInvalidated)
    }

    private func source(
        using provider: ControlledAdProvider,
        name: String
    ) -> MediaSource {
        MediaSource(
            url: URL(string: "https://media.example.com/\(name).m3u8")!,
            adMode: .clientSide(
                ClientSideAdConfiguration(
                    request: ClientSideAdRequest(
                        tagURL: URL(string: "https://ads.example.com/\(name).xml")!
                    ),
                    provider: provider
                )
            )
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class ControlledAdProvider: ClientSideAdProvider {
    private(set) var sessions: [ControlledAdSession] = []
    private(set) var contexts: [ClientSideAdSessionContext] = []
    private var sessionCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func makeSession(
        for request: ClientSideAdRequest,
        context: ClientSideAdSessionContext
    ) throws -> any ClientSideAdSession {
        contexts.append(context)
        let session = ControlledAdSession()
        sessions.append(session)

        let readyWaiters = sessionCountWaiters.filter { sessions.count >= $0.0 }
        sessionCountWaiters.removeAll { sessions.count >= $0.0 }
        for (_, continuation) in readyWaiters {
            continuation.resume()
        }

        return session
    }

    func waitForSessionCount(_ count: Int) async {
        guard sessions.count < count else { return }
        await withCheckedContinuation { continuation in
            sessionCountWaiters.append((count, continuation))
        }
    }
}

@MainActor
private final class ControlledAdSession: ClientSideAdSession {
    private let continuation: AsyncStream<ClientSideAdEvent>.Continuation
    let events: AsyncStream<ClientSideAdEvent>

    private(set) var isInvalidated = false
    private(set) var pauseBreakCount = 0
    private(set) var resumeBreakCount = 0
    private(set) var contentDidFinishCount = 0

    init() {
        let pair = AsyncStream<ClientSideAdEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func emit(_ event: ClientSideAdEvent) {
        continuation.yield(event)
    }

    func start() {}

    func contentDidFinish() {
        contentDidFinishCount += 1
    }

    func pauseBreak() {
        pauseBreakCount += 1
    }

    func resumeBreak() {
        resumeBreakCount += 1
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        continuation.finish()
    }
}
