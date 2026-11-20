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

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var started = false

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

            let oldLevel = level
            let wasPluggedIn = isPluggedIn
            hasBattery = true
            if newLevel != level { level = newLevel }
            if charging != isCharging { isCharging = charging }
            if pluggedIn != isPluggedIn { isPluggedIn = pluggedIn }

            guard notify else { return }
            if pluggedIn && !wasPluggedIn { onEvent?(.pluggedIn) }
            if !pluggedIn && wasPluggedIn { onEvent?(.unplugged) }
            if !pluggedIn, [20, 10, 5].contains(where: { oldLevel > $0 && newLevel <= $0 }) {
                onEvent?(.low(newLevel))
            }
            return
        }
    }
}
