import Foundation

/// Coordinates one active StreamKit player among controllers that share it.
///
/// Create one coordinator per playback group and pass it to each controller
/// that should pause the previously focused player when playback starts.
/// Controllers without a coordinator remain independent. This does not
/// configure or activate `AVAudioSession`; the host app owns that process-wide
/// policy.
@MainActor
public final class AudioPlaybackFocusCoordinator {

    private weak var focusedController: StreamPlayerController?

    public init() {}

    func requestFocus(for controller: StreamPlayerController) -> StreamPlayerController? {
        let previousController = focusedController
        focusedController = controller
        return previousController === controller ? nil : previousController
    }

    func ownsFocus(_ controller: StreamPlayerController) -> Bool {
        focusedController === controller
    }

    func releaseFocus(for controller: StreamPlayerController) {
        guard focusedController === controller else { return }
        focusedController = nil
    }
}
