import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Interaction") {
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
                if settings.expandOnHover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...0.8, step: 0.05)
                            Text("\(Int(settings.hoverDelay * 1000)) ms")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
                Toggle("Haptic feedback on the trackpad", isOn: $settings.hapticFeedback)
            }

            Section("Live Activities") {
                Toggle("Now Playing", isOn: $settings.showNowPlaying)
                Toggle("Hide music a few seconds after pausing", isOn: $settings.hideMusicWhenPaused)
                    .disabled(!settings.showNowPlaying)
            }

            Section("Alerts") {
                Toggle("Volume changes", isOn: $settings.showVolumeHUD)
                Toggle("Charging", isOn: $settings.showChargingHUD)
                Toggle("Low battery", isOn: $settings.showLowBatteryHUD)
                Toggle("Bluetooth devices (AirPods, keyboards…)", isOn: $settings.showBluetoothHUD)
            }

            Section("Appearance") {
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $settings.sizeScale, in: 0.8...1.3, step: 0.05)
                        Text("\(Int(settings.sizeScale * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Picker("Display", selection: $settings.preferMainDisplay) {
                    Text("Built-in display (notch)").tag(false)
                    Text("Main display").tag(true)
                }
                Toggle("Show idle island on displays without a notch", isOn: $settings.showIdleNotchOnPlainDisplays)
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Right-click the island for Settings and Quit, even when the menu bar icon is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 520)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
