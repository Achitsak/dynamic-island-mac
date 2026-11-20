import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class VolumeService {
    var onChange: ((Float, Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var last: (volume: Float, muted: Bool)?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?
    private var boundAddresses: [AudioObjectPropertyAddress] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bindDefaultDevice() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        bindDefaultDevice()
    }

    private func bindDefaultDevice() {
        unbind()
        device = Self.defaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        last = read()  // Baseline only: switching devices is not a volume change.

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.valuesChanged() }
        }
        valueListener = listener
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            guard AudioObjectHasProperty(device, &address) else { continue }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr {
                boundAddresses.append(address)
            }
        }
    }

    private func unbind() {
        guard let valueListener else { return }
        for var address in boundAddresses {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, valueListener)
        }
        boundAddresses.removeAll()
        self.valueListener = nil
    }

    private func valuesChanged() {
        guard let now = read() else { return }
        defer { last = now }
        if let last, abs(last.volume - now.volume) < 0.002, last.muted == now.muted { return }
        onChange?(now.volume, now.muted)
    }

    private func read() -> (volume: Float, muted: Bool)? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }

        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(device, &muteAddress) {
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted)
        }
        return (volume, muted != 0)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
