import AVFoundation
import Foundation

enum PlaybackFailureMapping {
    static let authenticationErrorDomain = "StreamKit.Authentication"

    static func authenticationNSError(message: String) -> NSError {
        NSError(
            domain: authenticationErrorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    static func map(_ error: Error?) -> PlaybackFailure {
        guard let error else {
            return PlaybackFailure(code: .playback, message: "Playback failed.")
        }

        if let failure = error as? PlaybackFailure {
            return failure
        }

        var candidate: NSError? = error as NSError
        var visited = Set<ObjectIdentifier>()
        var isNetwork = false
        var isUnsupportedFormat = false
        var isAuthentication = false

        for _ in 0..<8 {
            guard let current = candidate,
                  visited.insert(ObjectIdentifier(current)).inserted else {
                break
            }

            if current.domain == authenticationErrorDomain {
                isAuthentication = true
            } else if current.domain == NSURLErrorDomain {
                isNetwork = true
            } else if current.domain == AVFoundationErrorDomain {
                let code = AVError.Code(rawValue: current.code)
                switch code {
                case .formatUnsupported, .failedToParse, .fileFailedToParse,
                     .fileFormatNotRecognized, .undecodableMediaData:
                    isUnsupportedFormat = true
                default:
                    break
                }
            }

            candidate = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        if isAuthentication {
            return PlaybackFailure(
                code: .authentication,
                message: "The media server rejected the supplied credentials."
            )
        }

        if isNetwork {
            return PlaybackFailure(
                code: .network,
                message: "A network error prevented media playback."
            )
        }

        if isUnsupportedFormat {
            return PlaybackFailure(
                code: .unsupportedFormat,
                message: "The media format is unsupported or invalid."
            )
        }

        return PlaybackFailure(code: .playback, message: "Playback failed.")
    }
}
