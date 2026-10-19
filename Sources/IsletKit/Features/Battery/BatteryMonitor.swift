import Foundation
import IOKit.ps
import Observation
import os

/// 用 IOKit 的電源通知追蹤內建電池（公開 API，不需要權限）。
@Observable
final class BatteryMonitor {
    private(set) var state: BatteryState?
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// 需要跳出提示時呼叫。
    @ObservationIgnored var onEvent: (IslandEvent.Kind) -> Void = { _ in }

    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.Islet", category: "Battery")
    @ObservationIgnored private var tracker = BatteryAlertTracker()
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var lowPowerObserver: NSObjectProtocol?

    func start() {
        guard runLoopSource == nil else { return }
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(powerSourcesChanged, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        lowPowerObserver = nil
    }

    func refresh() {
        guard let newState = Self.readInternalBattery() else { return }
        apply(newState)
    }

    /// 套用新狀態並視需要發出提示（測試與 Debug 快照也用這個）。
    func apply(_ newState: BatteryState) {
        if newState != state {
            state = newState
            logger.info("battery level=\(newState.level, privacy: .public) plugged=\(newState.isPluggedIn, privacy: .public) charging=\(newState.isCharging, privacy: .public) charged=\(newState.isCharged, privacy: .public)")
        }
        if let event = tracker.update(with: newState) {
            onEvent(event)
        }
    }

    private static func readInternalBattery() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            return BatteryState(
                level: min(max(level, 0), 100),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }
}

/// IOKit 在主執行緒的 run loop 上呼叫這個 C callback。
private nonisolated func powerSourcesChanged(_ context: UnsafeMutableRawPointer?) {
    // 指標本身不是 Sendable，用位址傳進 main actor 再還原。
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<BatteryMonitor>.fromOpaque(pointer).takeUnretainedValue().refresh()
    }
}
