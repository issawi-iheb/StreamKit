import StreamKit
import SwiftUI

@MainActor
struct HLSInterstitialDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var session: StreamPlayerSession?
    @State private var streamURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/interstitial-sample/mvp_interstitial_sample.m3u8"
    @State private var selectedSurface: HLSInterstitialPlayerSurface = .managed
    @State private var trackState = PlayerTrackState()
    @State private var controlsVisible = true
    @State private var isFullscreenPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var parsedStreamURL: URL? {
        guard let url = URL(string: streamURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    var body: some View {
        DemoScrollContainer {
            DemoScreenHeading(
                eyebrow: "AD PLAYBACK",
                title: "HLS Interstitials",
                subtitle: "Load an ad-enabled HLS stream and compare the managed, advanced, and AVKit player surfaces."
            )

            DemoPanel("Test stream", symbol: "play.rectangle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Apple’s sample stream is prefilled. It plays sample clips as interstitials at about 10, 25, and 55 seconds; these are test assets, not ads from a live ad network. You can replace the URL with another direct HTTPS HLS manifest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Link(
                        "Open Apple’s HLS interstitial example",
                        destination: URL(string: "https://developer.apple.com/streaming/examples/")!
                    )

                    TextField("https://example.com/interstitials/master.m3u8", text: $streamURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("HLS interstitial manifest URL")
                        .accessibilityIdentifier("hlsInterstitialURL")

                    Button(action: loadStream) {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Load and play stream", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .demoPrimaryActionButtonStyle()
                    .disabled(parsedStreamURL == nil || isLoading)
                    .accessibilityIdentifier("hlsInterstitialLoad")
                }
            }

            DemoPanel("Player surface", symbol: "rectangle.on.rectangle") {
                Picker("Player surface", selection: $selectedSurface) {
                    ForEach(HLSInterstitialPlayerSurface.allCases) { surface in
                        Text(surface.title).tag(surface)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("hlsInterstitialSurfacePicker")
                .disabled(isLoading || session?.pictureInPictureState != .idle)

                Text(selectedSurface.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let session {
                HLSInterstitialPlayerSection(
                    session: session,
                    selectedSurface: $selectedSurface,
                    trackState: trackState,
                    controlsVisible: $controlsVisible,
                    isFullscreenPresented: $isFullscreenPresented,
                    onFullscreen: { isFullscreenPresented = true }
                )
            }

            if let errorMessage {
                DemoInlineNotice(errorMessage)
                    .accessibilityIdentifier("hlsInterstitialError")
            }
        }
        .navigationTitle("HLS Interstitials")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeRoute) {
                    Label("Back", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("hlsInterstitial.back")
            }
        }
        .fullScreenCover(isPresented: $isFullscreenPresented) {
            if selectedSurface == .advanced,
               let session {
                DemoPlayerView(
                    controller: session.controller,
                    snapshot: session.snapshot,
                    trackState: trackState,
                    isFullscreen: true,
                    onFullscreen: { isFullscreenPresented = false },
                    controlsVisible: $controlsVisible,
                    isActiveSurface: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .ignoresSafeArea()
            }
        }
    }

    private func closeRoute() {
        let closingSession = session
        session = nil
        dismiss()

        guard let closingSession else { return }
        Task { try? await closingSession.shutdown() }
    }

    private func loadStream() {
        guard let url = parsedStreamURL else { return }
        isLoading = true
        errorMessage = nil
        trackState.prepareForNewSource()

        Task {
            defer { isLoading = false }
            let source = MediaSource(url: url, presentationKind: .onDemand)

            do {
                if let session {
                    let load = session.load(source)
                    try await load.waitUntilReady()
                } else {
                    session = StreamPlayerSession(
                        source: source,
                        configuration: PlayerConfiguration(autoplay: true)
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private enum HLSInterstitialPlayerSurface: String, CaseIterable, Identifiable {
    case managed
    case advanced
    case avKit

    var id: Self { self }

    var title: String {
        switch self {
        case .managed: "Managed"
        case .advanced: "Advanced"
        case .avKit: "AVKit"
        }
    }

    var description: String {
        switch self {
        case .managed: "Managed session with AVKit controls."
        case .advanced: "StreamPlayerController with StreamVideoView and app-owned controls."
        case .avKit: "Explicit AVKit presentation controller and native controls."
        }
    }
}

@MainActor
private struct HLSInterstitialPlayerSection: View {
    @ObservedObject var session: StreamPlayerSession
    @Binding var selectedSurface: HLSInterstitialPlayerSurface
    let trackState: PlayerTrackState
    @Binding var controlsVisible: Bool
    @Binding var isFullscreenPresented: Bool
    let onFullscreen: () -> Void

    var body: some View {
        playerSurface
            .demoPlayerSurface()
            .accessibilityIdentifier("hlsInterstitialPlayerSurface")

        PlaybackDiagnosticsPanel(controller: session.controller)

        LabeledContent(
            "Ad break",
            value: session.snapshot.adBreak == nil ? "Not active" : "Playing"
        )
        .accessibilityIdentifier("hlsInterstitialAdState")

        LabeledContent("Playback", value: String(describing: session.snapshot.phase).capitalized)

        if let failure = session.snapshot.failure {
            DemoInlineNotice(failure.message)
                .accessibilityIdentifier("hlsInterstitialPlaybackFailure")
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        switch selectedSurface {
        case .managed:
            StreamPlayerView(session: session)
        case .advanced:
            DemoPlayerView(
                controller: session.controller,
                snapshot: session.snapshot,
                trackState: trackState,
                isFullscreen: false,
                onFullscreen: onFullscreen,
                controlsVisible: $controlsVisible,
                isActiveSurface: !isFullscreenPresented
            )
        case .avKit:
            StreamAVPlayerView(
                controller: session.controller,
                presentationController: session.presentationController
            )
        }
    }
}
