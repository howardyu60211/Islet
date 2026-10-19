import AppKit

/// 藍牙位址統一成小寫、冒號分隔（IOBluetooth 用 "aa-bb-…"，system_profiler 用 "AA:BB:…"）。
func normalizeBluetoothAddress(_ address: String) -> String {
    address.lowercased().replacingOccurrences(of: "-", with: ":")
}

enum HeadphoneSymbol {
    /// 依裝置名稱挑 SF Symbol；系統沒有這個符號就用一般耳機。
    static func name(forDeviceNamed deviceName: String) -> String {
        let lower = deviceName.lowercased()
        let candidate = if lower.contains("airpods max") {
            "airpods.max"
        } else if lower.contains("airpods pro") {
            "airpods.pro"
        } else if lower.contains("airpods") {
            "airpods"
        } else if lower.contains("beats") {
            "beats.headphones"
        } else {
            "headphones"
        }
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil ? candidate : "headphones"
    }
}

/// 從 `system_profiler SPBluetoothDataType -json` 讀耳機電量（公開工具；AirPods 左右耳、充電盒）。
enum BluetoothBatteryReader {
    static func read(address: String) async -> HeadphoneBattery? {
        guard let output = await ProcessRunner.output(
            URL(fileURLWithPath: "/usr/sbin/system_profiler"),
            arguments: ["-timeout", "10", "SPBluetoothDataType", "-json"]
        ) else { return nil }
        return parse(output, address: address)
    }

    static func parse(_ json: Data, address: String) -> HeadphoneBattery? {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }
        let target = normalizeBluetoothAddress(address)
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for case let properties as [String: Any] in entry.values {
                    guard let deviceAddress = properties["device_address"] as? String,
                          normalizeBluetoothAddress(deviceAddress) == target
                    else { continue }
                    let battery = HeadphoneBattery(
                        left: percent(properties["device_batteryLevelLeft"]),
                        right: percent(properties["device_batteryLevelRight"]),
                        caseLevel: percent(properties["device_batteryLevelCase"]),
                        main: percent(properties["device_batteryLevelMain"])
                    )
                    return battery.isEmpty ? nil : battery
                }
            }
        }
        return nil
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}
