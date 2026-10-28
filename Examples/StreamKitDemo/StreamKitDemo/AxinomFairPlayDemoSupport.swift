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
                "Certificate request failed (error code \(failure.code))."
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
            "Sending the FairPlay license request with a non-empty authorization header."
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let response = response as? HTTPURLResponse else {
                await diagnostics.record("License request returned no HTTP response.")
                throw AxinomDemoError.licenseRequestFailed
            }
            guard (200..<300).contains(response.statusCode), !data.isEmpty else {
                await diagnostics.record(
                    "License request failed (HTTP \(response.statusCode))."
                )
                throw AxinomDemoError.licenseRequestFailed
            }
            await diagnostics.record(
                "License request succeeded (HTTP \(response.statusCode)); AVFoundation is preparing playback."
            )
            return data
        } catch is AxinomDemoError {
            throw AxinomDemoError.licenseRequestFailed
        } catch {
            let failure = error as NSError
            await diagnostics.record(
                "License request network failure (error code \(failure.code))."
            )
            throw AxinomDemoError.licenseRequestFailed
        }
    }
}

@Observable
@MainActor
final class FairPlayDemoDiagnostics {
    private(set) var entries: [String] = []
    private(set) var playbackEvents: [PlaybackDiagnosticEvent] = []
    private(set) var metricEvents: [PlaybackMetricEvent] = []

    var latestMessage: String? { entries.last }
    var logText: String {
        let providerLog = entries.joined(separator: "\n")
        let playbackLog = playbackEvents.map(Self.describe).joined(separator: "\n")
        let metricsLog = metricEvents.map(Self.describe).joined(separator: "\n")
        return [providerLog, playbackLog, metricsLog]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func record(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        entries.append("[\(timestamp)] \(message)")
        if entries.count > 40 {
            entries.removeFirst(entries.count - 40)
        }
    }

    func record(_ event: PlaybackDiagnosticEvent) {
        playbackEvents.append(event)
        if playbackEvents.count > 40 {
            playbackEvents.removeFirst(playbackEvents.count - 40)
        }
    }

    func record(_ event: PlaybackMetricEvent) {
        metricEvents.append(event)
        if metricEvents.count > 40 {
            metricEvents.removeFirst(metricEvents.count - 40)
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
            "The SDK event history is bounded; sequence gaps indicate missing events.",
            "Sensitive data omitted: media and license URLs, server addresses, authorization values, provider response text, content identifiers, certificate, SPC, CKC, and rendition identifiers."
        ].joined(separator: "\n")
    }

    private static func describe(_ event: PlaybackDiagnosticEvent) -> String {
        let time = event.timestamp.formatted(date: .omitted, time: .standard)
        let message: String
        switch event.kind {
        case .loadStarted:
            message = "Load started"
        case .ready:
            message = "Media ready"
        case .bufferingStarted:
            message = "Buffering started"
        case let .bufferingEnded(duration):
            message = "Buffering ended after \(duration.formatted(.number.precision(.fractionLength(2)))) seconds"
        case let .loadCancelled(reason):
            message = "Load cancelled (\(reason))"
        case let .playbackFailed(code):
            message = "Playback failed (\(code))"
        case .ended:
            message = "Playback ended"
        case .audioInterruptionBegan:
            message = "Audio interruption began"
        case let .audioInterruptionEnded(systemAllowsResume, resumeRequested):
            message = "Audio interruption ended (system resume allowed: \(systemAllowsResume), resume requested: \(resumeRequested))"
        case .fairPlayContentKeyResponseAccepted:
            message = "AVFoundation accepted the FairPlay content-key response"
        case let .fairPlayContentKeyRequestFailed(errorCode):
            message = "FairPlay content-key processing failed (error code \(errorCode))"
        }

        return "[\(time)] #\(event.sequence) load \(event.loadGeneration): \(message)"
    }

    private static func describe(_ event: PlaybackMetricEvent) -> String {
        let time = event.timestamp.formatted(date: .omitted, time: .standard)
        let message: String
        switch event.kind {
        case let .resourceRequest(resourceType, mediaType, requestDuration, responseDuration, segmentDuration, bytes, status, cached):
            var details = "\(resourceType) \(mediaType) request \(requestDuration.formatted(.number.precision(.fractionLength(2))))s"
            if let responseDuration {
                details += ", response \(responseDuration.formatted(.number.precision(.fractionLength(2))))s"
            }
            if let segmentDuration {
                details += ", segment \(segmentDuration.formatted(.number.precision(.fractionLength(2))))s"
            }
            if let bytes { details += ", \(bytes) bytes" }
            if let status { details += ", HTTP \(status)" }
            if cached { details += ", cache" }
            message = details
        case let .startupCompleted(timeToLikelyToKeepUp):
            message = "Startup reached likely-to-keep-up in \(timeToLikelyToKeepUp.formatted(.number.precision(.fractionLength(2))))s"
        case .stall:
            message = "AVFoundation reported a playback stall"
        case let .variantSwitch(succeeded):
            message = "Variant switch \(succeeded ? "succeeded" : "failed")"
        case let .playbackSummary(summary):
            message = "Session summary: average bitrate \(summary.timeWeightedAverageBitrate) bits/s, peak \(summary.timeWeightedPeakBitrate) bits/s, \(summary.stallCount) stalls, \(summary.variantSwitchCount) variant switches"
        }

        return "[\(time)] #\(event.sequence) load \(event.loadGeneration): \(message)"
    }
}

enum AxinomDemoError: Error {
    case certificateRequestFailed
    case invalidKeyIdentifier
    case licenseRequestFailed
}
