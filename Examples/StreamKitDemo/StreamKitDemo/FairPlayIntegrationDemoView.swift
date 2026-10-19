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

    @State private var streamURL = "https://media.axprod.net/TestVectors/Hls/protected_hls_1080p_h264_singlekey/manifest.m3u8"
    @State private var certificateURL = "https://tools.axinom.com/FPScert/fairplay.cer"
    @State private var licenseURL = "https://drm-fairplay-licensing.axprod.net/AcquireLicense"
    // Axinom public evaluation token for the public protected HLS test vector.
    @State private var licenseToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjQwNjBhODY1LTg4NzgtNDI2Ny05Y2JmLTkxYWU1YmFlMWU3MiIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAieE5LNVNvRzRseGdHbGpRY2ZMOVRXQT09IiwKICAgICAgICAiaXYiOiAiTkJOYUpPcGI3MnNTYzBkSXFJejJQdz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.3Ti5rkzgw77GOXIpZWqNBUX16DXvph_NiJPCejrDStA"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Test Axinom’s protected HLS vector on a physical iPhone or iPad. Enter a fresh Axinom License Service Message token. The demo keeps it in memory for this screen only.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DemoPlayerView(
                    controller: controller,
                    snapshot: snapshot,
                    trackState: trackState,
                    isFullscreen: false,
                    onFullscreen: { isFullscreen = true }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                GroupBox("Playback status") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Phase", value: String(describing: snapshot.phase))
                        LabeledContent("Intent", value: String(describing: snapshot.intent))
                    }
                    .font(.footnote)
                }

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
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || !canLoad)
                .accessibilityIdentifier("fairPlayLoadProtectedStream")

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("fairPlayLiveError")
                }

                if diagnostics.latestMessage != nil {
                    GroupBox("FairPlay request diagnostics") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(diagnostics.logText)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

                GroupBox("What this tests") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("StreamKit creates the AVContentKeySession and SPC. This demo downloads the public evaluation certificate, posts the SPC to Axinom, sends your token in X-AxDRM-Message, and returns the CKC to AVFoundation.")
                        Text("Use a new short-lived token generated for this Axinom test vector. Tokens are not saved or logged. Do not use a management API key here.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Axinom FairPlay Test")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isFullscreen) {
            DemoPlayerView(
                controller: controller,
                snapshot: snapshot,
                trackState: trackState,
                isFullscreen: true,
                onFullscreen: { isFullscreen = false }
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
                    licenseProvider: provider,
                    diagnosticHandler: { event in
                        Task { @MainActor in
                            diagnostics.record(event.message)
                        }
                    }
                )
            )
        )
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

/// Minimal Axinom License Service adapter for this demo only.
/// It intentionally does not persist or log the runtime token or DRM payloads.
private struct AxinomFairPlayLicenseProvider: FairPlayLicenseProvider {
    let certificateURL: URL
    let licenseURL: URL
    let token: String
    let diagnostics: FairPlayDemoDiagnostics

    func applicationCertificate() async throws -> Data {
        await diagnostics.record("AVFoundation requested a content key; fetching the FPS certificate.")
        var request = URLRequest(url: certificateURL)
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), !data.isEmpty else {
                let status = (response as? HTTPURLResponse)?.statusCode
                await diagnostics.record("Certificate request failed (HTTP \(status.map(String.init) ?? "no HTTP response")).")
                throw AxinomDemoError.certificateRequestFailed
            }
            await diagnostics.record("Certificate retrieved (HTTP \(response.statusCode)); waiting for the FairPlay license response.")
            return data
        } catch is AxinomDemoError {
            throw AxinomDemoError.certificateRequestFailed
        } catch {
            let failure = error as NSError
            await diagnostics.record(
                "Certificate request failed (\(failure.domain), code \(failure.code))."
            )
            throw AxinomDemoError.certificateRequestFailed
        }
    }

    func contentIdentifier(
        for keyIdentifier: String,
        initializationData: Data?
    ) throws -> Data {
        // Axinom expects its FairPlay key URI as UTF-8 without the skd:// prefix.
        guard keyIdentifier.lowercased().hasPrefix("skd://") else {
            throw AxinomDemoError.invalidKeyIdentifier
        }
        let identifier = String(keyIdentifier.dropFirst("skd://".count))
        guard !identifier.isEmpty else { throw AxinomDemoError.invalidKeyIdentifier }
        return Data(identifier.utf8)
    }

    func contentKey(for request: FairPlayLicenseRequest) async throws -> Data {
        await diagnostics.record("Certificate is ready; posting the SPC to the FairPlay license service.")
        var urlRequest = URLRequest(url: licenseURL)
        urlRequest.timeoutInterval = 30
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.streamingContentKeyRequest
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(token, forHTTPHeaderField: "X-AxDRM-Message")

        guard let tokenHeader = urlRequest.value(forHTTPHeaderField: "X-AxDRM-Message"),
              !tokenHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await diagnostics.record("The token header is empty before sending; clear and paste the raw signed JWT again.")
            throw AxinomDemoError.licenseRequestFailed
        }
        await diagnostics.record(
            "Sending SPC with a non-empty X-AxDRM-Message header (\(tokenHeader.count) characters) to \(licenseURL.host ?? "unknown host")."
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let response = response as? HTTPURLResponse else {
                await diagnostics.record("License request returned no HTTP response.")
                throw AxinomDemoError.licenseRequestFailed
            }
            guard (200..<300).contains(response.statusCode), !data.isEmpty else {
                let serverMessage = response.value(forHTTPHeaderField: "X-AxDRM-ErrorMessage")
                let detail = serverMessage.map { ": \($0)" } ?? "."
                let responseHost = response.url?.host ?? "unknown host"
                await diagnostics.record(
                    "License request failed (HTTP \(response.statusCode), response host \(responseHost))\(detail)"
                )
                throw AxinomDemoError.licenseRequestFailed
            }
            await diagnostics.record(
                "License request succeeded (HTTP \(response.statusCode), response host \(response.url?.host ?? "unknown host")); AVFoundation is preparing playback."
            )
            return data
        } catch is AxinomDemoError {
            throw AxinomDemoError.licenseRequestFailed
        } catch {
            let failure = error as NSError
            await diagnostics.record(
                "License request network failure (\(failure.domain), code \(failure.code))."
            )
            throw AxinomDemoError.licenseRequestFailed
        }
    }
}

@Observable
@MainActor
private final class FairPlayDemoDiagnostics {
    private(set) var entries: [String] = []

    var latestMessage: String? { entries.last }
    var logText: String { entries.joined(separator: "\n") }

    func record(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        entries.append("[\(timestamp)] \(message)")
        if entries.count > 40 {
            entries.removeFirst(entries.count - 40)
        }
    }

    func copyableReport(phase: PlaybackPhase, intent: PlaybackIntent) -> String {
        [
            "StreamKit FairPlay diagnostics",
            "Playback phase: \(phase)",
            "Playback intent: \(intent)",
            "",
            logText,
            "",
            "Sensitive data omitted: token, certificate, SPC, and CKC."
        ].joined(separator: "\n")
    }
}

private enum AxinomDemoError: Error {
    case certificateRequestFailed
    case invalidKeyIdentifier
    case licenseRequestFailed
}
