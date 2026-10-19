import Foundation
import Observation
import os

/// 螢幕是否正在被錄影或分享。
/// macOS 沒有公開 API，這裡用 WindowServer（SkyLight）的私有函式 SLSIsScreenWatcherPresent，
/// 系統的螢幕錄影、QuickTime、ScreenCaptureKit 的 App、螢幕共享都會讓它變成 true。找不到這個函式時就不啟用。
@Observable
final class ScreenRecordingMonitor {
    private(set) var isActive = false

    @ObservationIgnored var onChange: (Bool) -> Void = { _ in }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "ScreenRecording")

    /// 沒有通知可以聽，所以定時查（呼叫本身很便宜）。
    private static let pollInterval: TimeInterval = 1.5

    private typealias WatcherFunction = @convention(c) () -> Bool

    private static let isWatcherPresent: WatcherFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSIsScreenWatcherPresent")
        else { return nil }
        return unsafeBitCast(symbol, to: WatcherFunction.self)
    }()

    static var isSupported: Bool { isWatcherPresent != nil }

    func start() {
        guard timer == nil else { return }
        guard let isWatcherPresent = Self.isWatcherPresent else {
            logger.error("找不到 SLSIsScreenWatcherPresent，不啟用螢幕錄影提示")
            return
        }
        // 啟動時已經在錄的不提示
        isActive = isWatcherPresent()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func poll() {
        guard let isWatcherPresent = Self.isWatcherPresent else { return }
        let active = isWatcherPresent()
        guard active != isActive else { return }
        isActive = active
        logger.info("screen capture \(active ? "started" : "stopped", privacy: .public)")
        onChange(active)
    }
}
