#if os(iOS)

import SwiftUI

/// Presents a managed playback session with AVKit's standard controls.
///
/// The session loads its initial source automatically. Keep the
/// `StreamPlayerSession` in an owner above this view if Picture in Picture
/// should survive navigation away from the player.
@MainActor
public struct StreamPlayerView: View {
    @StateObject private var session: StreamPlayerSession
    private let shutsDownSessionOnDisappear: Bool

    /// Creates and manages a session for a single player screen.
    ///
    /// The view shuts its session down when removed, after any active PiP ends.
    /// Pass a retained `StreamPlayerSession` instead when the host needs to
    /// manage navigation restoration or keep the session across routes.
    public init(
        source: MediaSource,
        configuration: PlayerConfiguration = .init(),
        automaticallyStartsPictureInPictureWhenLeavingApp: Bool = false,
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler = { completion in
            completion(false)
        }
    ) {
        _session = StateObject(
            wrappedValue: StreamPlayerSession(
                source: source,
                configuration: configuration,
                automaticallyStartsPictureInPictureWhenLeavingApp:
                    automaticallyStartsPictureInPictureWhenLeavingApp,
                restorationHandler: restorationHandler
            )
        )
        self.shutsDownSessionOnDisappear = true
    }

    /// Presents a session retained by the host for cross-route playback or PiP.
    public init(session: StreamPlayerSession) {
        _session = StateObject(wrappedValue: session)
        self.shutsDownSessionOnDisappear = false
    }

    public var body: some View {
        StreamAVPlayerView(
            controller: session.controller,
            presentationController: session.presentationController,
            automaticallyStartsPictureInPictureWhenLeavingApp:
                session.automaticallyStartsPictureInPictureWhenLeavingApp
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            guard shutsDownSessionOnDisappear else { return }
            Task { try? await session.shutdown() }
        }
    }
}

#endif
