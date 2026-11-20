import SwiftUI

struct CompactMusicView: View {
    let nowPlaying: NowPlayingService
    let ns: Namespace.ID
    let notchGap: CGFloat
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: nowPlaying.artwork, size: ui(22), radius: ui(6))
                .matchedGeometryEffect(id: "artwork", in: ns)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchGap)
            WaveformView(color: nowPlaying.accent, isPlaying: nowPlaying.isPlaying, bars: 4)
                .frame(width: ui(18), height: ui(14))
                .matchedGeometryEffect(id: "waveform", in: ns)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ui(13))
    }
}

/// Countdown on the right. On the left: the album art when music is also
/// playing, otherwise a timer glyph.
struct CompactTimerView: View {
    let timer: TimerService
    let nowPlaying: NowPlayingService?
    let ns: Namespace.ID
    let notchGap: CGFloat
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let nowPlaying {
                    ArtworkView(image: nowPlaying.artwork, size: ui(22), radius: ui(6))
                        .matchedGeometryEffect(id: "artwork", in: ns)
                } else {
                    Symbol(name: timer.isPaused ? "pause.fill" : "timer", size: ui(14))
                        .foregroundStyle(Color.timerOrange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchGap)
            HStack(spacing: ui(4)) {
                if nowPlaying != nil {
                    Symbol(name: timer.isPaused ? "pause.fill" : "timer", size: ui(11), weight: .bold)
                }
                CountdownText(timer: timer)
                    .font(.system(size: ui(13.5), weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.timerOrange)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ui(nowPlaying == nil ? 14 : 13))
    }
}

/// Power coming in and the level, taking turns on the left; time to full on the right.
struct CompactChargingView: View {
    let battery: BatteryService
    let notchGap: CGFloat
    @Environment(\.ui) private var ui

    private static let turn: TimeInterval = 10

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: ui(3)) {
                Symbol(name: "bolt.fill", size: ui(11), weight: .bold)
                // Only ticks while this view is on screen.
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: Self.turn)) { context in
                    let index = Int((context.date.timeIntervalSinceReferenceDate / Self.turn).rounded())
                    let watts = index.isMultiple(of: 2) ? battery.inputWatts : nil
                    Text(watts.map { "\($0)W" } ?? "\(battery.level)%")
                        .animation(.easeInOut(duration: 0.3), value: watts == nil)
                }
            }
            .foregroundStyle(Color.islandGreen)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchGap)
            Group {
                if let minutes = battery.minutesToFull {
                    Text(BatteryService.formatDuration(minutes: minutes))
                        .foregroundStyle(.white)
                } else {
                    // Still estimating. A battery rather than the level, so it can't be
                    // mistaken for a time.
                    BatteryGlyph(level: battery.level, tint: .islandGreen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: ui(13), weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, ui(14))
    }
}

struct CountdownText: View {
    let timer: TimerService

    var body: some View {
        switch timer.state {
        case .running(let end) where end > .now:
            Text(timerInterval: Date.now...end, countsDown: true)
        default:
            Text(TimerService.format(timer.remaining(at: .now)))
        }
    }
}

extension Color {
    static let timerOrange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let islandGreen = Color(red: 0.2, green: 0.84, blue: 0.29)
    static let islandRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let islandSecondary = Color.white.opacity(0.55)
}
