//
//  StreamPictureInPictureDismissalBehavior.swift
//  StreamKit
//
//  Created by Iheb on 23/10/2026.
//


#if os(iOS)
import UIKit

public enum StreamPictureInPictureDismissalBehavior: Equatable, Sendable {
    /// Pause playback when PiP ends in the background.
    case pausePlayback

    /// Allow playback to continue as audio when PiP ends.
    case continuePlayback
}

@MainActor
struct PictureInPictureDismissalPolicy {
    let behavior: StreamPictureInPictureDismissalBehavior
    let isApplicationInBackground: @MainActor () -> Bool

    static let systemApplicationIsInBackground: @MainActor () -> Bool = {
        UIApplication.shared.applicationState == .background
    }

    func shouldPausePlayback(stopRequestedByHost: Bool) -> Bool {
        guard behavior == .pausePlayback,
              !stopRequestedByHost else {
            return false
        }

        return isApplicationInBackground()
    }
}
#endif
