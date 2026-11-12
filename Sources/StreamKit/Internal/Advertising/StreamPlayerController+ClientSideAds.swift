//
//  StreamPlayerController+ClientSideAds.swift
//  StreamKit
//
//  Created by Iheb on 10/11/2026.
//

import Foundation

// MARK: - Client-Side Ad Host

extension StreamPlayerController: ClientSideAdHost {

    // MARK: Session Ownership

    /// Returns whether an ad session still owns the current source load.
    func isCurrentClientSideAdSession(
        _ token: ClientSideAdSessionToken
    ) -> Bool {
        guard !isShutdown,
              loadGeneration == token.loadGeneration,
              let coordinator = clientSideAdCoordinator
                else {
            return false
        }

        return coordinator.token == token
    }

    // MARK: Content Playback

    func pauseContentForAdBreak(
        token: ClientSideAdSessionToken
    ) async {
        guard isCurrentClientSideAdSession(token) else {
            return
        }

        // The active client-side break makes content playback undesired.
        // Reconciliation also protects against late engine operations.
        await reconcileTransportIntent()
    }

    func resumeContentAfterAdBreak(
        token: ClientSideAdSessionToken
    ) async {
        guard isCurrentClientSideAdSession(token) else {
            return
        }

        // Playback resumes only when the latest user intent, audio state,
        // source generation and ad-break state permit it.
        await reconcileTransportIntent()
    }

    // MARK: Ad-Break State

    func publishClientSideAdBreak(
        _ adBreak: PlaybackAdBreakState?,
        token: ClientSideAdSessionToken
    ) {
        guard isCurrentClientSideAdSession(token) else {
            return
        }

#if os(iOS)
        clientSideAdContainer.updateBreakState(
            isActive: adBreak != nil
        )
#endif

        updateAdBreak(adBreak)
    }

    func nextClientSideAdBreakSequence(
        token: ClientSideAdSessionToken
    ) -> UInt64 {
        guard isCurrentClientSideAdSession(token) else {
            return clientSideAdBreakSequence
        }

        clientSideAdBreakSequence &+= 1
        return clientSideAdBreakSequence
    }

    // MARK: Failure Reporting

    func clientSideAdSessionDidFail(
        _ failure: ClientSideAdFailure,
        token: ClientSideAdSessionToken
    ) {
        guard isCurrentClientSideAdSession(token) else {
            return
        }

        publishDiagnostic(
            .clientSideAdFailed(failure.code),
            loadGeneration: token.loadGeneration
        )
    }
}

// MARK: - Client-Side Ad Lifecycle

extension StreamPlayerController {
    func setClientSideAdPictureInPictureActive(_ isActive: Bool) {
        clientSideAdCoordinator?.setPictureInPictureActive(isActive)
    }

    /// Creates and starts the client-side ad session for a source.
    ///
    /// Returns after the initial ad decision, not after the complete
    /// advertising session. Provider failures are fail-open.
    func configureClientSideAds(
        for source: MediaSource,
        generation: UInt64
    ) async throws {
        guard case let .clientSide(configuration) = source.adMode else {
            return
        }

        try Task.checkCancellation()

        guard !isShutdown,
              loadGeneration == generation else {
            throw CancellationError()
        }

        do {
#if os(iOS)
            let context = ClientSideAdSessionContext(
                container: clientSideAdContainer,
                contentPlayer: renderingPlayer
            )
#else
            let context = ClientSideAdSessionContext(
                contentPlayer: renderingPlayer
            )
#endif

            let session = try configuration.provider.makeSession(
                for: configuration.request,
                context: context
            )

            guard !isShutdown,
                  loadGeneration == generation,
                  !Task.isCancelled else {
                session.invalidate()
                throw CancellationError()
            }

            let token = ClientSideAdSessionToken(
                loadGeneration: generation,
                sessionID: UUID()
            )

            let coordinator = ClientSideAdCoordinator(
                host: self,
                session: session,
                token: token,
                initialDecisionTimeout: configuration.initialDecisionTimeout
            )

            clientSideAdCoordinator = coordinator

            // Preserve an existing user pause when the ad session starts.
            coordinator.setUserPaused(snapshot.intent != .play)

            coordinator.start()

            await coordinator.waitForInitialDecision()

            try Task.checkCancellation()

            guard isCurrentClientSideAdSession(token) else {
                throw CancellationError()
            }

        } catch is CancellationError {
            invalidateClientSideAdSession(for: generation)
            throw CancellationError()
        } catch let failure as ClientSideAdFailure {
            guard !isShutdown,
                  loadGeneration == generation else {
                throw CancellationError()
            }

            publishDiagnostic(
                .clientSideAdFailed(failure.code),
                loadGeneration: generation
            )
        } catch {
            guard !isShutdown,
                  loadGeneration == generation else {
                throw CancellationError()
            }

            // Never expose provider-specific error details.
            publishDiagnostic(
                .clientSideAdFailed(.unknown),
                loadGeneration: generation
            )
        }
    }

    /// Invalidates the ad session belonging to the specified source.
    ///
    /// Invalidation never resumes content. The source lifecycle is
    /// responsible for publishing its corresponding playback transition.
    func invalidateClientSideAdSession(
        for generation: UInt64? = nil
    ) {
        guard let coordinator = clientSideAdCoordinator else {
#if os(iOS)
            clientSideAdContainer.updateBreakState(isActive: false)
#endif
            return
        }

        if let generation,
           coordinator.token.loadGeneration != generation {
            return
        }

        // Remove ownership before invalidation so late callbacks are stale.
        clientSideAdCoordinator = nil
        coordinator.invalidate()

#if os(iOS)
        clientSideAdContainer.updateBreakState(isActive: false)
#endif
    }
}
