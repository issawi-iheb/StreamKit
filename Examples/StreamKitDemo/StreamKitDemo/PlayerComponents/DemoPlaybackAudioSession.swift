import AVFAudio
import Foundation

@MainActor
enum DemoPlaybackAudioSession {
    static func configureAndActivate() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback)

        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                session.activate(options: []) { activated, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if activated {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AudioSessionActivationError.failed)
                    }
                }
            }
        } else {
            // Before iOS 27 the synchronous API can block; keep it off MainActor.
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try session.setActive(true)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

private enum AudioSessionActivationError: Error {
    case failed
}
