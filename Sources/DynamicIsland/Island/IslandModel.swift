import AppKit
import Observation

enum LiveActivity: Hashable {
    case music
    case timer
    case musicAndTimer
    case charging
}

enum HUD: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case charging(level: Int)
    case lowBattery(level: Int)
    case bluetooth(name: String, symbol: String, connected: Bool)
    case timerDone

    var kind: String {
        switch self {
        case .volume: "volume"
        case .brightness: "brightness"
        case .charging: "charging"
        case .lowBattery: "lowBattery"
        case .bluetooth: "bluetooth"
        case .timerDone: "timerDone"
        }
    }

    var isBanner: Bool {
        switch self {
        case .bluetooth, .timerDone: true
        default: false
        }
    }
}

enum Presentation: Equatable {
    case idle
    case compact(LiveActivity)
    case hud(HUD)
    case expanded
}

struct LayoutKey: Equatable {
    var presentation: Presentation
    var size: CGSize
}

@Observable @MainActor
final class IslandModel {
    let settings = AppSettings.shared
    let nowPlaying = NowPlayingService()
    let battery = BatteryService()
    let timer = TimerService()
    @ObservationIgnored let volume = VolumeService()
    @ObservationIgnored let brightness = BrightnessService()
    @ObservationIgnored let bluetooth = BluetoothService()

    var geometry = IslandGeometry.placeholder
    private(set) var isExpanded = false
    private(set) var isHovering = false
    private(set) var hud: HUD?
    private(set) var musicVisible = false

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var musicHideTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessTask: Task<Void, Never>?
    @ObservationIgnored private var pendingBrightness: Float?
    @ObservationIgnored private var brightnessQuietUntil = Date.distantPast

    // MARK: Lifecycle

    func start() {
        nowPlaying.onChange = { [weak self] in self?.nowPlayingChanged() }
        battery.onEvent = { [weak self] event in self?.handle(event) }
        volume.onChange = { [weak self] level, muted in self?.volumeChanged(level, muted) }
        brightness.onChange = { [weak self] level in self?.brightnessChanged(level) }
        bluetooth.onEvent = { [weak self] name, symbol, connected in
            self?.bluetoothChanged(name: name, symbol: symbol, connected: connected)
        }
        timer.onFinish = { [weak self] in
            self?.isExpanded = false
            self?.hud = nil
        }

        nowPlaying.start()
        battery.start()
        volume.start()
        brightness.start()
        if settings.showBluetoothHUD { bluetooth.start() }
    }

    func stop() {
        nowPlaying.stop()
    }

    func settingsChanged() {
        if settings.showBluetoothHUD { bluetooth.start() }
        nowPlayingChanged()
    }

    // MARK: What the island shows

    var presentation: Presentation {
        if timer.isFinished { return .hud(.timerDone) }
        if isExpanded { return .expanded }
        if let hud { return .hud(hud) }
        if let activity = primaryActivity { return .compact(activity) }
        return .idle
    }

    var primaryActivity: LiveActivity? {
        switch (musicVisible, timer.isActive) {
        case (true, true): return .musicAndTimer
        case (true, false): return .music
        case (false, true): return .timer
        case (false, false): return showsCharging ? .charging : nil
        }
    }

    /// Lowest priority: music and the timer take the island when they're active.
    var showsCharging: Bool {
        settings.showChargingActivity && battery.isCharging
    }

    var showsPlayer: Bool {
        settings.showNowPlaying && nowPlaying.track != nil
    }

    var hidesWhenIdle: Bool {
        !geometry.hasNotch && !settings.showIdleNotchOnPlainDisplays
    }

    var layoutKey: LayoutKey {
        let p = presentation
        return LayoutKey(presentation: p, size: size(for: p))
    }

    // MARK: Geometry

    var expandedWidth: CGFloat {
        let u = geometry.unit
        return max(Layout.expandedWidth * u, geometry.notchWidth + 2 * Layout.expandedMinEar * u)
    }

    var expandedHeight: CGFloat {
        let u = geometry.unit
        var height = geometry.notchHeight
        if timer.isActive { height += Layout.timerRowHeight * u }
        height += (showsPlayer ? Layout.playerHeight : Layout.placeholderHeight) * u
        if !timer.isActive { height += Layout.presetsHeight * u }
        return height + Layout.bottomPadding * u
    }

    /// Size without hover growth. Content is laid out at this size so it doesn't
    /// re-flow while the shape morphs around it.
    func contentSize(for p: Presentation) -> CGSize {
        let u = geometry.unit
        let nw = geometry.notchWidth
        let nh = geometry.notchHeight
        func ears(_ ear: CGFloat, extra: CGFloat = 0) -> CGSize {
            CGSize(width: nw + 2 * ear * u, height: nh + extra * u)
        }
        switch p {
        case .idle:
            return CGSize(width: nw, height: nh)
        case .compact(.music):
            return ears(Layout.musicEar)
        case .compact(.timer):
            return ears(Layout.timerEar)
        case .compact(.musicAndTimer):
            return ears(Layout.musicTimerEar)
        case .compact(.charging):
            return ears(Layout.chargingEar)
        case .hud(let hud):
            switch hud {
            case .volume, .brightness: return ears(Layout.volumeEar)
            case .charging, .lowBattery: return ears(Layout.batteryEar)
            case .bluetooth: return ears(Layout.bannerEar, extra: Layout.bannerExtra)
            case .timerDone:
                return CGSize(width: max(Layout.alertWidth * u, nw + 2 * 60 * u), height: nh + Layout.alertExtra * u)
            }
        case .expanded:
            return CGSize(width: expandedWidth, height: expandedHeight)
        }
    }

    func size(for p: Presentation) -> CGSize {
        var size = contentSize(for: p)
        // Only nudge on hover when hovering won't expand it anyway.
        if isHovering, !settings.expandOnHover, p != .expanded, p != .hud(.timerDone) {
            size.width += Layout.hoverGrowX * geometry.unit
            size.height += Layout.hoverGrowY * geometry.unit
        }
        return size
    }

    func cornerRadii(for p: Presentation) -> (top: CGFloat, bottom: CGFloat) {
        let u = geometry.unit
        switch p {
        case .idle: return (4 * u, 13 * u)  // Tucked behind the hardware notch.
        case .compact: return (5 * u, 14 * u)
        case .hud(let hud) where hud.isBanner: return (7 * u, 22 * u)
        case .hud: return (5 * u, 14 * u)
        case .expanded: return (9 * u, 30 * u)
        }
    }

    var hitRect: CGRect {
        let p = presentation
        let s = size(for: p)
        var rect = CGRect(x: geometry.centerX - s.width / 2, y: geometry.screenTop - s.height, width: s.width, height: s.height)
        if p != .expanded {
            rect = rect.insetBy(dx: -3 * geometry.unit, dy: 0)
            rect.origin.y -= 3 * geometry.unit
            rect.size.height += 3 * geometry.unit
        }
        return rect
    }

    // MARK: Interaction

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        hoverTask?.cancel()

        if hovering {
            guard settings.expandOnHover, !isExpanded else { return }
            let delay = settings.hoverDelay
            hoverTask = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, let self, self.isHovering else { return }
                self.expand()
            }
        } else if isExpanded {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled, let self, !self.isHovering else { return }
                self.collapse()
            }
        }
    }

    func handleTap() {
        switch presentation {
        case .hud(.timerDone): timer.dismissAlert()
        case .expanded: break
        default: expand()
        }
    }

    func expand() {
        guard !isExpanded, !timer.isFinished else { return }
        hudTask?.cancel()
        hud = nil
        isExpanded = true
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
    }

    // MARK: Events

    func show(_ hud: HUD, for duration: Double) {
        guard !isExpanded else { return }
        self.hud = hud
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hud = nil
        }
    }

    private func nowPlayingChanged() {
        guard settings.showNowPlaying, nowPlaying.track != nil else {
            musicHideTask?.cancel()
            musicVisible = false
            return
        }
        if nowPlaying.isPlaying || !settings.hideMusicWhenPaused {
            musicHideTask?.cancel()
            musicHideTask = nil
            if !musicVisible { musicVisible = true }
        } else if musicVisible, musicHideTask == nil {
            musicHideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                self.musicHideTask = nil
                if !self.nowPlaying.isPlaying { self.musicVisible = false }
            }
        }
    }

    private func volumeChanged(_ level: Float, _ muted: Bool) {
        guard settings.showVolumeHUD else { return }
        show(.volume(level: level, muted: muted), for: 1.6)
    }

    private func brightnessChanged(_ level: Float) {
        guard settings.showBrightnessHUD, Date.now > brightnessQuietUntil else { return }
        if case .hud(.brightness) = presentation {
            show(.brightness(level: level), for: 1.6)
            return
        }
        // Wait a beat before popping up: when the system changes the brightness by
        // itself, the event behind it (power, displays) can be reported just after.
        pendingBrightness = level
        guard brightnessTask == nil else { return }
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.brightnessTask = nil
            if let level = self.pendingBrightness { self.show(.brightness(level: level), for: 1.6) }
        }
    }

    /// macOS changes the brightness by itself when switching between battery and power
    /// (it dims a little on battery) and when displays are connected; that shouldn't
    /// show up as a brightness change.
    func ignoreSystemBrightnessChanges() {
        brightnessQuietUntil = .now + 3
        brightnessTask?.cancel()
        brightnessTask = nil
        if case .hud(.brightness) = presentation { hud = nil }
    }

    private func handle(_ event: BatteryService.Event) {
        switch event {
        case .pluggedIn:
            ignoreSystemBrightnessChanges()
            guard settings.showChargingHUD else { return }
            show(.charging(level: battery.level), for: 3.2)
        case .unplugged:
            ignoreSystemBrightnessChanges()
            if case .hud(.charging) = presentation { hud = nil }
        case .low(let level):
            guard settings.showLowBatteryHUD else { return }
            show(.lowBattery(level: level), for: 4)
        }
    }

    // MARK: Demo

    /// Cycles through every state (menu bar → Play Demo, or launch with --demo).
    func runDemo() {
        hoverTask?.cancel()
        Task { [weak self] in
            func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            guard let self else { return }

            self.show(.charging(level: self.battery.level), for: 3)
            await wait(3.6)

            for level: Float in [0.35, 0.45, 0.55, 0.65, 0.75] {
                self.show(.volume(level: level, muted: false), for: 1.4)
                await wait(0.3)
            }
            await wait(1.8)

            for level: Float in [0.8, 0.7, 0.6, 0.5] {
                self.show(.brightness(level: level), for: 1.4)
                await wait(0.3)
            }
            await wait(1.8)

            self.show(.bluetooth(name: "AirPods Pro", symbol: BluetoothService.symbolForName("AirPods Pro"), connected: true), for: 3)
            await wait(3.6)

            self.expand()
            await wait(4.5)
            self.collapse()
            await wait(1.2)

            self.timer.start(seconds: 125)
            await wait(4)
            self.expand()
            await wait(4.5)
            self.collapse()
            await wait(1.2)

            self.show(.lowBattery(level: 10), for: 3)
            await wait(3.6)

            self.timer.start(seconds: 1.5)
            await wait(6)
            self.timer.dismissAlert()
        }
    }

    private func bluetoothChanged(name: String, symbol: String, connected: Bool) {
        guard settings.showBluetoothHUD else { return }
        show(.bluetooth(name: name, symbol: symbol, connected: connected), for: 3)
    }
}
