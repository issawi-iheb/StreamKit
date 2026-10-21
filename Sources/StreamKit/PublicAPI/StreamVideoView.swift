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
        view.player = controller.renderingPlayer
        view.pictureInPictureController = pictureInPictureController
        return view
    }

    func updateUIView(
        _ uiView: PlayerLayerUIView,
        context: Context
    ) {
        uiView.player = controller.renderingPlayer
        uiView.pictureInPictureController = pictureInPictureController
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

    var player: AVPlayer? {
        get {
            playerLayer.player
        }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }

    var pictureInPictureController: StreamPictureInPictureController? {
        didSet {
            guard oldValue !== pictureInPictureController else {
                return
            }

            oldValue?.detach(from: playerLayer)
            pictureInPictureController?.attach(to: playerLayer)
        }
    }

    func detachPictureInPictureController() {
        pictureInPictureController?.detach(from: playerLayer)
        pictureInPictureController = nil
    }
    
    func prepareForRemoval() {
        let isPictureInPictureTransitioning =
            pictureInPictureController?.isPictureInPictureTransitioning == true

        // Setting this to nil invokes didSet, which unregisters the layer once.
        pictureInPictureController = nil

        // Keep the layer's player connection intact during a PiP transition.
        if !isPictureInPictureTransitioning {
            player = nil
        }
    }
}

#endif
