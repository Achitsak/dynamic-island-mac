import SwiftUI

struct CompactMusicView: View {
    let nowPlaying: NowPlayingService
    let ns: Namespace.ID
    let notchWidth: CGFloat
    @Environment(\.ui) private var ui

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: nowPlaying.artwork, size: ui(22), radius: ui(6))
                .matchedGeometryEffect(id: "artwork", in: ns)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth - ui(10))
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
    let notchWidth: CGFloat
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
            Color.clear.frame(width: notchWidth - ui(10))
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
