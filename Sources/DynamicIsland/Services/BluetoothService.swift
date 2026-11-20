import AppKit
import IOBluetooth

@MainActor
final class BluetoothService: NSObject {
    var onEvent: ((_ name: String, _ symbol: String, _ connected: Bool) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var startDate = Date()

    func start() {
        guard connectNotification == nil else { return }
        startDate = Date()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // Registration replays devices that are already connected; don't announce those.
        guard Date().timeIntervalSince(startDate) > 3 else { return }
        onEvent?(Self.name(of: device), Self.symbol(for: device), true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        onEvent?(Self.name(of: device), Self.symbol(for: device), false)
    }

    private static func name(of device: IOBluetoothDevice) -> String {
        device.name ?? device.nameOrAddress ?? "Bluetooth Device"
    }

    static func symbolForName(_ name: String) -> String {
        let name = name.lowercased()
        let candidates = name.contains("airpods pro") ? ["airpods.pro", "airpodspro"]
            : name.contains("airpods") ? ["airpods.gen3", "airpods"] : ["headphones"]
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "headphones"
    }

    static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        var candidates: [String]
        if name.contains("airpods max") {
            candidates = ["airpods.max", "airpodsmax"]
        } else if name.contains("airpods pro") {
            candidates = ["airpods.pro", "airpodspro"]
        } else if name.contains("airpods") {
            candidates = ["airpods.gen3", "airpods"]
        } else if name.contains("beats") {
            candidates = ["beats.headphones"]
        } else {
            switch device.deviceClassMajor {
            case 0x04:  // Audio / video
                candidates = ["headphones", "hifispeaker"]
            case 0x05:  // Peripheral
                let minor = device.deviceClassMinor
                if minor & 0x10 != 0 {
                    candidates = ["keyboard"]
                } else if minor & 0x20 != 0 {
                    candidates = name.contains("trackpad") ? ["rectangle.and.hand.point.up.left"] : ["magicmouse", "computermouse"]
                } else {
                    candidates = ["gamecontroller"]
                }
            case 0x02:
                candidates = ["iphone"]
            default:
                candidates = []
            }
        }
        candidates.append("dot.radiowaves.left.and.right")
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "bolt.horizontal"
    }
}
