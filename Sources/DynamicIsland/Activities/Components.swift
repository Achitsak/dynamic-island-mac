import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.32), Color(white: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: image)
    }
}

/// Waveform bars in the artwork's accent colour. Animated with Core Animation
/// keyframes so they cost no CPU in the app while music plays.
struct WaveformView: NSViewRepresentable {
    let color: Color
    let isPlaying: Bool
    var bars = 4

    func makeNSView(context: Context) -> WaveformLayerView {
        WaveformLayerView(bars: bars)
    }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.update(color: NSColor(color), playing: isPlaying)
    }
}

final class WaveformLayerView: NSView {
    private static let envelope: [CGFloat] = [0.6, 0.95, 0.8, 1.0, 0.65]
    private var barLayers: [CALayer] = []
    private var playing = false

    init(bars: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<bars {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var barWidth: CGFloat {
        bounds.width / (CGFloat(barLayers.count) * 1.7 - 0.7)
    }

    private var restScale: CGFloat {
        bounds.height > 0 ? min(1, barWidth / bounds.height) : 1
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = barWidth
        for (index, bar) in barLayers.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * width * 1.7 + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
            if !playing { bar.transform = CATransform3DMakeScale(1, restScale, 1) }
        }
        CATransaction.commit()
        if playing { startWave() }
    }

    func update(color: NSColor, playing: Bool) {
        let cgColor = color.cgColor
        for bar in barLayers where bar.backgroundColor != cgColor {
            bar.backgroundColor = cgColor
        }
        guard playing != self.playing else { return }
        self.playing = playing
        playing ? startWave() : stopWave()
    }

    private func startWave() {
        guard bounds.height > 0 else { return }
        for (index, bar) in barLayers.enumerated() where bar.animation(forKey: "wave") == nil {
            let envelope = Self.envelope[index % Self.envelope.count]
            var values = (0..<9).map { _ in 0.22 + 0.78 * CGFloat.random(in: 0.12...1) * envelope }
            values.append(values[0])  // Loop seamlessly.

            let wave = CAKeyframeAnimation(keyPath: "transform.scale.y")
            wave.values = values
            wave.duration = Double.random(in: 1.5...2.1)
            wave.calculationMode = .cubic
            wave.repeatCount = .infinity
            wave.timeOffset = Double.random(in: 0...wave.duration)
            wave.isRemovedOnCompletion = false
            bar.transform = CATransform3DIdentity
            bar.add(wave, forKey: "wave")
        }
    }

    private func stopWave() {
        for bar in barLayers {
            if let current = bar.presentation()?.transform { bar.transform = current }
            bar.removeAnimation(forKey: "wave")
            bar.transform = CATransform3DMakeScale(1, restScale, 1)
        }
    }
}

/// Scrolls text that doesn't fit. The text is drawn once and moved by Core
/// Animation, so a long title costs nothing per frame.
struct MarqueeText: NSViewRepresentable {
    let text: String
    let size: CGFloat
    let weight: NSFont.Weight
    let color: NSColor
    let height: CGFloat

    func makeNSView(context: Context) -> MarqueeView {
        MarqueeView()
    }

    func updateNSView(_ view: MarqueeView, context: Context) {
        view.configure(text: text, font: .systemFont(ofSize: size, weight: weight), color: color, gap: size * 2.4, speed: size * 2)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.textSize.width, height: height)
    }
}

final class MarqueeView: NSView {
    private(set) var textSize = CGSize.zero

    private let strip = CALayer()  // Holds both copies of the text; this is what scrolls.
    private let first = CALayer()
    private let second = CALayer()
    private let fade = CAGradientLayer()
    private var text = ""
    private var font = NSFont.systemFont(ofSize: 13)
    private var color = NSColor.white
    private var gap: CGFloat = 30
    private var speed: CGFloat = 26
    private var scrollSignature: [CGFloat] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        let still = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull()]
        for sublayer in [strip, first, second] { sublayer.actions = still }
        strip.addSublayer(first)
        strip.addSublayer(second)
        layer?.addSublayer(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        fade.locations = [0, 0.04, 0.92, 1]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String, font: NSFont, color: NSColor, gap: CGFloat, speed: CGFloat) {
        guard text != self.text || font != self.font || color != self.color else { return }
        self.text = text
        self.font = font
        self.color = color
        self.gap = gap
        self.speed = speed
        render()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render()
    }

    private func render() {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let measured = attributed.size()
        textSize = CGSize(width: ceil(measured.width), height: ceil(measured.height))
        guard textSize.width > 0 else {
            first.contents = nil
            second.contents = nil
            return
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let image = NSImage(size: textSize, flipped: false) { _ in
            attributed.draw(at: .zero)
            return true
        }
        let contents = image.layerContents(forContentsScale: scale)
        for copy in [first, second] {
            copy.contents = contents
            copy.contentsScale = scale
        }
    }

    override func layout() {
        super.layout()
        let y = ((bounds.height - textSize.height) / 2).rounded()
        first.frame = CGRect(x: 0, y: y, width: textSize.width, height: textSize.height)
        second.frame = CGRect(x: textSize.width + gap, y: y, width: textSize.width, height: textSize.height)
        strip.frame = CGRect(x: 0, y: 0, width: textSize.width * 2 + gap, height: bounds.height)
        fade.frame = bounds

        let overflow = textSize.width > bounds.width + 0.5
        second.isHidden = !overflow
        layer?.mask = overflow ? fade : nil

        let signature = [textSize.width, bounds.width, gap, speed]
        guard signature != scrollSignature else { return }
        scrollSignature = signature
        strip.removeAnimation(forKey: "scroll")
        guard overflow else { return }

        let distance = textSize.width + gap
        let pause = 2.2
        let travel = Double(distance / speed)
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -distance]
        scroll.keyTimes = [0, NSNumber(value: pause / (pause + travel)), 1]
        scroll.duration = pause + travel
        scroll.repeatCount = .infinity
        scroll.isRemovedOnCompletion = false
        strip.add(scroll, forKey: "scroll")
    }
}

struct ProgressRow: View {
    let elapsed: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @Environment(\.ui) private var ui
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        let live = duration <= 0
        let fraction = dragFraction ?? (live ? 0 : min(max(elapsed / duration, 0), 1))
        let active = dragFraction != nil || hovering

        HStack(spacing: ui(10)) {
            Text(live ? "" : Self.format(fraction * duration))
                .frame(width: ui(38), alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(Color.white.opacity(active ? 1 : 0.9))
                        .frame(width: max(0, width * fraction))
                }
                .frame(height: active ? ui(8) : ui(5))
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !live, width > 0 else { return }
                            dragFraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            guard !live, width > 0 else { return }
                            let target = min(max(value.location.x / width, 0), 1)
                            onSeek(target * duration)
                            dragFraction = nil
                        }
                )
                .onHover { hovering = $0 }
                .animation(.spring(duration: 0.25, bounce: 0.2), value: active)
            }

            Text(live ? "LIVE" : "-" + Self.format(max(0, duration - fraction * duration)))
                .frame(width: ui(42), alignment: .trailing)
        }
        .font(.system(size: ui(10.5), weight: .medium).monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.5))
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// SF Symbol drawn through AppKit. SwiftUI's symbol views pull in the symbol
/// animation engine (~60 MB) as soon as a symbol changes, so icons that swap use this.
struct Symbol: View {
    let name: String
    let size: CGFloat
    var weight: NSFont.Weight = .semibold

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Image(nsImage: Self.image(name, size, weight))
            .renderingMode(.template)
    }

    @MainActor private static func image(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSImage {
        let key = "\(name)|\(size)|\(weight.rawValue)"
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Symbol(name: symbol, size: size)
                .foregroundStyle(.white)
                .frame(width: size * 1.9, height: size * 1.9)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct CircleButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void
    @Environment(\.ui) private var ui

    var body: some View {
        Button(action: action) {
            Symbol(name: symbol, size: ui(13), weight: .bold)
                .foregroundStyle(tint)
                .frame(width: ui(32), height: ui(32))
                .background(Circle().fill(tint.opacity(0.22)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PresetChip: View {
    let title: String
    let action: () -> Void
    @Environment(\.ui) private var ui
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: ui(12), weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, ui(10))
                .frame(height: ui(26))
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.22 : 0.12)))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.4), value: configuration.isPressed)
    }
}

struct BatteryGlyph: View {
    let level: Int
    let tint: Color
    var showsBolt = false
    @Environment(\.ui) private var ui

    var body: some View {
        let width = ui(25), height = ui(12.5), inset = ui(2)
        HStack(spacing: ui(1.5)) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: ui(4), style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: ui(1.1))
                RoundedRectangle(cornerRadius: ui(2.4), style: .continuous)
                    .fill(tint)
                    .frame(width: max(ui(2), (width - inset * 2) * CGFloat(min(max(level, 0), 100)) / 100))
                    .padding(inset)
            }
            .frame(width: width, height: height)
            .overlay {
                if showsBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: ui(8.5), weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: ui(1))
                }
            }
            Capsule()
                .fill(Color.white.opacity(0.38))
                .frame(width: ui(1.8), height: ui(4.5))
        }
    }
}
