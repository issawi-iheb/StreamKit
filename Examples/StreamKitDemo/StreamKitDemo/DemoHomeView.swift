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
                        AudioSessionDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Audio Session & Background Playback",
                            subtitle: "Interruption recovery and background audio",
                            symbol: "waveform"
                        )
                    }
                    .accessibilityIdentifier("demo.audio-session")

                    NavigationLink {
                        StandalonePlayerDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Standalone Player",
                            subtitle: "Playback controls, seeking and fullscreen",
                            symbol: "play.rectangle"
                        )
                    }
                    .accessibilityIdentifier("demo.standalone-player")

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
                            subtitle: "Planned demo — not implemented yet.",
                            symbol: "list.bullet.rectangle"
                        )
                    }
                }

                Section("Presentation") {
                    NavigationLink {
                        PresentationDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "AVKit Player & Picture in Picture",
                            subtitle: "Switch between system AVKit and custom PiP",
                            symbol: "pip"
                        )
                    }
                    .accessibilityIdentifier("demo.presentation-avkit-pip")
                }

                Section("Protected Playback") {
                    NavigationLink {
                        BearerAuthenticatedPlayerDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Bearer-Authenticated HLS",
                            subtitle: "Play a protected stream with a host-scoped token",
                            symbol: "lock.shield"
                        )
                    }
                    .accessibilityIdentifier("demo.bearer-authenticated-hls")

                    NavigationLink {
                        FairPlayIntegrationDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Axinom FairPlay Test",
                            subtitle: "Play Axinom's protected HLS test vector",
                            symbol: "key.horizontal"
                        )
                    }
                    .accessibilityIdentifier("demo.axinom-fairplay")
                }

                Section("SDK") {
                    NavigationLink {
                        PlaybackEventsDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Playback Events",
                            subtitle: "Planned demo — not implemented yet.",
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
