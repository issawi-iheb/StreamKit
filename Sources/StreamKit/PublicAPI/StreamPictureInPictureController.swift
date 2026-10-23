//
//  StreamPictureInPictureController.swift
//  StreamKit
//


#if os(iOS)

import AVFoundation
import AVKit
import Combine
import Foundation

/// The observable lifecycle of a Picture in Picture session.
public enum StreamPictureInPictureState: Equatable, Sendable {
    case idle
    case starting
    case active
    case stopping
}

/// Restores the host app's playback interface when PiP stops.
/// Call `completion(true)` only after the player interface is available again.
public typealias StreamPictureInPictureRestorationHandler =
    @MainActor (@escaping @Sendable (Bool) -> Void) -> Void

/// Makes an AVKit restoration completion idempotent across host callbacks.
final class StreamPictureInPictureRestorationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false
    private let completion: @Sendable (Bool) -> Void

    init(_ completion: @escaping @Sendable (Bool) -> Void) {
        self.completion = completion
    }

    func call(_ restored: Bool) {
        lock.lock()
        guard !hasCompleted else {
            lock.unlock()
            return
        }
        hasCompleted = true
        lock.unlock()

        completion(restored)
    }
}

/// Coordinates Picture in Picture for custom StreamVideoView surfaces.
///
/// Share one instance between all views rendering the same playback controller.
/// The host application owns audio-session configuration and background playback
/// capabilities. PiP must be started in response to a user action.
@MainActor
public final class StreamPictureInPictureController: NSObject, ObservableObject {

    /// Whether this device supports PiP for an AVPlayerLayer.
    public let isSupported: Bool

    /// Whether PiP can currently start for the active surface.
    @Published public private(set) var isPictureInPicturePossible = false

    /// Whether PiP is currently presenting this playback session.
    @Published public private(set) var state: StreamPictureInPictureState = .idle

    /// Whether the PiP window is active or completing its stop transition.
    public var isPictureInPictureActive: Bool {
        state == .active || state == .stopping
    }

    private var stopRequestedWhileStarting = false
    private var stopWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// True from the start request until AVKit confirms the session has stopped.
    /// The active state is included because the source controller and layer
    /// must remain retained while PiP owns playback presentation.
    var isPictureInPictureSessionInProgress: Bool {
        state != .idle
    }

    private var pictureInPictureController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?

    /// The layer currently associated with AVPictureInPictureController.
    private weak var attachedLayer: AVPlayerLayer?

    /// Strongly retains the layer while its PiP transition/session is in progress.
    private var protectedLayer: AVPlayerLayer?

    /// Weak registry of mounted surfaces, ordered by most recent attachment.
    private var registeredLayers: [WeakPlayerLayerReference] = []

    /// Invalidates queued KVO updates from replaced controllers.
    private var controllerGeneration: UInt64 = 0

    /// What happens when PiP ends while the app is in the background.
    public var dismissalBehavior: StreamPictureInPictureDismissalBehavior = .pausePlayback

    /// The player whose video surface this coordinator presents.
    private weak var playbackController: StreamPlayerController?

    /// Injectable for deterministic policy tests.
    private let isApplicationInBackground: @MainActor () -> Bool

    /// Prevents host-requested stops from triggering dismissal pausing.
    private var stopRequestedByHost = false
    
    /// Restores the host app's playback interface when PiP stops.
    public var restorationHandler: StreamPictureInPictureRestorationHandler

    public convenience init(
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler = { completion in
            completion(false)
        }
    ) {
        self.init(
            restorationHandler: restorationHandler,
            isApplicationInBackground:
                PictureInPictureDismissalPolicy.systemApplicationIsInBackground
        )
    }

    init(
        restorationHandler: @escaping StreamPictureInPictureRestorationHandler,
        isApplicationInBackground: @escaping @MainActor () -> Bool
    ) {
        isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        self.restorationHandler = restorationHandler
        self.isApplicationInBackground = isApplicationInBackground
        super.init()
    }

    /// Starts PiP. Call only in response to a user-initiated action.
    public func startPictureInPicture() {
        guard isSupported,
              isPictureInPicturePossible,
              state == .idle,
              let controller = pictureInPictureController,
              let layer = attachedLayer else {
            return
        }

        // Keep the exact source layer alive until start succeeds or fails.
        stopRequestedByHost = false
        protectedLayer = layer
        state = .starting
        controller.startPictureInPicture()
    }

    /// Requests that an active PiP session stop.
    public func stopPictureInPicture() {
        switch state {
        case .starting:
            stopRequestedByHost = true
            stopRequestedWhileStarting = true

        case .active:
            stopRequestedByHost = true
            state = .stopping
            pictureInPictureController?.stopPictureInPicture()

        case .idle, .stopping:
            break
        }
    }

    /// Requests PiP to stop and waits for AVKit to finish its lifecycle callback.
    /// Cancellation stops waiting but does not cancel the PiP stop request.
    public func stopAndWaitUntilStopped() async {
        guard state != .idle else { return }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard state != .idle else {
                    continuation.resume()
                    return
                }

                stopWaiters[waiterID] = continuation
                stopPictureInPicture()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelStopWaiter(waiterID)
            }
        }
    }

    func bind(to controller: StreamPlayerController) {
        guard playbackController !== controller,
              !isPictureInPictureSessionInProgress else {
            return
        }

        playbackController = controller
    }

    /// Registers a surface. The latest mounted surface is preferred when safe
    /// to switch controllers.
    func attach(to layer: AVPlayerLayer) {
        guard isSupported else { return }

        register(layer)

        if isPictureInPictureSessionInProgress {
            return
        }

        guard attachedLayer !== layer || pictureInPictureController == nil else {
            return
        }

        installController(for: layer)
    }

    /// Unregisters a surface. A PiP-owned controller is preserved until the
    /// transition/session ends, even if SwiftUI dismantles its source view.
    func detach(from layer: AVPlayerLayer) {
        if isPictureInPictureSessionInProgress,
           attachedLayer === layer {
            // Remove the unmounted surface from future selection,
            // but retain the active PiP source until AVKit stops.
            unregister(layer)
            return
        }

        unregister(layer)

        guard attachedLayer === layer else {
            return
        }

        clearController()
        installMostRecentAvailableLayer()
    }

    private func register(_ layer: AVPlayerLayer) {
        registeredLayers.removeAll {
            $0.layer == nil || $0.layer === layer
        }
        registeredLayers.append(WeakPlayerLayerReference(layer: layer))
    }

    private func unregister(_ layer: AVPlayerLayer) {
        registeredLayers.removeAll {
            $0.layer == nil || $0.layer === layer
        }
    }

    private func mostRecentAvailableLayer() -> AVPlayerLayer? {
        registeredLayers.removeAll { $0.layer == nil }
        return registeredLayers.reversed().compactMap(\.layer).first
    }

    private func installMostRecentAvailableLayer() {
        guard !isPictureInPictureSessionInProgress else { return }

        guard let layer = mostRecentAvailableLayer() else {
            clearController()
            return
        }

        if attachedLayer === layer, pictureInPictureController != nil {
            return
        }

        installController(for: layer)
    }

    private func installController(for layer: AVPlayerLayer) {
        // This method must never replace a controller during PiP.
        guard !isPictureInPictureSessionInProgress else { return }

        clearController()
        attachedLayer = layer

        guard let controller = AVPictureInPictureController(playerLayer: layer) else {
            let generation = controllerGeneration

            Task { @MainActor [weak self] in
                await Task.yield()

                guard let self,
                      self.controllerGeneration == generation,
                      self.pictureInPictureController == nil else {
                    return
                }

                if self.isPictureInPicturePossible {
                    self.isPictureInPicturePossible = false
                }
            }

            return
        }

        controllerGeneration &+= 1
        let generation = controllerGeneration

        pictureInPictureController = controller
        controller.delegate = self

        possibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let isPossible = change.newValue else { return }

            // Transfer only Sendable values across the actor boundary.
            Task { @MainActor [weak self] in
                guard let self,
                      self.controllerGeneration == generation else {
                    return
                }

                self.isPictureInPicturePossible = isPossible
            }
        }
    }

    private func clearController() {
        // Invalidate queued KVO tasks before releasing the old controller.
        controllerGeneration &+= 1

        possibleObservation = nil
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        attachedLayer = nil

        let generation = controllerGeneration

        Task { @MainActor [weak self] in
            await Task.yield()

            guard let self,
                  self.controllerGeneration == generation else {
                return
            }

            if self.isPictureInPicturePossible {
                self.isPictureInPicturePossible = false
            }
        }
    }

    private func finishPictureInPictureTransition() {
        state = .idle
        stopRequestedWhileStarting = false
        stopRequestedByHost = false
        protectedLayer = nil
        resumeStopWaiters()

        installMostRecentAvailableLayer()
    }

    private func cancelStopWaiter(_ id: UUID) {
        stopWaiters.removeValue(forKey: id)?.resume()
    }

    private func resumeStopWaiters() {
        let waiters = stopWaiters.values
        stopWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

extension StreamPictureInPictureController: AVPictureInPictureControllerDelegate {

    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            return
        }

        state = .active
        if stopRequestedWhileStarting {
            stopRequestedWhileStarting = false
            stopPictureInPicture()
        }
    }

    public func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            return
        }

        state = .stopping
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            return
        }

        let shouldPause = PictureInPictureDismissalPolicy(
            behavior: dismissalBehavior,
            isApplicationInBackground: isApplicationInBackground
        ).shouldPausePlayback(
            stopRequestedByHost: stopRequestedByHost
        )

        let controller = playbackController

        finishPictureInPictureTransition()

        if shouldPause, let controller {
            Task { @MainActor in
                do {
                    try await controller.pause()
                } catch is CancellationError {
                    // Playback was already cancelled.
                } catch {
                    // Playback failure is reported through the player API.
                }
            }
        }
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            return
        }

        finishPictureInPictureTransition()
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            completionHandler(false)
            return
        }

        let completionGate = StreamPictureInPictureRestorationCompletion(
            completionHandler
        )

        self.restorationHandler { restored in
            completionGate.call(restored)
        }
    }
}

@MainActor
private final class WeakPlayerLayerReference {
    weak var layer: AVPlayerLayer?

    init(layer: AVPlayerLayer) {
        self.layer = layer
    }
}

#endif
