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
    @StateObject private var managedPlayerSession = ManagedPlayerDemoSession()

    @State private var isStandalonePlayerPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    Button {
                        managedPlayerSession.startPlayerRoute()
                    } label: {
                        DemoNavigationRow(
                            title: "Managed AVKit Player",
                            subtitle: "VOD with standard controls and Picture in Picture",
                            symbol: "play.rectangle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(managedPlayerSession.isPreparingPlayer)
                    .accessibilityIdentifier("demo.managed-player")

                    NavigationLink {
                        LiveDVRDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Live & DVR Playback",
                            subtitle: "Inspect seekable ranges and seek behind live",
                            symbol: "dot.radiowaves.left.and.right"
                        )
                    }
                    .accessibilityIdentifier("demo.live-dvr")

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
                            subtitle: "Token flow; source also works with managed player",
                            symbol: "lock.shield"
                        )
                    }
                    .accessibilityIdentifier("demo.bearer-authenticated-hls")

                    NavigationLink {
                        FairPlayIntegrationDemoView()
                    } label: {
                        DemoNavigationRow(
                            title: "Axinom FairPlay Test",
                            subtitle: "FairPlay flow; source also works with managed player",
                            symbol: "key.horizontal"
                        )
                    }
                    .accessibilityIdentifier("demo.axinom-fairplay")
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
            .navigationDestination(
                isPresented: $managedPlayerSession.isPlayerPresented
            ) {
                ManagedPlayerDemoView(sessionOwner: managedPlayerSession)
            }
        }
        .onAppear {
            standalonePlayerSession.requestPlayerRoute = {
                isStandalonePlayerPresented = true
            }
        }
        .alert(
            "Could not prepare playback",
            isPresented: Binding(
                get: { managedPlayerSession.errorMessage != nil },
                set: { if !$0 { managedPlayerSession.clearError() } }
            )
        ) {
            Button("OK") { managedPlayerSession.clearError() }
        } message: {
            Text(managedPlayerSession.errorMessage ?? "")
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
