import Foundation
import Observation
import StreamKit
import SwiftUI
import UIKit

/// Device-only Axinom FairPlay test using credentials entered at runtime.
@MainActor
struct FairPlayIntegrationDemoView: View {
    @State private var controller = StreamPlayerController()
    @State private var snapshot = PlaybackSnapshot(phase: .idle, intent: .pause)
    @State private var trackState = PlayerTrackState()
    @State private var isFullscreen = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var diagnostics = FairPlayDemoDiagnostics()
    @State private var didCopyDiagnostics = false
    @State private var controlsVisible = true

    @State private var streamURL = "https://media.axprod.net/TestVectors/Hls/protected_hls_1080p_h264_singlekey/manifest.m3u8"
    @State private var certificateURL = "https://tools.axinom.com/FPScert/fairplay.cer"
    @State private var licenseURL = "https://drm-fairplay-licensing.axprod.net/AcquireLicense"
    // Axinom public evaluation token for the public protected HLS test vector.
    @State private var licenseToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjQwNjBhODY1LTg4NzgtNDI2Ny05Y2JmLTkxYWU1YmFlMWU3MiIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAieE5LNVNvRzRseGdHbGpRY2ZMOVRXQT09IiwKICAgICAgICAiaXYiOiAiTkJOYUpPcGI3MnNTYzBkSXFJejJQdz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.3Ti5rkzgw77GOXIpZWqNBUX16DXvph_NiJPCejrDStA"

    var body: some View {
        DemoScrollContainer {
                DemoScreenHeading(
                    eyebrow: "DIGITAL RIGHTS",
                    title: "FairPlay Streaming",
                    subtitle: "Test Axinom’s protected HLS stream on a physical iPhone or iPad with a fresh, short-lived license token."
                )

                DemoPanel("FairPlay configuration", symbol: "key.horizontal") {
                    VStack(alignment: .leading, spacing: 12) {
                        Group {
                            TextField("Protected HLS manifest URL", text: $streamURL)
                                .keyboardType(.URL)
                                .accessibilityLabel("Protected HLS manifest URL")
                            TextField("FairPlay certificate URL", text: $certificateURL)
                                .keyboardType(.URL)
                                .accessibilityLabel("FairPlay certificate URL")
                            TextField("FairPlay license URL", text: $licenseURL)
                                .keyboardType(.URL)
                                .accessibilityLabel("FairPlay license URL")
                            SecureField("Axinom License Service Message token", text: $licenseToken)
                                .textContentType(.oneTimeCode)
                                .accessibilityLabel("Axinom license token")
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                        Button(action: loadProtectedStream) {
                            if isLoading {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Load protected stream", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .demoPrimaryActionButtonStyle()
                        .disabled(isLoading || !canLoad)
                        .accessibilityIdentifier("fairPlayLoadProtectedStream")

                        if let errorMessage {
                            DemoInlineNotice(errorMessage)
                                .accessibilityIdentifier("fairPlayLiveError")
                        }
                    }
                }

                DemoPlayerView(
                    controller: controller,
                    snapshot: snapshot,
                    trackState: trackState,
                    isFullscreen: false,
                    onFullscreen: { isFullscreen = true },
                    controlsVisible: $controlsVisible,
                    isActiveSurface: !isFullscreen
                )

                DemoPanel("Playback status", symbol: "play.circle") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Phase", value: String(describing: snapshot.phase))
                        LabeledContent("Intent", value: String(describing: snapshot.intent))
                    }
                    .font(.footnote)
                }

                if diagnostics.latestMessage != nil {
                    DemoPanel("Playback and FairPlay diagnostics", symbol: "doc.text.magnifyingglass") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(diagnostics.logText)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(12)
                                .frame(maxHeight: 220, alignment: .topLeading)
                                .accessibilityIdentifier("fairPlayRequestDiagnostics")

                            Button {
                                UIPasteboard.general.string = diagnostics.copyableReport(
                                    phase: snapshot.phase,
                                    intent: snapshot.intent
                                )
                                didCopyDiagnostics = true
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    didCopyDiagnostics = false
                                }
                            } label: {
                                Label(
                                    didCopyDiagnostics ? "Copied" : "Copy diagnostics",
                                    systemImage: didCopyDiagnostics ? "checkmark" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("fairPlayCopyDiagnostics")
                        }
                    }
                }

                DemoPanel("What this tests", symbol: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("StreamKit creates the AVContentKeySession and SPC. This demo downloads the public evaluation certificate, posts the SPC to Axinom, sends your token in X-AxDRM-Message, and returns the CKC to AVFoundation.")
                        Text("If AVFoundation requests a renewal, the diagnostics record it and the provider receives isRenewal = true. Renewal timing is controlled by the stream and license service; this public vector may not request a renewal during a short test.")
                        Text("Use a new short-lived token generated for this Axinom test vector. Tokens are not saved or logged. Do not use a management API key here.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
        .navigationTitle("Axinom FairPlay Test")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isFullscreen) {
            DemoPlayerView(
                controller: controller,
                snapshot: snapshot,
                trackState: trackState,
                isFullscreen: true,
                onFullscreen: { isFullscreen = false },
                controlsVisible: $controlsVisible,
                isActiveSurface: !isFullscreen
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
        }
        .task {
            for await update in controller.snapshots {
                snapshot = update
            }
        }
        .task {
            for await event in controller.diagnosticEvents {
                diagnostics.record(event)
            }
        }
        .task {
            for await event in controller.metrics {
                diagnostics.record(event)
            }
        }
        .task {
            await withTaskCancellationHandler {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3_600)) }
                    catch { break }
                }
            } onCancel: {
                Task { @MainActor in await controller.shutdown() }
            }
        }
    }

    private var canLoad: Bool {
        guard let media = URL(string: streamURL), media.scheme?.lowercased() == "https",
              let certificate = URL(string: certificateURL), certificate.scheme?.lowercased() == "https",
              let license = URL(string: licenseURL), license.scheme?.lowercased() == "https"
        else { return false }
        return !licenseToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadProtectedStream() {
        guard let media = URL(string: streamURL),
              let certificate = URL(string: certificateURL),
              let license = URL(string: licenseURL),
              media.scheme?.lowercased() == "https",
              certificate.scheme?.lowercased() == "https",
              license.scheme?.lowercased() == "https"
        else {
            errorMessage = "Enter valid HTTPS URLs for the manifest, certificate, and license service."
            return
        }

        let token = licenseToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Enter a fresh Axinom License Service Message token."
            return
        }

        isLoading = true
        errorMessage = nil
        diagnostics.record("Waiting for AVFoundation to request a content key.")
        let provider = AxinomFairPlayLicenseProvider(
            certificateURL: certificate,
            licenseURL: license,
            token: token,
            diagnostics: diagnostics
        )
        let source = MediaSource(
            url: media,
            requestConfiguration: MediaRequestConfiguration(
                fairPlay: FairPlayConfiguration(
                    licenseProvider: provider
                )
            )
        )
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
