//
//  StreamVideoView.swift
//  StreamKit
//
//  Created by Iheb on 13/10/2026.
//

#if os(iOS)
import SwiftUI
import AVFoundation

/// Displays video from a StreamPlayerController.
///
/// Playback lifecycle remains owned by the controller.
/// Removing this view does not stop playback.
public struct StreamVideoView: View {
    private let controller: StreamPlayerController

    public init(controller: StreamPlayerController) {
        self.controller = controller
    }

    public var body: some View {
        StreamPlayerLayerView(controller: controller)
            .background(.black)
            .clipped()
    }
}

private struct StreamPlayerLayerView: UIViewRepresentable {
    let controller: StreamPlayerController

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.player = controller.renderingPlayer
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.player = controller.renderingPlayer
    }
}

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
}
#endif
