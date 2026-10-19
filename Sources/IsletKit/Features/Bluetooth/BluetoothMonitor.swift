import CoreBluetooth
import Foundation
import IOBluetooth
import os

/// 用 IOBluetooth 的連線／斷線通知偵測藍牙耳機（第一次會詢問藍牙權限）。
final class BluetoothMonitor: NSObject, CBCentralManagerDelegate {
    /// 需要跳出提示時呼叫。
    var onEvent: (IslandEvent.Kind) -> Void = { _ in }

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var startDate = Date.distantFuture
    /// 只用來非同步地詢問藍牙權限。
    private var authorizationManager: CBCentralManager?
    private let logger = Logger(subsystem: "com.howardyu.Islet", category: "Bluetooth")

    /// App 啟動時系統會把已經連著的裝置都通知一次，這段時間內不提示。
    private static let launchQuietPeriod: TimeInterval = 3
    /// AirPods 剛連上時電量還讀不到，等一下再讀。
    private static let batteryDelay: Duration = .milliseconds(1500)

    func start() {
        guard connectNotification == nil, authorizationManager == nil else { return }
        // 沒有用途說明就存取藍牙會被系統終止（例如直接用 swift run 執行時）
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil else {
            logger.error("Info.plist 缺少 NSBluetoothAlwaysUsageDescription，不啟用藍牙提示")
            return
        }
        switch CBManager.authorization {
        case .allowedAlways:
            registerForNotifications()
        case .notDetermined:
            // IOBluetooth 問權限時會卡住主執行緒直到使用者回應；
            // 改用 CoreBluetooth 非同步地問，允許之後再註冊
            authorizationManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        default:
            logger.info("沒有藍牙權限，不啟用耳機提示")
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.authorizationManager != nil else { return }
                self.authorizationManager = nil
                if CBManager.authorization == .allowedAlways {
                    self.registerForNotifications()
                }
            }
        }
    }

    private func registerForNotifications() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        // 系統會把已經連著的裝置馬上通知一次，從註冊完成後開始算安靜期
        startDate = Date()
    }

    func stop() {
        authorizationManager = nil
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    // IOBluetooth 會在不同的執行緒呼叫這兩個 callback（註冊時同步呼叫、之後在背景執行緒），
    // 所以先轉回主執行緒再碰任何狀態，不然同時改字典會壞掉。

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let device = UncheckedSendable(device)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handleConnected(device.value) }
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let notification = UncheckedSendable(notification)
        let device = UncheckedSendable(device)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handleDisconnected(device.value, notification: notification.value) }
        }
    }

    private func handleConnected(_ device: IOBluetoothDevice) {
        guard connectNotification != nil, let rawAddress = device.addressString else { return }
        let address = normalizeBluetoothAddress(rawAddress)
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )

        guard Date().timeIntervalSince(startDate) > Self.launchQuietPeriod, isHeadphone(device) else { return }
        let snapshot = makeSnapshot(of: device, address: address)
        logger.info("headphones connected: \(snapshot.name, privacy: .public)")
        Task { [weak self] in
            try? await Task.sleep(for: Self.batteryDelay)
            var withBattery = snapshot
            withBattery.battery = await BluetoothBatteryReader.read(address: address)
            self?.onEvent(.bluetooth(device: withBattery, connected: true))
        }
    }

    private func handleDisconnected(_ device: IOBluetoothDevice, notification: IOBluetoothUserNotification) {
        notification.unregister()
        guard let rawAddress = device.addressString else { return }
        let address = normalizeBluetoothAddress(rawAddress)
        disconnectNotifications[address] = nil
        guard connectNotification != nil, isHeadphone(device) else { return }
        logger.info("headphones disconnected")
        onEvent(.bluetooth(device: makeSnapshot(of: device, address: address), connected: false))
    }

    private func isHeadphone(_ device: IOBluetoothDevice) -> Bool {
        if Int(device.deviceClassMajor) == kBluetoothDeviceClassMajorAudio {
            return true
        }
        let name = (device.name ?? "").lowercased()
        return name.contains("airpods") || name.contains("beats")
    }

    private func makeSnapshot(of device: IOBluetoothDevice, address: String) -> BluetoothDeviceSnapshot {
        let name = device.name ?? tr("藍牙耳機", "Bluetooth Headphones")
        return BluetoothDeviceSnapshot(
            name: name,
            address: address,
            symbolName: HeadphoneSymbol.name(forDeviceNamed: name),
            battery: nil
        )
    }
}

/// 把非 Sendable 的 IOBluetooth 物件帶回主執行緒用（只在主執行緒上使用它）。
private nonisolated struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
