//
//  StreamPictureInPictureController.swift
//  StreamKit
//


#if os(iOS)

import AVFoundation
import AVKit
import Combine
import Foundation

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
    @Published public private(set) var isPictureInPictureActive = false

    private var isPictureInPictureStarting = false

    var isPictureInPictureTransitioning: Bool {
        isPictureInPictureStarting || isPictureInPictureActive
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

    private let restorationHandler: StreamAVPlayerRestorationHandler

    public init(
        restorationHandler: @escaping StreamAVPlayerRestorationHandler = { completion in
            completion(true)
        }
    ) {
        isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        self.restorationHandler = restorationHandler
        super.init()
    }

    /// Starts PiP. Call only in response to a user-initiated action.
    public func startPictureInPicture() {
        guard isSupported,
              isPictureInPicturePossible,
              !isPictureInPictureTransitioning,
              let controller = pictureInPictureController,
              let layer = attachedLayer else {
            return
        }

        // Keep the exact source layer alive until start succeeds or fails.
        protectedLayer = layer
        isPictureInPictureStarting = true
        controller.startPictureInPicture()
    }

    /// Requests that an active PiP session stop.
    public func stopPictureInPicture() {
        guard isPictureInPictureActive else { return }
        pictureInPictureController?.stopPictureInPicture()
    }

    /// Registers a surface. The latest mounted surface is preferred when safe
    /// to switch controllers.
    func attach(to layer: AVPlayerLayer) {
        guard isSupported else { return }

        register(layer)

        if isPictureInPictureTransitioning {
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
        unregister(layer)

        guard attachedLayer === layer else {
            return
        }

        if isPictureInPictureTransitioning {
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
        guard !isPictureInPictureTransitioning else { return }

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
        guard !isPictureInPictureTransitioning else { return }

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
        isPictureInPictureStarting = false
        isPictureInPictureActive = false
        protectedLayer = nil

        installMostRecentAvailableLayer()
    }
}

extension StreamPictureInPictureController: AVPictureInPictureControllerDelegate {

    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            return
        }

        isPictureInPictureStarting = false
        isPictureInPictureActive = true
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard self.pictureInPictureController === pictureInPictureController else {
            return
        }

        finishPictureInPictureTransition()
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

        let completionGate = PictureInPictureRestorationCompletion(completionHandler)
        restorationHandler { restored in
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

/// Makes restoration completion idempotent if a host callback calls it twice.
private final class PictureInPictureRestorationCompletion: @unchecked Sendable {
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
#endif
