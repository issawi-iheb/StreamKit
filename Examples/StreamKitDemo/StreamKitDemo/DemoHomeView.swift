//
//  DemoHomeView.swift
//  StreamKitDemo
//
//  Created by Iheb on 14/10/2026.
//

import SwiftUI

struct DemoHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    NavigationLink {
                        StandalonePlayerDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Standalone Player",
                            subtitle: "Playback controls, seeking and fullscreen",
                            symbol: "play.rectangle"
                        )
                    }

                    NavigationLink {
                        ConcurrentPlayersDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Concurrent Players",
                            subtitle: "Independent playback across multiple players",
                            symbol: "rectangle.split.2x1"
                        )
                    }

                    NavigationLink {
                        PlaylistDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Playlist",
                            subtitle: "Select and play different media sources",
                            symbol: "list.bullet.rectangle"
                        )
                    }
                }

                Section("SDK") {
                    NavigationLink {
                        PlaybackEventsDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Playback Events",
                            subtitle: "Observe playback state and failures",
                            symbol: "waveform.path"
                        )
                    }
                }
            }
            .navigationTitle("StreamKit")
        }
    }
}

private struct DemoNavigationRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
