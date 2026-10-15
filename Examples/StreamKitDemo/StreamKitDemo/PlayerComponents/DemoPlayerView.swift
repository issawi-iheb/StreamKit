//
//  DemoPlayerView.swift
//  StreamKitDemo
//
//  Created by Iheb on 14/10/2026.
//

import Foundation
import StreamKit
import SwiftUI

@MainActor
struct DemoPlayerView: View {
    let controller: StreamPlayerController
    let snapshot: PlaybackSnapshot
    let trackState: PlayerTrackState
    let isFullscreen: Bool
    let onFullscreen: () -> Void

    @State private var controlsVisible = true
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    private enum TrackMenu: Equatable {
        case audio
        case subtitles
    }

    @State private var activeTrackMenu: TrackMenu?

    private var duration: Double {
        max(snapshot.duration ?? 0, 1)
    }

    private var isPlaying: Bool {
        snapshot.phase == .playing ||
        snapshot.phase == .waiting
    }

    private var canAccessTracks: Bool {
        switch snapshot.phase {
        case .ready, .playing, .paused, .waiting:
            true
        case .idle, .loading, .ended, .failed:
            false
        }
    }

    var body: some View {
        Group {
            if isFullscreen {
                playerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                playerContent
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: snapshot.currentTime) { _, newTime in
            guard !isSeeking else {
                return
            }

            seekPosition = newTime
        }
        .onChange(of: snapshot.duration) { _, newDuration in
            guard !isSeeking, let newDuration else {
                return
            }

            seekPosition = min(snapshot.currentTime, newDuration)
        }
        .task(id: canAccessTracks) {
            guard canAccessTracks else {
                return
            }

            await trackState.load(using: controller)
        }
        .task(id: controlsVisible && isPlaying && activeTrackMenu == nil) {
            guard controlsVisible,
                  isPlaying,
                  activeTrackMenu == nil else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  isPlaying,
                  activeTrackMenu == nil else {
                return
            }

            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
    }

    // MARK: Player Content

    private var playerContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            // Base the layout on actual player width.
            let hasRoomForSeparateTrackButtons = width >= 560

            ZStack {
                Color.black

                StreamVideoView(controller: controller)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )

                if snapshot.phase == .waiting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                        .accessibilityLabel("Buffering")
                }

                if controlsVisible {
                    LinearGradient(
                        stops: [
                            .init(
                                color: .black.opacity(0.48),
                                location: 0
                            ),
                            .init(
                                color: .clear,
                                location: 0.30
                            ),
                            .init(
                                color: .clear,
                                location: 0.55
                            ),
                            .init(
                                color: .black.opacity(0.68),
                                location: 1
                            )
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                // Tap the video to show or hide playback controls.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if controlsVisible {
                                if activeTrackMenu != nil {
                                    activeTrackMenu = nil
                                } else {
                                    controlsVisible = false
                                }
                            } else {
                                controlsVisible = true
                            }
                        }
                    }
                    .allowsHitTesting(!controlsVisible)
                    .zIndex(1)

                if controlsVisible {
                    controlsOverlay(
                        width: width,
                        height: geometry.size.height,
                        hasRoomForSeparateTrackButtons:
                            hasRoomForSeparateTrackButtons
                    )
                    .zIndex(2)

                    if let activeTrackMenu {
                        VStack {
                            Spacer()

                            HStack {
                                Spacer()

                                trackMenu(for: activeTrackMenu)
                                    .frame(width: 240)
                                    .padding(.trailing, isFullscreen ? 30 : 56)
                                    .padding(.bottom, isFullscreen ? 100 : 96)
                            }
                        }
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .zIndex(3)
                    }
                }            }
            .clipped()
        }
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Playback Controls

    private func controlsOverlay(
        width: CGFloat,
        height: CGFloat,
        hasRoomForSeparateTrackButtons: Bool
    ) -> some View {
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 8)

            centerControls

            Spacer(minLength: 8)

            bottomBar
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, isFullscreen ? 30 : 14)
        .padding(
            .top,
            isFullscreen
                ? (height > width ? 60 : 16)
                : 8
        )
        .padding(.bottom, isFullscreen ? 16 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Top Bar

    @ViewBuilder
    private var topBar: some View {
        if isFullscreen {
            HStack(spacing: 12) {
                glassCircleButton(
                    symbol: "xmark",
                    label: "Exit full screen"
                ) {
                    onFullscreen()
                }

                Spacer()
            }
        } else {
            HStack {
                Text("STREAMKIT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.leading, 4)

                Spacer()
            }
        }
    }

    private func glassCircleButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .playerGlass(Circle())
        .accessibilityLabel(label)
    }

    // MARK: Center Controls

    private var centerControls: some View {
        let playSize: CGFloat = isFullscreen ? 92 : 56

        return HStack(spacing: isFullscreen ? 68 : 28) {
            skipButton(
                seconds: -10,
                symbol: "gobackward.10",
                label: "Skip backward 10 seconds"
            )

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(
                        .system(
                            size: isFullscreen ? 38 : 24,
                            weight: .semibold
                        )
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: isPlaying ? 0 : 3)
                    .frame(width: playSize, height: playSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .playerGlass(Circle())
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            skipButton(
                seconds: 10,
                symbol: "goforward.10",
                label: "Skip forward 10 seconds"
            )
        }
    }

    private func skipButton(
        seconds: Double,
        symbol: String,
        label: String
    ) -> some View {
        let size: CGFloat = isFullscreen ? 64 : 44

        return Button {
            let target = min(
                max(snapshot.currentTime + seconds, 0),
                snapshot.duration ?? .greatestFiniteMagnitude
            )

            Task {
                do {
                    try await controller.seek(to: target)
                } catch {
                    // The current snapshot remains authoritative.
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(
                    .system(
                        size: isFullscreen ? 28 : 20,
                        weight: .regular
                    )
                )
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .playerGlass(Circle())
        .accessibilityLabel(label)
        .disabled(
            snapshot.phase == .idle ||
            snapshot.phase == .loading
        )
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        let displayedTime = isSeeking ? seekPosition : snapshot.currentTime

        return VStack(alignment: .leading, spacing: isFullscreen ? 12 : 6) {
            // Title + track buttons on the same row
            HStack(alignment: .bottom, spacing: 12) {
                Spacer(minLength: 12)

                trackControls

                if !isFullscreen {
                    Button(action: onFullscreen) {
                        Image(
                            systemName: "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enter full screen")
                }
            }

            // Elapsed — progress bar — remaining
            HStack(spacing: 12) {
                Text(formatTime(displayedTime))
                    .foregroundStyle(.white.opacity(0.7))

                PlayerProgressBar(
                    value: $seekPosition,
                    range: 0...duration,
                    onEditingChanged: handleSeekEditing
                )
                .disabled(
                    snapshot.duration == nil ||
                    snapshot.phase == .idle ||
                    snapshot.phase == .loading
                )
                .accessibilityLabel("Playback position")

                Text(
                    remainingTime(
                        current: displayedTime,
                        duration: snapshot.duration
                    )
                )
                .foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
    }

    private func handleSeekEditing(_ editing: Bool) {
        isSeeking = editing

        guard !editing else {
            return
        }

        let target = min(max(seekPosition, 0), duration)

        Task {
            do {
                try await controller.seek(to: target)
            } catch {
                seekPosition = snapshot.currentTime
            }
        }
    }

    // MARK: Track Controls

    @ViewBuilder
    private var trackControls: some View {
        if trackState.hasAudioTracks || trackState.hasSubtitleTracks {
            HStack(spacing: isFullscreen ? 8 : 2) {
                if trackState.hasAudioTracks {
                    trackButton(
                        symbol: "waveform",
                        title: "Audio",
                        menu: .audio
                    ) {
                        openMenu(.audio)
                    }
                }

                if trackState.hasSubtitleTracks {
                    trackButton(
                        symbol: "captions.bubble",
                        title: "Subtitles",
                        menu: .subtitles
                    ) {
                        openMenu(.subtitles)
                    }
                }
            }
            .padding(.horizontal, 6)
            .playerGlass(Capsule(), interactive: false)
        }
    }

    private func trackButton(
        symbol: String,
        title: String,
        menu: TrackMenu,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    if activeTrackMenu == menu {
                        Circle().fill(.white.opacity(0.18))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(!canAccessTracks || trackState.isLoading)
    }

    private func openMenu(_ menu: TrackMenu) {
        guard canAccessTracks else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            controlsVisible = true
            activeTrackMenu =
                activeTrackMenu == menu ? nil : menu
        }
    }

    // MARK: Track Menus

    private func trackMenu(
        for menu: TrackMenu
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Menu title

            HStack {
                Text(menuTitle(menu))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                Button {
                    closeMenu()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(menuTitle(menu)) menu")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 0.5)

            if trackState.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)

                    Text("Loading…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        switch menu {
                        case .audio:
                            ForEach(trackState.audioTracks) { track in
                                trackRow(
                                    title: track.name,
                                    isSelected:
                                        trackState.selectedAudioID == track.id
                                ) {
                                    await trackState.selectAudio(
                                        track.id,
                                        using: controller
                                    )
                                }
                            }

                        case .subtitles:
                            trackRow(
                                title: "Off",
                                isSelected:
                                    trackState.selectedSubtitleID == nil
                            ) {
                                await trackState.selectSubtitle(
                                    nil,
                                    using: controller
                                )
                            }

                            ForEach(trackState.subtitleTracks) { track in
                                trackRow(
                                    title: track.name,
                                    isSelected:
                                        trackState.selectedSubtitleID == track.id
                                ) {
                                    await trackState.selectSubtitle(
                                        track.id,
                                        using: controller
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .scrollIndicators(.visible)
            }

            if let message = trackState.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(10)
            }
        }
        .frame(width: 240)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .playerGlass(
            RoundedRectangle(cornerRadius: 22),
            interactive: false
        )
    }

    private func menuTitle(
        _ menu: TrackMenu
    ) -> String {
        switch menu {
        case .audio:
            return "Audio"
        case .subtitles:
            return "Subtitles"
        }
    }

    private func trackRow(
        title: String,
        isSelected: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(0.10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(trackState.isLoading)
    }

    private func closeMenu() {
        withAnimation(.easeInOut(duration: 0.18)) {
            activeTrackMenu = nil
        }
    }

    // MARK: Playback

    private func togglePlayback() {
        Task {
            do {
                if isPlaying {
                    await controller.pause()
                } else {
                    try await controller.play()
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible = true
                }
            } catch {
                // Playback errors are reported by the controller.
            }
        }
    }

    // MARK: Time Formatting

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func remainingTime(
        current: TimeInterval,
        duration: TimeInterval?
    ) -> String {
        guard let duration, duration.isFinite, duration > 0 else {
            return "–:––"
        }

        let remaining = max(duration - current, 0)
        return "−\(formatTime(remaining))"
    }
}

// MARK: - Liquid Glass helper

extension View {
    /// Liquid Glass on iOS 26+, ultra-thin material before that.
    @ViewBuilder
    func playerGlass<S: Shape>(
        _ shape: S,
        interactive: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: shape
            )
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - Progress bar (thick capsule, no thumb)

struct PlayerProgressBar: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.28))

                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: geometry.size.width * fraction)
            }
            .frame(height: isDragging ? 12 : 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }

                        let x = min(
                            max(drag.location.x / geometry.size.width, 0),
                            1
                        )
                        value = range.lowerBound + x * span
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 24)
        .opacity(isEnabled ? 1 : 0.5)
    }
}
