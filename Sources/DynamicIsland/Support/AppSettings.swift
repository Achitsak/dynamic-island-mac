import Foundation
import Observation

/// User preferences, persisted in UserDefaults. Every change posts `didChange`.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let didChange = Notification.Name("AppSettingsDidChange")

    var expandOnHover: Bool { didSet { save(expandOnHover, "expandOnHover") } }
    var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    var hapticFeedback: Bool { didSet { save(hapticFeedback, "hapticFeedback") } }

    var showNowPlaying: Bool { didSet { save(showNowPlaying, "showNowPlaying") } }
    var hideMusicWhenPaused: Bool { didSet { save(hideMusicWhenPaused, "hideMusicWhenPaused") } }
    var showChargingActivity: Bool { didSet { save(showChargingActivity, "showChargingActivity") } }

    var showVolumeHUD: Bool { didSet { save(showVolumeHUD, "showVolumeHUD") } }
    var showBrightnessHUD: Bool { didSet { save(showBrightnessHUD, "showBrightnessHUD") } }
    var showChargingHUD: Bool { didSet { save(showChargingHUD, "showChargingHUD") } }
    var showLowBatteryHUD: Bool { didSet { save(showLowBatteryHUD, "showLowBatteryHUD") } }
    var showBluetoothHUD: Bool { didSet { save(showBluetoothHUD, "showBluetoothHUD") } }

    var sizeScale: Double { didSet { save(sizeScale, "sizeScale") } }
    var preferMainDisplay: Bool { didSet { save(preferMainDisplay, "preferMainDisplay") } }
    var showIdleNotchOnPlainDisplays: Bool { didSet { save(showIdleNotchOnPlainDisplays, "showIdleNotchOnPlainDisplays") } }
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "expandOnHover": true,
            "hoverDelay": 0.15,
            "hapticFeedback": true,
            "showNowPlaying": true,
            "hideMusicWhenPaused": true,
            "showChargingActivity": true,
            "showVolumeHUD": true,
            "showBrightnessHUD": true,
            "showChargingHUD": true,
            "showLowBatteryHUD": true,
            "showBluetoothHUD": true,
            "sizeScale": 1.0,
            "preferMainDisplay": false,
            "showIdleNotchOnPlainDisplays": true,
            "showMenuBarIcon": true,
        ])
        expandOnHover = d.bool(forKey: "expandOnHover")
        hoverDelay = d.double(forKey: "hoverDelay")
        hapticFeedback = d.bool(forKey: "hapticFeedback")
        showNowPlaying = d.bool(forKey: "showNowPlaying")
        hideMusicWhenPaused = d.bool(forKey: "hideMusicWhenPaused")
        showChargingActivity = d.bool(forKey: "showChargingActivity")
        showVolumeHUD = d.bool(forKey: "showVolumeHUD")
        showBrightnessHUD = d.bool(forKey: "showBrightnessHUD")
        showChargingHUD = d.bool(forKey: "showChargingHUD")
        showLowBatteryHUD = d.bool(forKey: "showLowBatteryHUD")
        showBluetoothHUD = d.bool(forKey: "showBluetoothHUD")
        sizeScale = d.double(forKey: "sizeScale")
        preferMainDisplay = d.bool(forKey: "preferMainDisplay")
        showIdleNotchOnPlainDisplays = d.bool(forKey: "showIdleNotchOnPlainDisplays")
        showMenuBarIcon = d.bool(forKey: "showMenuBarIcon")
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
