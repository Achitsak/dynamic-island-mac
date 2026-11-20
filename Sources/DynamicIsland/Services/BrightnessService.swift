import CoreGraphics
import Foundation

/// Built-in display brightness. macOS has no public API for it, so this uses the
/// private DisplayServices framework (looked up at runtime; if it's missing the
/// brightness alert just never shows).
@MainActor
final class BrightnessService {
    var onChange: ((Float) -> Void)?

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias RegisterForChanges = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    private var display = CGDirectDisplayID(0)
    private var getBrightness: GetBrightness?
    private var last: Float?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        guard let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(framework, "DisplayServicesGetBrightness"),
              let register = dlsym(framework, "DisplayServicesRegisterForBrightnessChangeNotifications"),
              let display = Self.builtInDisplay() else { return }
        self.display = display
        getBrightness = unsafeBitCast(get, to: GetBrightness.self)
        last = read()  // Baseline only.

        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let service = Unmanaged<BrightnessService>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { service.valueChanged() }
            }
        }
        _ = unsafeBitCast(register, to: RegisterForChanges.self)(display, Unmanaged.passUnretained(self).toOpaque(), callback)
    }

    private func valueChanged() {
        guard let now = read() else { return }
        defer { last = now }
        if let last, abs(last - now) < 0.005 { return }
        onChange?(now)
    }

    private func read() -> Float? {
        var value = Float(0)
        guard let getBrightness, getBrightness(display, &value) == 0 else { return nil }
        return min(max(value, 0), 1)
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count = UInt32(0)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}
