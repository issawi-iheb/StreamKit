import Foundation
import Observation
import StreamKit

/// Minimal Axinom License Service adapter for this demo only.
/// It intentionally does not persist or log the runtime token or DRM payloads.
struct AxinomFairPlayLicenseProvider: FairPlayLicenseProvider {
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
        await diagnostics.record(
            request.isRenewal
                ? "AVFoundation requested FairPlay key renewal; posting the renewal SPC to the license service."
                : "Certificate is ready; posting the SPC to the FairPlay license service."
        )
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
final class FairPlayDemoDiagnostics {
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

enum AxinomDemoError: Error {
    case certificateRequestFailed
    case invalidKeyIdentifier
    case licenseRequestFailed
}
