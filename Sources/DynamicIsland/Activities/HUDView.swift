import SwiftUI

struct HUDView: View {
    let hud: HUD
    let model: IslandModel
    @Environment(\.ui) private var ui

    private var notchGap: CGFloat { model.geometry.notchWidth - ui(10) }

    var body: some View {
        switch hud {
        case .volume(let level, let muted):
            let percent = muted ? 0 : Int((level * 100).rounded())
            ears {
                HStack(spacing: ui(6)) {
                    Symbol(name: Self.speakerSymbol(level: level, muted: muted), size: ui(13))
                        .frame(width: ui(19), alignment: .leading)
                    Text(muted ? "Muted" : "\(percent)%")
                        .font(.system(size: ui(13), weight: .semibold).monospacedDigit())
                        .fixedSize()
                }
                .foregroundStyle(.white)
            } trailing: {
                LevelBar(value: muted ? 0 : Double(level))
                    .frame(height: ui(6))
                    .padding(.leading, ui(4))
            }

        case .charging(let level):
            ears {
                Text("Charging")
                    .font(.system(size: ui(13), weight: .semibold))
                    .foregroundStyle(Color.islandGreen)
            } trailing: {
                HStack(spacing: ui(5)) {
                    Text("\(level)%")
                        .font(.system(size: ui(13), weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.islandGreen)
                    BatteryGlyph(level: level, tint: .islandGreen, showsBolt: true)
                }
            }

        case .lowBattery(let level):
            ears {
                Text("Low Battery")
                    .font(.system(size: ui(12.5), weight: .semibold))
                    .foregroundStyle(Color.islandRed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } trailing: {
                HStack(spacing: ui(5)) {
                    Text("\(level)%")
                        .font(.system(size: ui(13), weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.islandRed)
                    BatteryGlyph(level: level, tint: .islandRed)
                }
            }

        case .bluetooth(let name, let symbol, let connected):
            VStack(spacing: 0) {
                ears {
                    Symbol(name: symbol, size: ui(17), weight: .medium)
                        .foregroundStyle(.white)
                } trailing: {
                    Symbol(name: connected ? "checkmark.circle.fill" : "minus.circle.fill", size: ui(16))
                        .foregroundStyle(connected ? Color.islandGreen : Color.islandSecondary)
                }
                .frame(height: model.geometry.notchHeight)

                HStack(spacing: ui(6)) {
                    Text(name)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(connected ? "Connected" : "Disconnected")
                        .foregroundStyle(Color.islandSecondary)
                        .fixedSize()
                }
                .font(.system(size: ui(13), weight: .semibold))
                .padding(.horizontal, ui(20))
                .frame(maxHeight: .infinity)
                .padding(.bottom, ui(4))
            }

        case .timerDone:
            VStack(spacing: 0) {
                Color.clear.frame(height: model.geometry.notchHeight)
                HStack(spacing: ui(12)) {
                    ZStack {
                        Circle().fill(Color.timerOrange.opacity(0.2))
                        Symbol(name: "timer", size: ui(17))
                            .foregroundStyle(Color.timerOrange)
                    }
                    .frame(width: ui(40), height: ui(40))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Timer")
                            .font(.system(size: ui(12), weight: .medium))
                            .foregroundStyle(Color.islandSecondary)
                        Text("Done")
                            .font(.system(size: ui(21), weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: ui(8))
                    Button {
                        model.timer.dismissAlert()
                    } label: {
                        Text("Stop")
                            .font(.system(size: ui(14), weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, ui(20))
                            .frame(height: ui(32))
                            .background(Capsule().fill(Color.timerOrange))
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .padding(.horizontal, ui(Layout.sidePadding))
                .frame(maxHeight: .infinity)
                .padding(.bottom, ui(6))
            }
        }
    }

    private static func speakerSymbol(level: Float, muted: Bool) -> String {
        if muted { return "speaker.slash.fill" }
        switch level {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func ears<L: View, T: View>(@ViewBuilder _ leading: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 0) {
            leading().frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchGap)
            trailing().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, ui(14))
        .frame(height: model.geometry.notchHeight)
    }
}

private struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(geo.size.height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
    }
}
