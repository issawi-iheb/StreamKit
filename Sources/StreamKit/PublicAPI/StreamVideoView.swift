//
//  StreamVideoView.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

#if os(iOS)

import SwiftUI
import AVFoundation
import AVKit
import Combine

/// Displays video from a StreamPlayerController.
///
/// Playback lifecycle remains owned by the controller.
/// Removing this view does not stop playback.
public struct StreamVideoView: View {

    private let controller: StreamPlayerController
    private let pictureInPictureController: StreamPictureInPictureController?

    public init(
        controller: StreamPlayerController,
        pictureInPictureController: StreamPictureInPictureController? = nil
    ) {
        self.controller = controller
        self.pictureInPictureController = pictureInPictureController
    }

    public var body: some View {
        StreamPlayerLayerView(
            controller: controller,
            pictureInPictureController: pictureInPictureController
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipped()
    }
}

// MARK: - Player Layer

private struct StreamPlayerLayerView: UIViewRepresentable {

    let controller: StreamPlayerController
    let pictureInPictureController: StreamPictureInPictureController?

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.pictureInPictureController = pictureInPictureController
        view.updatePlayer(controller.renderingPlayer)
        return view
    }

    func updateUIView(
        _ uiView: PlayerLayerUIView,
        context: Context
    ) {
        uiView.pictureInPictureController = pictureInPictureController
        uiView.updatePlayer(controller.renderingPlayer)
    }

    static func dismantleUIView(
        _ uiView: PlayerLayerUIView,
        coordinator: ()
    ) {
        uiView.prepareForRemoval()
    }
}

// MARK: - Player Layer View

@MainActor
private final class PlayerLayerUIView: UIView {

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private var pendingPlayer: AVPlayer?
    private var hasPendingPlayer = false
    private var pictureInPictureStateObservation: AnyCancellable?

    var player: AVPlayer? {
        get {
            playerLayer.player
        }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }

    func updatePlayer(_ player: AVPlayer?) {
        guard pictureInPictureController?.state != .starting,
              pictureInPictureController?.state != .active,
              pictureInPictureController?.state != .stopping else {
            pendingPlayer = player
            hasPendingPlayer = true
            return
        }

        pendingPlayer = nil
        hasPendingPlayer = false
        self.player = player
    }

    var pictureInPictureController: StreamPictureInPictureController? {
        didSet {
            guard oldValue !== pictureInPictureController else {
                return
            }

            oldValue?.detach(from: playerLayer)
            pictureInPictureStateObservation?.cancel()
            pictureInPictureController?.attach(to: playerLayer)
            pictureInPictureStateObservation = pictureInPictureController?.$state
                .removeDuplicates()
                .filter { $0 == .idle }
                .sink { [weak self] _ in
                    guard let self, self.hasPendingPlayer else { return }
                    let pendingPlayer = self.pendingPlayer
                    self.pendingPlayer = nil
                    self.hasPendingPlayer = false
                    self.player = pendingPlayer
                }
        }
    }

    func detachPictureInPictureController() {
        pictureInPictureController?.detach(from: playerLayer)
        pictureInPictureStateObservation?.cancel()
        pictureInPictureStateObservation = nil
        pictureInPictureController = nil
    }
    
    func prepareForRemoval() {
        let isPictureInPictureSessionInProgress =
            pictureInPictureController?.isPictureInPictureSessionInProgress == true

        // Setting this to nil invokes didSet, which unregisters the layer once.
        pictureInPictureController = nil
        pictureInPictureStateObservation?.cancel()
        pictureInPictureStateObservation = nil

        // Keep the PiP source layer and its player connection intact until AVKit
        // confirms that the active PiP session has stopped.
        if !isPictureInPictureSessionInProgress {
            player = nil
        }
    }
}

#endif
