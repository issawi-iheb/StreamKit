import StreamKit
import SwiftUI

@MainActor
struct BearerAuthenticatedPlayerDemoView: View {
    @State private var controller = StreamPlayerController()
    @State private var snapshot = PlaybackSnapshot(phase: .idle, intent: .pause)
    @State private var trackState = PlayerTrackState()

    @State private var mediaURL = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    @State private var trustedHosts = "test-streams.mux.dev"
    @State private var bearerToken = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("A public HLS sample is prefilled so you can check basic playback. To test bearer authentication, replace it with your protected HTTPS stream and enter a valid development token. List every exact host that may serve playlists, segments, keys, or redirects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("https://media.example.com/master.m3u8", text: $mediaURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("HTTPS media URL")

                TextField("media.example.com, cdn.example.com", text: $trustedHosts)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Trusted media hosts")

                SecureField("Bearer token", text: $bearerToken)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bearer token")

                Button {
                    loadProtectedStream()
                } label: {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Load HLS stream", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || !canLoad)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("bearer-auth-error")
                }

                DemoPlayerView(
                    controller: controller,
                    snapshot: snapshot,
                    trackState: trackState,
                    isFullscreen: false,
                    onFullscreen: {}
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("The token is kept only in this screen’s memory. In a product, use the provider to fetch or refresh tokens from your app’s credential store. Exact host matching prevents sending the token to unrelated HLS hosts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Bearer Authentication")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for await update in controller.snapshots {
                snapshot = update
            }
        }
        .task {
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(3_600))
                    } catch {
                        break
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    await controller.shutdown()
                }
            }
        }
    }

    private var canLoad: Bool {
        guard let url = URL(string: mediaURL),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              trustedHostSet.contains(host.lowercased())
        else { return false }

        return true
    }

    private var trustedHostSet: Set<String> {
        Set(trustedHosts
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    private func loadProtectedStream() {
        guard let url = URL(string: mediaURL),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              trustedHostSet.contains(host.lowercased())
        else {
            errorMessage = "Enter a valid HTTPS URL and trusted host list that includes the media host."
            return
        }

        isLoading = true
        errorMessage = nil

        let source: MediaSource
        if bearerToken.isEmpty {
            source = MediaSource(url: url)
        } else {
            let token = bearerToken
            let authentication = MediaBearerAuthentication(
                trustedHosts: trustedHostSet
            ) { _ in token }
            source = MediaSource(
                url: url,
                requestConfiguration: MediaRequestConfiguration(
                    bearerAuthentication: authentication
                )
            )
        }
        trackState.prepareForNewSource()
        let handle = controller.load(source)

        Task {
            defer { isLoading = false }
            do {
                try await handle.waitUntilReady()
                try await controller.play()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
