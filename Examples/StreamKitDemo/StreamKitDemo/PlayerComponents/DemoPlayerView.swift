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
        snapshot.phase == .ready ||
        snapshot.phase == .playing ||
        snapshot.phase == .waiting
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
                    .zIndex(1)

                if controlsVisible {
                    controlsOverlay(
                        width: width,
                        height: geometry.size.height,
                        hasRoomForSeparateTrackButtons:
                            hasRoomForSeparateTrackButtons
                    )
                    .zIndex(2)
                }
            }
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
        let horizontalPadding: CGFloat = isFullscreen ? 30 : 14

        return VStack(spacing: 0) {
            // Top bar

            HStack {
                if isFullscreen {
                    Button {
                        print("EXIT FULLSCREEN TAPPED")
                        onFullscreen()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.25), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .zIndex(10)
                    .accessibilityLabel("Exit full screen")
                } else {
                    Text("STREAMKIT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.leading, 4)
                }

                Spacer()
            }

            Spacer(minLength: 8)

            // Center playback controls

            HStack(spacing: isFullscreen ? 44 : 30) {
                skipButton(
                    seconds: -10,
                    symbol: "gobackward.10",
                    label: "Skip backward 10 seconds"
                )

                Button {
                    togglePlayback()
                } label: {
                    Image(
                        systemName: isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 23, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: isPlaying ? 0 : 2)
                    .frame(
                        width: isFullscreen ? 58 : 54,
                        height: isFullscreen ? 58 : 54
                    )
                    .background(
                        .white.opacity(0.18),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                .white.opacity(0.28),
                                lineWidth: 0.8
                            )
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                skipButton(
                    seconds: 10,
                    symbol: "goforward.10",
                    label: "Skip forward 10 seconds"
                )
            }

            Spacer(minLength: 8)

            // Timeline and secondary controls

            VStack(spacing: 2) {
                Slider(
                    value: $seekPosition,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isSeeking = editing

                        guard !editing else {
                            return
                        }

                        let target = min(
                            max(seekPosition, 0),
                            duration
                        )

                        Task {
                            do {
                                try await controller.seek(to: target)
                            } catch {
                                seekPosition = snapshot.currentTime
                            }
                        }
                    }
                )
                .tint(.white)
                .frame(height: 20)
                .disabled(
                    snapshot.duration == nil ||
                    snapshot.phase == .idle ||
                    snapshot.phase == .loading
                )
                .accessibilityLabel("Playback position")

                HStack(spacing: 12) {
                    Text(
                        formatTime(
                            isSeeking
                                ? seekPosition
                                : snapshot.currentTime
                        )
                    )
                    .foregroundStyle(.white.opacity(0.95))

                    Spacer(minLength: 4)

                    trackControls(
                        hasRoomForSeparateButtons:
                            hasRoomForSeparateTrackButtons
                    )

                    if !isFullscreen {
                        Button(action: onFullscreen) {
                            Image(
                                systemName:
                                    "arrow.up.left.and.arrow.down.right"
                            )
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Enter full screen")
                    }

                    Text(
                        remainingTime(
                            current: isSeeking
                                ? seekPosition
                                : snapshot.currentTime,
                            duration: snapshot.duration
                        )
                    )
                    .foregroundStyle(.white.opacity(0.75))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, horizontalPadding)
        .padding(
            .top,
            isFullscreen
                ? (height > width ? 60 : 16)
                : 8
        )
        .padding(.bottom, isFullscreen ? 16 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Track Controls

    private func trackControls(
        hasRoomForSeparateButtons: Bool
    ) -> some View {
        HStack(spacing: hasRoomForSeparateButtons ? 8 : 2) {
            if trackState.hasAudioTracks {
                trackButton(
                    symbol: "waveform",
                    title: "Audio",
                    menu: .audio,
                    showsTitle: hasRoomForSeparateButtons
                ) {
                    openMenu(.audio)
                }
            }

            if trackState.hasSubtitleTracks {
                trackButton(
                    symbol: "captions.bubble",
                    title: "Subtitles",
                    menu: .subtitles,
                    showsTitle: hasRoomForSeparateButtons
                ) {
                    openMenu(.subtitles)
                }
            }
        }
    }

    private func trackButton(
        symbol: String,
        title: String,
        menu: TrackMenu,
        showsTitle: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))

                if showsTitle {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, showsTitle ? 10 : 8)
            .frame(minWidth: 36, minHeight: 36)
            .background {
                if activeTrackMenu == menu {
                    Capsule()
                        .fill(.white.opacity(0.16))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(!canAccessTracks || trackState.isLoading)
        .overlay(alignment: .bottomTrailing) {
            if activeTrackMenu == menu {
                trackMenu(for: menu)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -44)
                    .zIndex(4)
                    .transition(
                        .opacity.combined(
                            with: .scale(
                                scale: 0.96,
                                anchor: .bottomTrailing
                            )
                        )
                    )
            }
        }
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
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.82))
                .background(.ultraThinMaterial)
        }
        .environment(\.colorScheme, .dark)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    .white.opacity(0.12),
                    lineWidth: 0.5
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(
            color: .black.opacity(0.25),
            radius: 16,
            y: 5
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

    // MARK: Skip

    private func skipButton(
        seconds: Double,
        symbol: String,
        label: String
    ) -> some View {
        Button {
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
                .font(.system(size: 24, weight: .regular))
                .frame(width: 44, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(
            snapshot.phase == .idle ||
            snapshot.phase == .loading
        )
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
