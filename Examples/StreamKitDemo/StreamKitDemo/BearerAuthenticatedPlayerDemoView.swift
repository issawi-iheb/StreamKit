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
    @State private var isFullscreen = false
    @State private var controlsVisible = true

    var body: some View {
        DemoScrollContainer {
                DemoScreenHeading(
                    eyebrow: "SECURE PLAYBACK",
                    title: "Bearer authentication",
                    subtitle: "Attach scoped credentials to protected HLS requests."
                )

                DemoPanel("Protected stream setup", symbol: "lock.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A public HLS sample is prefilled for basic playback. To test authentication, enter your protected HTTPS stream, token, and every exact host that may serve its playlists, segments, keys, or redirects.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("https://media.example.com/master.m3u8", text: $mediaURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("HTTPS media URL")

                        TextField("media.example.com, cdn.example.com", text: $trustedHosts)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Trusted media hosts")

                        SecureField("Bearer token", text: $bearerToken)
                            .textInputAutocapitalization(.never)
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
                        .demoPrimaryActionButtonStyle()
                        .disabled(isLoading || !canLoad)

                        if let errorMessage {
                            DemoInlineNotice(errorMessage)
                                .accessibilityIdentifier("bearer-auth-error")
                        }
                    }
                }

                DemoPlayerView(
                    controller: controller,
                    snapshot: snapshot,
                    trackState: trackState,
                    isFullscreen: false,
                    onFullscreen: {},
                    controlsVisible: $controlsVisible,
                    isActiveSurface: !isFullscreen
                )

                DemoPanel("Credential handling", symbol: "hand.raised") {
                    Text("The token stays only in this screen’s memory. In an app, use the provider to fetch or refresh credentials from your credential store. Exact host matching prevents sending the token to unrelated HLS hosts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
