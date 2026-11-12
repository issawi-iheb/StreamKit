//
//  ClientSideAdCoordinatorTests.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import Foundation
import Testing
@testable import StreamKit

@Suite("Client-side ad coordinator")
@MainActor
struct ClientSideAdCoordinatorTests {

    @Test("Cancelling one waiter does not resolve other waiters")
    func cancellingOneWaiterDoesNotResolveOthers() async {
        let session = CoordinatorTestSession()
        let host = CoordinatorTestHost()
        let coordinator = makeCoordinator(
            host: host,
            session: session
        )

        coordinator.start()

        let firstWaiter = Task {
            await coordinator.waitForInitialDecision()
        }

        let secondWaiter = Task {
            await coordinator.waitForInitialDecision()
        }

        await Task.yield()

        firstWaiter.cancel()
        await firstWaiter.value

        #expect(firstWaiter.isCancelled)
        #expect(!coordinator.isInitialDecisionResolved)

        session.emit(.ready(hasPreRoll: false))
        await secondWaiter.value

        #expect(coordinator.isInitialDecisionResolved)

        coordinator.invalidate()
    }

    @Test("Pre-roll start resolves the initial decision but keeps the break active")
    func preRollResolvesInitialDecisionAndBlocksContent() async {
        let session = CoordinatorTestSession()
        let host = CoordinatorTestHost()
        let coordinator = makeCoordinator(
            host: host,
            session: session
        )

        coordinator.start()

        let waiter = Task {
            await coordinator.waitForInitialDecision()
        }

        await Task.yield()

        session.emit(.ready(hasPreRoll: true))
        session.emit(.breakStarted(ClientSideAdBreakInfo()))

        await waiter.value
        await waitUntil { host.pauseCount == 1 }

        #expect(coordinator.isInitialDecisionResolved)
        #expect(coordinator.activeBreak != nil)
        #expect(host.publishedBreaks.last! != nil)
        #expect(host.pauseCount == 1)
        #expect(host.resumeCount == 0)

        coordinator.invalidate()
    }

    @Test("Initial decision timeout fails open without resuming content")
    func initialDecisionTimeoutFailsOpen() async {
        let session = CoordinatorTestSession()
        let host = CoordinatorTestHost()
        let coordinator = makeCoordinator(
            host: host,
            session: session,
            timeout: 0.020
        )

        coordinator.start()
        await coordinator.waitForInitialDecision()

        #expect(coordinator.isInitialDecisionResolved)
        #expect(host.failures == [
            ClientSideAdFailure(code: .timedOut)
        ])
        #expect(host.resumeCount == 0)
        #expect(coordinator.activeBreak == nil)

        coordinator.invalidate()
    }

    @Test("Session failure resolves the initial decision")
    func sessionFailureResolvesInitialDecision() async {
        let session = CoordinatorTestSession()
        let host = CoordinatorTestHost()
        let coordinator = makeCoordinator(
            host: host,
            session: session
        )

        coordinator.start()

        let waiter = Task {
            await coordinator.waitForInitialDecision()
        }

        await Task.yield()

        let failure = ClientSideAdFailure(code: .requestFailed)
        session.emit(.failed(failure))

        await waiter.value

        #expect(coordinator.isInitialDecisionResolved)
        #expect(host.failures == [failure])
        #expect(host.resumeCount == 0)

        coordinator.invalidate()
    }

    @Test("Invalidation resolves waiters without resuming content")
    func invalidationResolvesWaitersWithoutResumingContent() async {
        let session = CoordinatorTestSession()
        let host = CoordinatorTestHost()
        let coordinator = makeCoordinator(
            host: host,
            session: session
        )

        coordinator.start()

        let waiter = Task {
            await coordinator.waitForInitialDecision()
        }

        await Task.yield()

        coordinator.invalidate()
        await waiter.value

        #expect(coordinator.isInvalidated)
        #expect(coordinator.isInitialDecisionResolved)
        #expect(session.isInvalidated)
        #expect(host.resumeCount == 0)
    }

    private func makeCoordinator(
        host: CoordinatorTestHost,
        session: CoordinatorTestSession,
        timeout: TimeInterval = 3
    ) -> ClientSideAdCoordinator {
        ClientSideAdCoordinator(
            host: host,
            session: session,
            token: ClientSideAdSessionToken(
                loadGeneration: 1,
                sessionID: UUID()
            ),
            initialDecisionTimeout: timeout
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }

            await Task.yield()
        }
    }
}

@MainActor
private final class CoordinatorTestSession: ClientSideAdSession {

    private let continuation:
        AsyncStream<ClientSideAdEvent>.Continuation

    let events: AsyncStream<ClientSideAdEvent>

    private(set) var isInvalidated = false

    init() {
        let pair = AsyncStream<ClientSideAdEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func emit(_ event: ClientSideAdEvent) {
        continuation.yield(event)
    }

    func start() {}

    func contentDidFinish() {}

    func pauseBreak() {}

    func resumeBreak() {}

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        continuation.finish()
    }
}

@MainActor
private final class CoordinatorTestHost: ClientSideAdHost {

    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var failures: [ClientSideAdFailure] = []
    private(set) var publishedBreaks: [PlaybackAdBreakState?] = []

    private var nextSequence: UInt64 = 0

    func pauseContentForAdBreak(
        token: ClientSideAdSessionToken
    ) async {
        pauseCount += 1
    }

    func resumeContentAfterAdBreak(
        token: ClientSideAdSessionToken
    ) async {
        resumeCount += 1
    }

    func publishClientSideAdBreak(
        _ adBreak: PlaybackAdBreakState?,
        token: ClientSideAdSessionToken
    ) {
        publishedBreaks.append(adBreak)
    }

    func nextClientSideAdBreakSequence(
        token: ClientSideAdSessionToken
    ) -> UInt64 {
        nextSequence += 1
        return nextSequence
    }

    func clientSideAdSessionDidFail(
        _ failure: ClientSideAdFailure,
        token: ClientSideAdSessionToken
    ) {
        failures.append(failure)
    }
}
