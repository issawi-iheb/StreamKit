//
//  DemoHomeView.swift
//  StreamKitDemo
//
//  Created by Iheb on 14/10/2026.
//

import SwiftUI
import StreamKit

struct DemoHomeView: View {
    @StateObject private var presentationSession = PresentationDemoSession()
    @StateObject private var standalonePlayerSession = StandalonePlayerDemoSession()

    @State private var isStandalonePlayerPresented = false

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

                    Button {
                        isStandalonePlayerPresented = true
                    } label: {
                        DemoNavigationRow(
                            title: "Standalone Player",
                            subtitle: "Playback controls, seeking and fullscreen",
                            symbol: "play.rectangle"
                        )
                    }
                    .buttonStyle(.plain)
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
                    Button {
                        presentationSession.isPlayerPresented = true
                    } label: {
                        DemoNavigationRow(
                            title: "AVKit Player & Picture in Picture",
                            subtitle: "Switch between system AVKit and custom PiP",
                            symbol: "pip"
                        )
                    }
                    .accessibilityIdentifier("demo.presentation-avkit-pip")

                    if presentationSession.pictureInPictureState != .idle {
                        Button("Stop active PiP") {
                            presentationSession.pictureInPictureController
                                .stopPictureInPicture()
                        }
                        .accessibilityIdentifier("demo.stop-active-pip")
                    }
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
            .navigationDestination(
                isPresented: $isStandalonePlayerPresented
            ) {
                StandalonePlayerDemoView(
                    session: standalonePlayerSession
                )
            }
            .navigationDestination(
                isPresented: $presentationSession.isPlayerPresented
            ) {
                PresentationDemoView(session: presentationSession)
            }
        }
        .onAppear {
            standalonePlayerSession.requestPlayerRoute = {
                isStandalonePlayerPresented = true
            }
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
