import Foundation
import StreamKit
import SwiftUI

@MainActor
struct PlaybackDiagnosticsPanel: View {
    let controller: StreamPlayerController

    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 12) {
            Label("Playback diagnostics", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            Button {
                isPresented = true
            } label: {
                Label("View", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("View playback diagnostics")
            .accessibilityIdentifier("playback-diagnostics-button")
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.045), lineWidth: 1)
        }
        .sheet(isPresented: $isPresented) {
            PlaybackDiagnosticsSheet(controller: controller)
        }
    }
}

@MainActor
private struct PlaybackDiagnosticsSheet: View {
    let controller: StreamPlayerController

    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticEvents: [PlaybackDiagnosticEvent] = []
    @State private var metricEvents: [PlaybackMetricEvent] = []

    private var entries: [Entry] {
        let diagnostics = diagnosticEvents.map(Entry.init)
        let metrics = metricEvents.map(Entry.init)
        return (diagnostics + metrics).sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id < $1.id
            }
            return $0.timestamp < $1.timestamp
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Playback events") {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No playback events yet",
                            systemImage: "waveform.path.ecg",
                            description: Text("Start playback to collect lifecycle and AVFoundation performance metrics.")
                        )
                    } else {
                        ForEach(entries.suffix(120)) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.message)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("\(entry.timestamp.formatted(date: .omitted, time: .standard)) · #\(entry.sequence) · load \(entry.loadGeneration)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section {
                    Text("History is bounded and delivery is best-effort. Sequence gaps mean some events were dropped. URLs, server addresses, credentials, and rendition identifiers are omitted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Playback Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            for await event in controller.diagnosticEvents {
                diagnosticEvents.append(event)
                if diagnosticEvents.count > 80 {
                    diagnosticEvents.removeFirst(diagnosticEvents.count - 80)
                }
            }
        }
        .task {
            for await event in controller.metrics {
                metricEvents.append(event)
                if metricEvents.count > 160 {
                    metricEvents.removeFirst(metricEvents.count - 160)
                }
            }
        }
    }
}

private struct Entry: Identifiable {
    let id: String
    let timestamp: Date
    let sequence: UInt64
    let loadGeneration: UInt64
    let message: String

    init(_ event: PlaybackDiagnosticEvent) {
        id = "diagnostic-\(event.sequence)"
        timestamp = event.timestamp
        sequence = event.sequence
        loadGeneration = event.loadGeneration
        message = Self.describe(event.kind)
    }

    init(_ event: PlaybackMetricEvent) {
        id = "metric-\(event.sequence)"
        timestamp = event.timestamp
        sequence = event.sequence
        loadGeneration = event.loadGeneration
        message = Self.describe(event.kind)
    }

    private static func describe(_ kind: PlaybackDiagnosticEvent.Kind) -> String {
        switch kind {
        case .loadStarted:
            "Load started"
        case .ready:
            "Media ready"
        case .bufferingStarted:
            "Buffering started"
        case let .bufferingEnded(duration):
            "Buffering ended after \(duration.formatted(.number.precision(.fractionLength(2)))) s"
        case let .loadCancelled(reason):
            "Load cancelled: \(reason)"
        case let .playbackFailed(code):
            "Playback failed: \(code)"
        case .ended:
            "Playback ended"
        case .audioInterruptionBegan:
            "Audio interruption began"
        case let .audioInterruptionEnded(systemAllowsResume, resumeRequested):
            "Audio interruption ended (resume allowed: \(systemAllowsResume), resume requested: \(resumeRequested))"
        case .fairPlayContentKeyResponseAccepted:
            "FairPlay content-key response accepted"
        case let .fairPlayContentKeyRequestFailed(errorCode):
            "FairPlay content-key request failed (code \(errorCode))"
        }
    }

    private static func describe(_ kind: PlaybackMetricEvent.Kind) -> String {
        switch kind {
        case let .resourceRequest(resourceType, mediaType, requestDuration, responseDuration, segmentDuration, responseBytes, statusCode, cached):
            var message = "\(resourceType) \(mediaType) request · \(requestDuration.formatted(.number.precision(.fractionLength(2)))) s"
            if let responseDuration {
                message += " · response \(responseDuration.formatted(.number.precision(.fractionLength(2)))) s"
            }
            if let segmentDuration {
                message += " · segment \(segmentDuration.formatted(.number.precision(.fractionLength(2)))) s"
            }
            if let responseBytes {
                message += " · \(responseBytes) transferred body bytes"
            }
            if let statusCode {
                message += " · HTTP \(statusCode)"
            }
            if cached { message += " · cache" }
            return message
        case let .startupCompleted(timeToLikelyToKeepUp):
            return "Startup reached likely-to-keep-up in \(timeToLikelyToKeepUp.formatted(.number.precision(.fractionLength(2)))) s"
        case .stall:
            return "AVFoundation reported a playback stall"
        case let .variantSwitch(succeeded):
            return "Variant switch \(succeeded ? "succeeded" : "failed")"
        case let .playbackSummary(summary):
            return "Session summary · average \(summary.timeWeightedAverageBitrate) bit/s · peak \(summary.timeWeightedPeakBitrate) bit/s · \(summary.stallCount) stalls · \(summary.variantSwitchCount) variant switches"
        }
    }
}
