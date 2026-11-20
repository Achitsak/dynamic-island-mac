import Foundation
import IOKit.ps
import Observation
import SwiftUI

@Observable @MainActor
final class BatteryService {
    enum Event {
        case pluggedIn
        case unplugged
        case low(Int)
    }

    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var hasBattery = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Minutes until full; nil while macOS is still estimating or when not charging.
    private(set) var minutesToFull: Int?
    /// Power coming in from the charger.
    private(set) var inputWatts: Int?

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let smartBattery = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
    )

    var tint: Color {
        if isPluggedIn { return .islandGreen }
        if isLowPowerMode { return .yellow }
        if level <= 20 { return .islandRed }
        return .white
    }

    func start() {
        guard !started else { return }
        started = true
        read(notify: false)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.read(notify: true) }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    private func read(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let newLevel = Int((Double(current) / Double(maximum) * 100).rounded())
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            // macOS holds back its estimate for a few minutes after plugging in; the
            // battery's own average is usually ready well before that.
            let toFull = charging
                ? Self.validMinutes(description[kIOPSTimeToFullChargeKey] as? Int) ?? Self.validMinutes(batteryProperty("AvgTimeToFull"))
                : nil
            let watts = pluggedIn ? readInputWatts() : nil

            let oldLevel = level
            let wasPluggedIn = isPluggedIn
            hasBattery = true
            if newLevel != level { level = newLevel }
            if charging != isCharging { isCharging = charging }
            if pluggedIn != isPluggedIn { isPluggedIn = pluggedIn }
            if toFull != minutesToFull { minutesToFull = toFull }
            if watts != inputWatts { inputWatts = watts }

            guard notify else { return }
            if pluggedIn && !wasPluggedIn { onEvent?(.pluggedIn) }
            if !pluggedIn && wasPluggedIn { onEvent?(.unplugged) }
            if !pluggedIn, [20, 10, 5].contains(where: { oldLevel > $0 && newLevel <= $0 }) {
                onEvent?(.low(newLevel))
            }
            return
        }
    }

    /// What the system is drawing from the charger right now (Apple silicon reports
    /// this), otherwise what the charger negotiated.
    private func readInputWatts() -> Int? {
        if let telemetry: [String: Any] = batteryProperty("PowerTelemetryData"),
           let milliwatts = telemetry["SystemPowerIn"] as? Int, milliwatts > 0 {
            return Int((Double(milliwatts) / 1000).rounded())
        }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        return (adapter?[kIOPSPowerAdapterWattsKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    private func batteryProperty<T>(_ key: String) -> T? {
        guard smartBattery != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(smartBattery, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
    }

    /// -1 means "still estimating" and 65535 "unknown".
    private static func validMinutes(_ minutes: Int?) -> Int? {
        minutes.flatMap { (1..<65535).contains($0) ? $0 : nil }
    }

    /// "1h 20m", "45m".
    static func formatDuration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
