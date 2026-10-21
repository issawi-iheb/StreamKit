import UIKit

@MainActor
enum DemoInterfaceOrientation {
    private static var previousOrientation: UIInterfaceOrientationMask = .portrait

    static func requestFullscreenLandscape() {
        guard let scene = activeScene else { return }
        if #available(iOS 26.0, *) {
            previousOrientation = orientationMask(
                for: scene.effectiveGeometry.interfaceOrientation
            )
        } else {
            previousOrientation = orientationMask(for: scene.interfaceOrientation)
        }
        request(.landscape, in: scene)
    }

    static func restorePreviousOrientation() {
        guard let scene = activeScene else { return }
        request(previousOrientation, in: scene)
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
    }

    private static func request(
        _ orientations: UIInterfaceOrientationMask,
        in scene: UIWindowScene
    ) {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
            NSLog("StreamKit Demo orientation request failed: %@", error.localizedDescription)
        }
    }

    private static func orientationMask(
        for orientation: UIInterfaceOrientation
    ) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }
}
