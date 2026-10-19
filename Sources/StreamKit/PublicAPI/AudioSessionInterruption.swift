import Foundation

#if os(iOS)
import AVFAudio
#endif

enum AudioSessionInterruption: Sendable {
    case began
    case ended(systemAllowsResume: Bool)
}

@MainActor
protocol AudioInterruptionSource: AnyObject {
    var events: AsyncStream<AudioSessionInterruption> { get }
    func shutdown()
}

/// Owns the system notification subscription and translates it into a small,
/// platform-independent event stream for the controller.
@MainActor
final class SystemAudioInterruptionSource: AudioInterruptionSource {
    private let continuation: AsyncStream<AudioSessionInterruption>.Continuation
    let events: AsyncStream<AudioSessionInterruption>
    private var observer: NSObjectProtocol?

    init() {
        var capturedContinuation: AsyncStream<AudioSessionInterruption>.Continuation!
        events = AsyncStream { capturedContinuation = $0 }
        continuation = capturedContinuation

        #if os(iOS)
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let event = Self.event(from: notification) else { return }
            Task { @MainActor [weak self] in
                self?.continuation.yield(event)
            }
        }
        #endif
    }

    func shutdown() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        continuation.finish()
    }

    #if os(iOS)
    nonisolated private static func event(from notification: Notification) -> AudioSessionInterruption? {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return nil }

        switch type {
        case .began:
            return .began
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            return .ended(systemAllowsResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
    #endif
}
