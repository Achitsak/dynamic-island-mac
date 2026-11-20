import SwiftUI

struct ExpandedView: View {
    let model: IslandModel
    let ns: Namespace.ID
    @Environment(\.ui) private var ui

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeader(model: model)
                .frame(height: model.geometry.notchHeight)
            if model.timer.isActive {
                TimerRow(timer: model.timer)
                    .frame(height: ui(Layout.timerRowHeight))
            }
            if model.showsPlayer {
                PlayerView(nowPlaying: model.nowPlaying, ns: ns)
                    .frame(height: ui(Layout.playerHeight))
            } else {
                NothingPlayingView(nowPlaying: model.nowPlaying)
                    .frame(height: ui(Layout.placeholderHeight))
            }
            if !model.timer.isActive {
                TimerPresetsView(timer: model.timer)
                    .frame(height: ui(Layout.presetsHeight))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Header (the band beside the notch)

private struct ExpandedHeader: View {
    let model: IslandModel
    @Environment(\.ui) private var ui

    var body: some View {
        let earWidth = max(0, (model.expandedWidth - model.geometry.notchWidth) / 2 - ui(Layout.sidePadding))
        HStack(spacing: 0) {
            leading
                .frame(width: earWidth, alignment: .leading)
            Spacer(minLength: 0)
            BatteryStatus(battery: model.battery)
                .frame(width: earWidth, alignment: .trailing)
        }
        .padding(.horizontal, ui(Layout.sidePadding))
    }

    @ViewBuilder
    private var leading: some View {
        if model.showsPlayer, let name = model.nowPlaying.appName {
            HStack(spacing: ui(6)) {
                if let icon = model.nowPlaying.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: ui(16), height: ui(16))
                }
                Text(name)
                    .font(.system(size: ui(12), weight: .medium))
                    .foregroundStyle(Color.islandSecondary)
                    .lineLimit(1)
            }
        } else {
            Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.system(size: ui(12.5), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

private struct BatteryStatus: View {
    let battery: BatteryService
    @Environment(\.ui) private var ui

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: ui(6)) {
                Text("\(battery.level)%")
                    .font(.system(size: ui(12), weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                BatteryGlyph(level: battery.level, tint: battery.tint, showsBolt: battery.isPluggedIn)
            }
        }
    }
}

// MARK: - Music player

private struct PlayerView: View {
    let nowPlaying: NowPlayingService
    let ns: Namespace.ID
    @Environment(\.ui) private var ui

    var body: some View {
        VStack(spacing: ui(8)) {
            HStack(spacing: ui(12)) {
                ArtworkView(image: nowPlaying.artwork, size: ui(54), radius: ui(12))
                    .matchedGeometryEffect(id: "artwork", in: ns)
                    .onTapGesture { nowPlaying.openSourceApp() }
                    .help("Open \(nowPlaying.appName ?? "player")")

                VStack(alignment: .leading, spacing: ui(1)) {
                    MarqueeText(
                        text: nowPlaying.track?.title ?? "",
                        size: ui(14),
                        weight: .semibold,
                        color: .white,
                        height: ui(19)
                    )
                    MarqueeText(
                        text: nowPlaying.track?.artist ?? "",
                        size: ui(12.5),
                        weight: .regular,
                        color: NSColor(white: 1, alpha: 0.55),
                        height: ui(16)
                    )
                }
                .id(nowPlaying.trackKey)
                .transition(.opacity)

                WaveformView(color: nowPlaying.accent, isPlaying: nowPlaying.isPlaying, bars: 5)
                    .frame(width: ui(22), height: ui(17))
                    .matchedGeometryEffect(id: "waveform", in: ns)
            }
            .frame(height: ui(54))
            .animation(.easeInOut(duration: 0.25), value: nowPlaying.trackKey)

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                ProgressRow(
                    elapsed: nowPlaying.elapsed(at: context.date),
                    duration: nowPlaying.track?.duration ?? 0,
                    onSeek: { nowPlaying.seek(to: $0) }
                )
            }
            .frame(height: ui(14))

            HStack(spacing: ui(26)) {
                ControlButton(symbol: "backward.fill", size: ui(15)) { nowPlaying.previous() }
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: ui(20)) {
                    nowPlaying.togglePlayPause()
                }
                ControlButton(symbol: "forward.fill", size: ui(15)) { nowPlaying.next() }
            }
            .frame(height: ui(32))
        }
        .padding(.top, ui(6))
        .padding(.horizontal, ui(Layout.sidePadding))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct NothingPlayingView: View {
    let nowPlaying: NowPlayingService
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: ui(12)) {
            ArtworkView(image: nil, size: ui(48), radius: ui(11))
            VStack(alignment: .leading, spacing: ui(2)) {
                Text("Not Playing")
                    .font(.system(size: ui(14), weight: .semibold))
                    .foregroundStyle(.white)
                Text("Play something in Music, Spotify or a browser")
                    .font(.system(size: ui(11.5)))
                    .foregroundStyle(Color.islandSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: ui(8))
            ControlButton(symbol: "play.fill", size: ui(18)) { nowPlaying.play() }
        }
        .padding(.top, ui(6))
        .padding(.horizontal, ui(Layout.sidePadding))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Timer

private struct TimerRow: View {
    let timer: TimerService
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: ui(12)) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    Circle().stroke(Color.timerOrange.opacity(0.25), lineWidth: ui(3))
                    Circle()
                        .trim(from: 0, to: timer.fractionRemaining(at: context.date))
                        .stroke(Color.timerOrange, style: StrokeStyle(lineWidth: ui(3), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "timer")
                        .font(.system(size: ui(14), weight: .semibold))
                        .foregroundStyle(Color.timerOrange)
                }
            }
            .frame(width: ui(34), height: ui(34))

            VStack(alignment: .leading, spacing: 0) {
                Text(timer.isPaused ? "Paused" : "Timer")
                    .font(.system(size: ui(11), weight: .medium))
                    .foregroundStyle(Color.islandSecondary)
                CountdownText(timer: timer)
                    .font(.system(size: ui(21), weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.timerOrange)
                    .lineLimit(1)
            }

            Spacer(minLength: ui(8))

            CircleButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", tint: .timerOrange) {
                timer.isPaused ? timer.resume() : timer.pause()
            }
            CircleButton(symbol: "xmark", tint: .white) { timer.cancel() }
        }
        .padding(.top, ui(6))
        .padding(.horizontal, ui(Layout.sidePadding))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct TimerPresetsView: View {
    let timer: TimerService
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: ui(7)) {
            Label("Timer", systemImage: "timer")
                .font(.system(size: ui(12), weight: .medium))
                .foregroundStyle(Color.islandSecondary)
            Spacer(minLength: ui(6))
            ForEach([1, 5, 10, 15, 25], id: \.self) { minutes in
                PresetChip(title: "\(minutes)m") { timer.start(seconds: TimeInterval(minutes * 60)) }
            }
        }
        .padding(.top, ui(8))
        .padding(.horizontal, ui(Layout.sidePadding))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
