import SwiftUI
import StreamKit

@MainActor
struct LiveDVRDemoView: View {
    @State private var controller = StreamPlayerController()
    @State private var snapshot = PlaybackSnapshot(phase: .idle, intent: .pause)
    @State private var streamURL = "https://rt-fra.rttv.com/live/rtfrance/playlist.m3u8"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This demo starts with a public RT live HLS sample. You can replace it with your own HTTPS HLS URL. The controls seek to the live edge or request playback 15, 30, or 60 seconds behind it; each stream controls how much DVR history is available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                StreamVideoView(controller: controller)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("https://example.com/live/playlist.m3u8", text: $streamURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Live HLS manifest URL")

                Button(action: loadLiveStream) {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Load live stream", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || !canLoad)
                .accessibilityIdentifier("liveDVRLoadStream")

                HStack {
                    Button {
                        Task { await performPlaybackCommand { try await controller.play() } }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(!isLoaded || snapshot.intent == .play)

                    Button {
                        Task { await performPlaybackCommand { await controller.pause() } }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .disabled(!isLoaded || snapshot.intent == .pause)
                }
                .buttonStyle(.bordered)

                GroupBox("Live DVR seeking") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Go to live edge") {
                            seekToLiveEdge(offset: 0)
                        }
                        .accessibilityIdentifier("liveDVRSeekLive")

                        HStack {
                            ForEach([15.0, 30.0, 60.0], id: \.self) { offset in
                                Button("−\(Int(offset)) sec") {
                                    seekToLiveEdge(offset: offset)
                                }
                                .accessibilityIdentifier("liveDVRSeekBehind-\(Int(offset))")
                            }
                        }

                        Text("Offsets are requests to AVFoundation relative to the live edge. The stream server determines the available DVR window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(!isLoaded || isLoading)
                }

                GroupBox("Observed timeline") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Phase", value: String(describing: snapshot.phase))
                        LabeledContent("Intent", value: String(describing: snapshot.intent))
                        LabeledContent("Playback time", value: formatTime(snapshot.currentTime))
                        LabeledContent(
                            "Latest seekable time",
                            value: snapshot.timeline.latestSeekableTime.map(formatTime) ?? "Unavailable"
                        )
                        LabeledContent(
                            "Media date",
                            value: snapshot.timeline.currentDate?.formatted(date: .abbreviated, time: .standard) ?? "Unavailable"
                        )

                        if snapshot.timeline.seekableRanges.isEmpty {
                            Text("AVFoundation has not reported a seekable range yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(snapshot.timeline.seekableRanges.enumerated()), id: \.offset) { index, range in
                                Text("Range \(index + 1): \(formatTime(range.start)) – \(formatTime(range.end))")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .font(.footnote)
                }
                .accessibilityIdentifier("liveDVRTimeline")

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Live & DVR")
        .navigationBarTitleDisplayMode(.inline)
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
        guard let url = URL(string: streamURL),
              url.scheme?.lowercased() == "https",
              url.host != nil
        else { return false }
        return true
    }

    private var isLoaded: Bool {
        ![.idle, .loading, .failed].contains(snapshot.phase)
            && snapshot.timeline.presentationKind == .live
    }

    private func loadLiveStream() {
        guard canLoad, let url = URL(string: streamURL) else { return }
        isLoading = true
        errorMessage = nil
        let handle = controller.load(
            MediaSource(url: url, presentationKind: .live)
        )
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

    private func seekToLiveEdge(offset: TimeInterval) {
        Task { await performPlaybackCommand {
            try await controller.seekToLiveEdge(offsetFromLive: offset)
        } }
    }

    private func performPlaybackCommand(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "Unavailable" }
        let wholeSeconds = Int(seconds)
        return String(format: "%02d:%02d:%02d", wholeSeconds / 3_600, (wholeSeconds / 60) % 60, wholeSeconds % 60)
    }
}
