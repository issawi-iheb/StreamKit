import SwiftUI
import StreamKit

@MainActor
struct ManagedPlayerDemoView: View {
    @StateObject private var session: StreamPlayerSession

    init() {
        let source = MediaSource(
            url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
            presentationKind: .onDemand
        )
        _session = StateObject(
            wrappedValue: StreamPlayerSession(source: source)
        )
    }

    var body: some View {
        StreamPlayerView(session: session)
            .navigationTitle("Managed Player")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                Task { try? await session.shutdown() }
            }
    }
}
