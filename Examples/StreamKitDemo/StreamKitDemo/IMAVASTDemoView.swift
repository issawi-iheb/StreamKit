
import SwiftUI
import StreamKit
import StreamKitIMA

@MainActor
struct IMAVASTDemoView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session: StreamPlayerSession?
    @State private var selectedSurface: IMAVASTPlayerSurface = .managed
    @State private var trackState = PlayerTrackState()
    @State private var controlsVisible = true
    @State private var isFullscreenPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let contentURL = URL(
        string: "https" + "://" +
        "storage.googleapis.com/gvabox/media/samples/stock.mp4"
    )!

    private let adTagURL = URL(
        string: "https" + "://" + "pubads.g.doubleclick.net/gampad/ads?" +
        "iu=/21775744923/external/single_ad_samples&" +
        "sz=640x480&cust_params=sample_ct%3Dlinear&" +
        "ciu_szs=300x250%2C728x90&gdfp_req=1&" +
        "output=vast&unviewed_position_start=1&" +
        "env=vp&correlator="
    )!

    var body: some View {
        DemoScrollContainer {
            DemoScreenHeading(
                eyebrow: "CLIENT-SIDE AD INSERTION",
                title: "Google IMA · VAST",
                subtitle: "Test Google IMA preroll advertising through the StreamKit provider adapter."
            )

            DemoPanel("Test configuration", symbol: "play.rectangle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Google's official single inline linear VAST sample.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(action: loadContent) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                "Load content and request ad",
                                systemImage: "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .demoPrimaryActionButtonStyle()
                    .disabled(isLoading)
                    .accessibilityIdentifier("imaVAST.load")
                }
            }

            DemoPanel("Player surface", symbol: "rectangle.on.rectangle") {
                Picker("Player surface", selection: $selectedSurface) {
                    ForEach(IMAVASTPlayerSurface.allCases) { surface in
                        Text(surface.title)
                            .tag(surface)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("imaVAST.surfacePicker")
                .disabled(
                    isLoading ||
                    session?.pictureInPictureState != .idle
                )

                Text(selectedSurface.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let session {
                IMAVASTPlayerSection(
                    session: session,
                    selectedSurface: $selectedSurface,
                    trackState: trackState,
                    controlsVisible: $controlsVisible,
                    isFullscreenPresented: $isFullscreenPresented,
                    onFullscreen: {
                        isFullscreenPresented = true
                    }
                )
            }

            if let errorMessage {
                DemoInlineNotice(errorMessage)
                    .accessibilityIdentifier("imaVAST.error")
            }
        }
        .navigationTitle("Google IMA · VAST")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: closeRoute) {
                    Label("Back", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("imaVAST.back")
            }
        }
        .fullScreenCover(isPresented: $isFullscreenPresented) {
            if selectedSurface == .advanced, let session {
                ZStack {
                    DemoPlayerView(
                        controller: session.controller,
                        snapshot: session.snapshot,
                        trackState: trackState,
                        isFullscreen: true,
                        onFullscreen: {
                            isFullscreenPresented = false
                        },
                        controlsVisible: $controlsVisible,
                        isActiveSurface: true
                    )

                    ClientSideAdContainerHost(
                        container: session.controller.clientSideAdContainer
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Session lifecycle

    private func closeRoute() {
        let closingSession = session
        session = nil

        dismiss()

        guard let closingSession else {
            return
        }

        Task {
            try? await closingSession.shutdown()
        }
    }

    private func loadContent() {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        trackState.prepareForNewSource()

        Task {
            defer {
                isLoading = false
            }

            let configuration = ClientSideAdConfiguration(
                request: ClientSideAdRequest(tagURL: adTagURL),
                provider: GoogleIMAAdProvider()
            )

            let source = MediaSource(
                url: contentURL,
                presentationKind: .onDemand,
                adMode: .clientSide(configuration)
            )

            do {
                if let session {
                    let load = session.load(source)
                    try await load.waitUntilReady()
                } else {
                    session = StreamPlayerSession(
                        source: source,
                        configuration: PlayerConfiguration(
                            autoplay: true
                        )
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Player surface

private enum IMAVASTPlayerSurface: String, CaseIterable, Identifiable {
    case managed
    case advanced
    case avKit

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .managed:
            "Managed"
        case .advanced:
            "Advanced"
        case .avKit:
            "AVKit"
        }
    }

    var description: String {
        switch self {
        case .managed:
            "Managed session with AVKit controls."
        case .advanced:
            "StreamPlayerController with StreamVideoView and app-owned controls."
        case .avKit:
            "Explicit AVKit presentation controller and native controls."
        }
    }
}

// MARK: - Player section

@MainActor
private struct IMAVASTPlayerSection: View {
    @ObservedObject var session: StreamPlayerSession

    @Binding var selectedSurface: IMAVASTPlayerSurface

    let trackState: PlayerTrackState

    @Binding var controlsVisible: Bool
    @Binding var isFullscreenPresented: Bool

    let onFullscreen: () -> Void

    var body: some View {
        playerSurface
            .demoPlayerSurface()
            .accessibilityIdentifier("imaVAST.playerSurface")

        PlaybackDiagnosticsPanel(
            controller: session.controller
        )

        LabeledContent(
            "Ad break",
            value: session.snapshot.adBreak == nil
                ? "Not active"
                : "Playing"
        )
        .accessibilityIdentifier("imaVAST.adState")

        LabeledContent(
            "Playback",
            value: String(
                describing: session.snapshot.phase
            ).capitalized
        )

        if let failure = session.snapshot.failure {
            DemoInlineNotice(failure.message)
                .accessibilityIdentifier("imaVAST.playbackFailure")
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        ZStack {
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

            ClientSideAdContainerHost(
                container: session.controller.clientSideAdContainer
            )
        }
    }
}
