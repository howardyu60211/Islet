import CoreAudio
import Observation
import os

/// 麥克風是否有 App 在用（Core Audio 公開 API，不需要權限）。
/// macOS 14.2 以上可以知道是哪個 App；更舊的系統只看輸入裝置有沒有在跑。
/// 有些系統版本（例如 macOS 27）不會送出行程「開始／停止輸入」的通知，所以除了監聽也定時查一次。
@Observable
final class MicrophoneMonitor {
    private(set) var isActive = false
    /// 正在錄音的 App（較舊的系統上是空的）。
    private(set) var apps: [SensorApp] = []

    /// 開始或停止使用時呼叫；app 是剛開始用（或最後停止）的 App。
    @ObservationIgnored var onChange: (_ active: Bool, _ app: SensorApp?) -> Void = { _, _ in }

    @ObservationIgnored private var listListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var objectListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    /// 輪詢前先看的輸入裝置，連同找到它們時的完整裝置清單；清單變了或過期就重新找（不靠通知，macOS 27 上通知不可靠）。
    @ObservationIgnored private var inputDevices: (devices: [AudioObjectID], inputs: [AudioObjectID], expiry: Date)?
    @ObservationIgnored private var evaluateTask: Task<Void, Never>?
    @ObservationIgnored private var pollTimer: Timer?
    /// 第一次讀到的狀態不提示（啟動時已經在錄音的不算「開始」）。
    @ObservationIgnored private var isPrimed = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "Microphone")

    private static var system: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }
    /// 通知沒來時的備援輪詢間隔（平常只讀幾個輸入裝置的屬性，很便宜）。
    private static let pollInterval: TimeInterval = 1
    /// 輸入裝置分類最多沿用多久。
    private static let inputDevicesLifetime: TimeInterval = 10

    private static var usesProcessList: Bool {
        if #available(macOS 14.2, *) { true } else { false }
    }

    func start() {
        guard listListener == nil else { return }
        var address = Self.listAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshObjects() }
        }
        AudioObjectAddPropertyListenerBlock(Self.system, &address, .main, block)
        listListener = block
        isPrimed = false
        refreshObjects()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        evaluateTask?.cancel()
        pollTimer?.invalidate()
        pollTimer = nil
        if let listListener {
            var address = Self.listAddress
            AudioObjectRemovePropertyListenerBlock(Self.system, &address, .main, listListener)
        }
        listListener = nil
        inputDevices = nil
        for (id, block) in objectListeners {
            var address = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        objectListeners.removeAll()
        isActive = false
        apps = []
    }

    // MARK: - 監聽

    /// 行程（或輸入裝置）清單變了：替新的物件加上監聽、拿掉消失的。
    private func refreshObjects() {
        let objects = Set(Self.watchedObjects())
        for id in objects where objectListeners[id] == nil {
            var address = Self.runningAddress
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleEvaluate() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
                objectListeners[id] = block
            }
        }
        for (id, block) in objectListeners where !objects.contains(id) {
            var address = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
            objectListeners[id] = nil
        }
        scheduleEvaluate()
    }

    /// 等一下再判斷，避免短暫開關（例如系統音效、聽寫剛啟動）閃一下。
    private func scheduleEvaluate() {
        evaluateTask?.cancel()
        evaluateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    /// 狀態跟上次不同時才判斷（一樣經過 scheduleEvaluate 的延遲，短暫開關不會閃一下）。
    private func poll() {
        guard isPrimed else { return }
        // 沒在錄音、輸入裝置也都沒在跑時不用逐一查每個行程（省下二十幾次跟 coreaudiod 的往返）
        if !isActive, Self.usesProcessList, !isAnyInputDeviceRunning() { return }
        let (active, users) = Self.currentState()
        if active != isActive || users != apps {
            scheduleEvaluate()
        }
    }

    /// 有沒有輸入裝置正在執行（不管是哪個 App 在用）。同時有輸出的裝置（例如 AirPods）放音樂時也會是 true，這時就照常逐一查。
    private func isAnyInputDeviceRunning() -> Bool {
        let devices = Self.objectList(of: Self.system, Self.address(kAudioHardwarePropertyDevices))
        // 讀不到裝置清單（例如 coreaudiod 正在重啟）時不留快取，照常逐一查
        guard !devices.isEmpty else {
            inputDevices = nil
            return true
        }
        let now = Date()
        let inputs: [AudioObjectID]
        if let cached = inputDevices, cached.devices == devices, cached.expiry > now {
            inputs = cached.inputs
        } else {
            // 剛接上的裝置可能還沒列出輸入串流，所以清單沒變也定期重新分類
            inputs = devices.filter { Self.hasStreams($0, kAudioObjectPropertyScopeInput) }
            inputDevices = (devices, inputs, now.addingTimeInterval(Self.inputDevicesLifetime))
        }
        return inputs.contains { (Self.value(of: $0, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)) as UInt32? ?? 0) != 0 }
    }

    private func evaluate() {
        let (active, users) = Self.currentState()
        let previous = apps
        let wasActive = isActive
        if users != apps { apps = users }
        if active != isActive { isActive = active }
        guard isPrimed else {
            isPrimed = true
            return
        }
        if active != wasActive {
            logger.info("microphone \(active ? "in use" : "idle", privacy: .public)")
            onChange(active, active ? users.first : previous.first)
        } else if active, let newcomer = users.first(where: { !previous.contains($0) }) {
            // 已經有 App 在錄音時又多一個
            onChange(true, newcomer)
        }
    }

    // MARK: - Core Audio

    private static var listAddress: AudioObjectPropertyAddress {
        if #available(macOS 14.2, *) {
            address(kAudioHardwarePropertyProcessObjectList)
        } else {
            address(kAudioHardwarePropertyDevices)
        }
    }

    private static var runningAddress: AudioObjectPropertyAddress {
        if #available(macOS 14.2, *) {
            address(kAudioProcessPropertyIsRunningInput)
        } else {
            address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        }
    }

    #if DEBUG
    /// 快照與「模擬事件」用：假裝有 App 正在錄音。
    func debugSetActive(_ active: Bool, apps: [SensorApp]) {
        isActive = active
        self.apps = active ? apps : []
    }
    #endif

    private static func watchedObjects() -> [AudioObjectID] {
        let ids = objectList(of: system, listAddress)
        // 舊系統只看「只有輸入」的裝置；同時有輸出的裝置（例如耳機）放音樂時也會是「執行中」
        return usesProcessList ? ids : ids.filter { hasStreams($0, kAudioObjectPropertyScopeInput) && !hasStreams($0, kAudioObjectPropertyScopeOutput) }
    }

    private static func currentState() -> (active: Bool, apps: [SensorApp]) {
        // 兩個屬性都是 UInt32；不寫明的話 0 會讓型別推斷成 Int，多讀 4 個沒初始化的位元組
        let running = watchedObjects().filter { (value(of: $0, runningAddress) as UInt32? ?? 0) != 0 }
        guard #available(macOS 14.2, *) else {
            return (!running.isEmpty, [])
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [SensorApp] = []
        var isActive = false
        for process in running {
            let pid: pid_t = value(of: process, address(kAudioProcessPropertyPID)) ?? -1
            guard pid != ownPID else { continue }
            isActive = true
            let bundleID = string(of: process, address(kAudioProcessPropertyBundleID))
            if let app = SensorApp.resolve(processIdentifier: pid, bundleIdentifier: bundleID), !apps.contains(where: { $0.name == app.name }) {
                apps.append(app)
            }
        }
        return (isActive, apps)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(of object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func string(of object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?, !string.isEmpty
        else { return nil }
        return string
    }

    private static func objectList(of object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasStreams(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }
}
