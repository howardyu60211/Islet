import AudioToolbox
import CoreAudio
import os

/// 系統音量：監聽預設輸出裝置的音量與靜音（Core Audio 公開 API，不需要權限）。
final class VolumeMonitor {
    /// 音量（0～100）或靜音改變時呼叫。
    var onChange: (_ level: Int, _ muted: Bool) -> Void = { _, _ in }

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var last: (level: Int, muted: Bool)?
    /// 切換輸出裝置後系統會套用新裝置的音量，這段時間內不提示。
    private var quietUntil = Date.distantPast
    private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "Volume")

    func start() {
        guard defaultDeviceListener == nil else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        defaultDeviceListener = block
        attachToDefaultDevice()
    }

    func stop() {
        if let block = defaultDeviceListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        defaultDeviceListener = nil
        detachFromDevice()
    }

    private func attachToDefaultDevice() {
        detachFromDevice()
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown
        else { return }
        deviceID = id
        last = read()
        quietUntil = Date().addingTimeInterval(1)

        // 有些裝置只有各聲道的音量，沒有「主音量」，所以全部都聽，重複的通知用 last 過濾
        var selectors: [AudioObjectPropertyAddress] = [
            Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume),
            Self.address(kAudioDevicePropertyMute),
        ]
        for channel: UInt32 in [1, 2] {
            selectors.append(Self.address(kAudioDevicePropertyVolumeScalar, element: channel))
        }
        for var address in selectors where AudioObjectHasProperty(id, &address) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.volumeChanged() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func detachFromDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        }
        deviceListeners.removeAll()
        deviceID = AudioObjectID(kAudioObjectUnknown)
        last = nil
    }

    private func volumeChanged() {
        guard let current = read() else { return }
        defer { last = current }
        guard Date() > quietUntil, let last, last != current else { return }
        onChange(current.level, current.muted)
    }

    private func read() -> (level: Int, muted: Bool)? {
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &volume) == noErr else { return nil }
        var muteAddress = Self.address(kAudioDevicePropertyMute)
        var mute = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &mute)
        }
        return (Int((volume * 100).rounded()), mute != 0)
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
}
