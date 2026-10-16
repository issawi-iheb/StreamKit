//
//  DemoPlaceholderView.swift
//  StreamKitDemo
//
//  Created by Iheb on 14/10/2026.
//

import SwiftUI

struct PlaylistDemoView: View {
    var body: some View {
        DemoPlaceholderView(
            title: "Playlist",
            description: "Playlist selection is planned but is not implemented yet."
        )
    }
}

struct PlaybackEventsDemoView: View {
    var body: some View {
        DemoPlaceholderView(
            title: "Playback Events",
            description: "Playback event inspection is planned but is not implemented yet."
        )
    }
}

private struct DemoPlaceholderView: View {
    let title: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "hammer",
            description: Text(description)
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
