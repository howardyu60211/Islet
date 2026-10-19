import CoreAudio
import Observation
import os

/// 一個聲音輸出裝置（MacBook 喇叭、AirPods、外接喇叭…）。
struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            HeadphoneSymbol.name(forDeviceNamed: name)
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeUSB: "hifispeaker"
        default: "speaker.wave.2.fill"
        }
    }
}

/// 系統的聲音輸出裝置清單與切換（Core Audio 公開 API，不需要權限）。
@Observable
final class AudioOutputModel {
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var currentID: AudioDeviceID?

    @ObservationIgnored private var isListening = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "AudioOutput")

    var current: AudioOutputDevice? {
        devices.first { $0.id == currentID }
    }

    func start() {
        refresh()
        guard !isListening else { return }
        isListening = true
        // 裝置插拔（例如 AirPods 連上）或在別處切換輸出時更新
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func select(_ device: AudioOutputDevice) {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        if status == noErr {
            currentID = device.id
        } else {
            logger.error("切換輸出裝置失敗：\(status, privacy: .public)")
        }
    }

    func refresh() {
        let newDevices = Self.deviceIDs()
            .filter(Self.hasOutput)
            .compactMap { id -> AudioOutputDevice? in
                guard let name = Self.name(of: id) else { return nil }
                let transport: UInt32 = Self.value(of: id, kAudioDevicePropertyTransportType) ?? 0
                // 合成裝置是給錄音軟體用的，不列出
                guard transport != kAudioDeviceTransportTypeAggregate else { return nil }
                return AudioOutputDevice(id: id, name: name, transportType: transport)
            }
        if newDevices != devices {
            devices = newDevices
            logger.info("輸出裝置：\(newDevices.map(\.name).joined(separator: "、"), privacy: .public)")
        }
        let defaultID: AudioDeviceID? = Self.value(of: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
        if defaultID != currentID {
            currentID = defaultID
        }
    }

    // MARK: - Core Audio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
