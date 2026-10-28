import SwiftUI
import StreamKit

struct DemoHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var presentationSession = PresentationDemoSession()
    @StateObject private var standalonePlayerSession = StandalonePlayerDemoSession()
    @StateObject private var managedPlayerSession = ManagedPlayerDemoSession()

    @State private var isStandalonePlayerPresented = false

    private var sectionColumns: [GridItem] {
        let count = horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize ? 2 : 1
        return Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: count
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    intro
                    featuredPlayer

                    demoSection("Playback examples") {
                        NavigationLink {
                            LiveDVRDemoView()
                        } label: {
                            DemoNavigationCard(
                                title: "Live & DVR",
                                subtitle: "Play a live stream and explore its seekable window.",
                                symbol: "dot.radiowaves.left.and.right"
                            )
                        }
                        .accessibilityIdentifier("demo.live-dvr")

                        Button {
                            isStandalonePlayerPresented = true
                        } label: {
                            DemoNavigationCard(
                                title: "Custom controls",
                                subtitle: "Build playback, seeking, tracks, and fullscreen into your UI.",
                                symbol: "slider.horizontal.3"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("demo.standalone-player")

                        NavigationLink {
                            ConcurrentPlayersDemoView()
                        } label: {
                            DemoNavigationCard(
                                title: "Multiple players",
                                subtitle: "Run two independent playback sessions together.",
                                symbol: "rectangle.split.2x1"
                            )
                        }
                        .accessibilityIdentifier("demo.concurrent-players")

                        NavigationLink {
                            AudioSessionDemoView()
                        } label: {
                            DemoNavigationCard(
                                title: "Audio & background",
                                subtitle: "See interruption recovery and background playback.",
                                symbol: "waveform"
                            )
                        }
                        .accessibilityIdentifier("demo.audio-session")
                    }

                    demoSection("Presentation") {
                        Button {
                            presentationSession.isPlayerPresented = true
                        } label: {
                            DemoNavigationCard(
                                title: "AVKit & Picture in Picture",
                                subtitle: "Compare Apple's player controls with StreamKit's custom surface.",
                                symbol: "pip"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("demo.presentation-avkit-pip")
                        .gridCellColumns(horizontalSizeClass == .regular ? 2 : 1)

                        if presentationSession.pictureInPictureState != .idle {
                            Button {
                                presentationSession.pictureInPictureController
                                    .stopPictureInPicture()
                            } label: {
                                DemoNavigationCard(
                                    title: "Stop active Picture in Picture",
                                    subtitle: "Return to the presentation example.",
                                    symbol: "pip.exit"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("demo.stop-active-pip")
                            .gridCellColumns(horizontalSizeClass == .regular ? 2 : 1)
                        }
                    }

                    demoSection("Protected streams") {
                        NavigationLink {
                            BearerAuthenticatedPlayerDemoView()
                        } label: {
                            DemoNavigationCard(
                                title: "Bearer authentication",
                                subtitle: "Provide credentials for protected HLS resources.",
                                symbol: "lock.shield"
                            )
                        }
                        .accessibilityIdentifier("demo.bearer-authenticated-hls")

                        NavigationLink {
                            FairPlayIntegrationDemoView()
                        } label: {
                            DemoNavigationCard(
                                title: "FairPlay Streaming",
                                subtitle: "Connect HLS playback to a FairPlay license provider.",
                                symbol: "key.horizontal"
                            )
                        }
                        .accessibilityIdentifier("demo.axinom-fairplay")
                    }

                }
                .demoReadableContent(maximumWidth: 1000)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("StreamKit")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationDestination(
                isPresented: $isStandalonePlayerPresented
            ) {
                StandalonePlayerDemoView(session: standalonePlayerSession)
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
        .tint(DemoPalette.accent)
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAYER STUDIO")
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.tint)

            Text("Streaming,\nwithout the setup.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("Start with a ready-made player, or explore the building blocks behind it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var featuredPlayer: some View {
        Button {
            managedPlayerSession.startPlayerRoute()
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.035, green: 0.09, blue: 0.15),
                                Color(red: 0.055, green: 0.22, blue: 0.31),
                                Color(red: 0.09, green: 0.13, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                GeometryReader { geometry in
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.32))
                            .frame(width: 210, height: 210)
                            .blur(radius: 62)
                            .offset(x: geometry.size.width * 0.58, y: -45)

                        Circle()
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                            .frame(width: 210, height: 210)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.06), lineWidth: 1)
                                    .padding(18)
                            }
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.86))
                                    .frame(width: 72, height: 72)
                                    .background(.white.opacity(0.12), in: Circle())
                                    .overlay {
                                        Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                                    }
                                    .shadow(color: .cyan.opacity(0.25), radius: 24)
                            }
                            .offset(x: geometry.size.width * 0.58, y: -38)
                    }
                }
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.38)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 7, height: 7)
                        Text("THE FASTEST WAY IN")
                            .font(.caption2.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.8))

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(DemoPalette.accentBright)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)

                            Text(managedPlayerSession.playerEntryStatusLabel.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.10), in: Capsule())
                    }

                    Spacer(minLength: 32)

                    Text("Managed player")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("Starts a VOD stream immediately with AVKit controls and Picture in Picture.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .padding(22)
            }
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 360 : 264)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.02, green: 0.12, blue: 0.2).opacity(0.2), radius: 22, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(!managedPlayerSession.canOpenPlayer)
        .accessibilityHint("Opens the managed AVKit player demonstration")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("demo.managed-player")
    }

    private func demoSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }

            LazyVGrid(columns: sectionColumns, alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}

private struct DemoNavigationCard: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DemoPalette.accentBright)
                .frame(width: 42, height: 42)
                .background(DemoPalette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.15, blue: 0.21),
                            Color(red: 0.07, green: 0.11, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: DemoPalette.accentDeep.opacity(0.08), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}
