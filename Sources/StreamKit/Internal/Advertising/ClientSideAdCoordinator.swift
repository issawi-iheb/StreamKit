//
//  ClientSideAdCoordinator.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//
import Foundation

/// Identifies one client-side ad session owned by a specific source load.
struct ClientSideAdSessionToken: Equatable, Sendable {
    let loadGeneration: UInt64
    let sessionID: UUID
}

/// Internal boundary between the ad coordinator and the playback controller.
@MainActor
protocol ClientSideAdHost: AnyObject {
    /// Pauses content only if this session still owns the current source.
    func pauseContentForAdBreak(
        token: ClientSideAdSessionToken
    ) async

    /// Reconciles content playback only if this session still owns the source.
    func resumeContentAfterAdBreak(
        token: ClientSideAdSessionToken
    ) async

    /// Publishes the active ad break, or clears it, for the owning session.
    func publishClientSideAdBreak(
        _ adBreak: PlaybackAdBreakState?,
        token: ClientSideAdSessionToken
    )

    /// Allocates the next provider-neutral ad-break sequence number.
    func nextClientSideAdBreakSequence(
        token: ClientSideAdSessionToken
    ) -> UInt64

    /// Reports a normalized provider failure without exposing vendor details.
    func clientSideAdSessionDidFail(
        _ failure: ClientSideAdFailure,
        token: ClientSideAdSessionToken
    )
}

/// Coordinates one client-side ad session for one source generation.
@MainActor
final class ClientSideAdCoordinator {

    // MARK: - Ownership

    private weak var host: (any ClientSideAdHost)?
    private let session: any ClientSideAdSession
    let token: ClientSideAdSessionToken
    private let initialDecisionTimeout: TimeInterval
    // MARK: - Lifecycle

    private(set) var isInvalidated = false
    private(set) var isInitialDecisionResolved = false

    private var eventTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var decisionWaiters: [
        UUID: CheckedContinuation<Void, Never>
    ] = [:]
    private var hasStarted = false
    private var hasContentFinished = false

    // MARK: - Ad Break State

    private(set) var activeBreak: PlaybackAdBreakState?

    // MARK: - Pause Reasons

    private var isPausedByUser = false
    private var isAudioInterrupted = false
    private var isPictureInPictureActive = false

    private var shouldPauseAdSession: Bool {
        isPausedByUser
            || isAudioInterrupted
            || isPictureInPictureActive
    }
    private var isAdBreakPaused = false

    // MARK: - External Pause Reasons

    func setUserPaused(_ isPaused: Bool) {
        guard !isInvalidated else { return }
        isPausedByUser = isPaused
        reconcileAdSessionPauseState()
    }

    func setAudioInterrupted(_ isInterrupted: Bool) {
        guard !isInvalidated else { return }
        isAudioInterrupted = isInterrupted
        reconcileAdSessionPauseState()
    }

    func setPictureInPictureActive(_ isActive: Bool) {
        guard !isInvalidated else { return }
        isPictureInPictureActive = isActive
        reconcileAdSessionPauseState()
    }

    private func reconcileAdSessionPauseState() {
        guard activeBreak != nil else { return }

        let shouldPause = shouldPauseAdSession
        guard shouldPause != isAdBreakPaused else { return }

        isAdBreakPaused = shouldPause

        if shouldPause {
            session.pauseBreak()
        } else {
            session.resumeBreak()
        }
    }

    // MARK: - Initialization

    init(
        host: any ClientSideAdHost,
        session: any ClientSideAdSession,
        token: ClientSideAdSessionToken,
        initialDecisionTimeout: TimeInterval
    ) {
        self.host = host
        self.session = session
        self.token = token
        self.initialDecisionTimeout = initialDecisionTimeout
    }

    // MARK: - Initial Decision

    func waitForInitialDecision() async {
        guard !isInitialDecisionResolved, !isInvalidated else {
            return
        }

        let waiterID = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !isInitialDecisionResolved,
                      !isInvalidated,
                      !Task.isCancelled else {
                    continuation.resume()
                    return
                }

                decisionWaiters[waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelDecisionWaiter(waiterID)
            }
        }
    }

    private func cancelDecisionWaiter(_ id: UUID) {
        guard let continuation = decisionWaiters.removeValue(forKey: id) else {
            return
        }

        continuation.resume()
    }

    private func resolveInitialDecision() {
        guard !isInitialDecisionResolved else {
            return
        }

        isInitialDecisionResolved = true

        timeoutTask?.cancel()
        timeoutTask = nil

        let waiters = Array(decisionWaiters.values)
        decisionWaiters.removeAll()

        for continuation in waiters {
            continuation.resume()
        }
    }

    func contentDidFinish() {
        guard !isInvalidated, !hasContentFinished else {
            return
        }

        hasContentFinished = true
        session.contentDidFinish()
    }
    // MARK: - Startup

    func start() {
        guard !hasStarted, !isInvalidated else {
            return
        }

        hasStarted = true

        let events = session.events

        eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self, !self.isInvalidated else {
                    break
                }

                await self.handle(event)
            }
        }

        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let nanoseconds = UInt64(
                    min(self.initialDecisionTimeout * 1_000_000_000, Double(UInt64.max))
                )
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !self.isInvalidated,
                  !self.isInitialDecisionResolved else {
                return
            }

            self.host?.clientSideAdSessionDidFail(
                ClientSideAdFailure(code: .timedOut),
                token: self.token
            )

            self.resolveInitialDecision()
        }

        session.start()
    }

    // MARK: - Event Handling

    private func handle(_ event: ClientSideAdEvent) async {
        guard !isInvalidated else {
            return
        }

        switch event {
        case .ready(let hasPreRoll):
            if !hasPreRoll {
                resolveInitialDecision()
            }

        case .breakStarted:
            guard activeBreak == nil,
                  let host else {
                return
            }
                isAdBreakPaused = false

            let sequence = host.nextClientSideAdBreakSequence(
                token: token
            )

            let adBreak = PlaybackAdBreakState(
                deliveryMode: .clientSide,
                sequence: sequence,
                restrictsForwardSeeking: true,
                requiresPreferredPlaybackRate: true
            )

            activeBreak = adBreak

            host.publishClientSideAdBreak(
                adBreak,
                token: token
            )
            reconcileAdSessionPauseState()
            // The initial decision is now known: a pre-roll is active.
            // The controller's active-break state continues blocking content.
            resolveInitialDecision()

            await host.pauseContentForAdBreak(token: token)

        case .breakEnded:
            await finishActiveBreak()
            resolveInitialDecision()

        case .allBreaksCompleted:
            await finishActiveBreak()
            resolveInitialDecision()

        case .failed(let failure):
            host?.clientSideAdSessionDidFail(
                failure,
                token: token
            )

            await finishActiveBreak()
            resolveInitialDecision()
        }
    }

    // MARK: - Break Completion

    private func finishActiveBreak() async {
        guard activeBreak != nil else {
            return
        }

        activeBreak = nil
        isAdBreakPaused = false

        host?.publishClientSideAdBreak(
            nil,
            token: token
        )

        guard !isInvalidated else {
            return
        }

        await host?.resumeContentAfterAdBreak(token: token)
    }


    // MARK: - Invalidation

    func invalidate() {
        guard !isInvalidated else {
            return
        }

        isInvalidated = true

        eventTask?.cancel()
        eventTask = nil

        timeoutTask?.cancel()
        timeoutTask = nil

        // Invalidation must never resume content playback.
        session.invalidate()

        activeBreak = nil
        resolveInitialDecision()
        host = nil
    }
}
