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
            description: "Select a media source and load it into the player."
        )
    }
}

struct PlaybackEventsDemoView: View {
    var body: some View {
        DemoPlaceholderView(
            title: "Playback Events",
            description: "Inspect playback state transitions and failures."
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
