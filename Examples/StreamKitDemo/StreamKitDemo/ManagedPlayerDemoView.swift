import SwiftUI
import StreamKit

@MainActor
struct ManagedPlayerDemoView: View {
    @ObservedObject var sessionOwner: ManagedPlayerDemoSession

    var body: some View {
        Group {
            if let session = sessionOwner.playerSession {
                StreamPlayerView(session: session)
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let session = sessionOwner.playerSession {
                PlaybackDiagnosticsPanel(controller: session.controller)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Managed Player")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    sessionOwner.isPlayerPresented = false
                } label: {
                    Label("StreamKit", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("managed.back-to-menu")
            }
        }
        .onAppear {
            sessionOwner.playerInterfaceDidAppear()
        }
        .onDisappear {
            if !sessionOwner.isPlayerPresented {
                sessionOwner.playerInterfaceDidDisappear()
                sessionOwner.playerRouteDidClose()
            }
        }
    }
}
