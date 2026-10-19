import Foundation

/// 藍牙耳機的電量（百分比），讀不到的欄位為 nil。
struct HeadphoneBattery: Equatable, Sendable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// 單一電池的裝置（例如 AirPods Max、一般耳機）。
    var main: Int?

    var isEmpty: Bool {
        left == nil && right == nil && caseLevel == nil && main == nil
    }
}

/// 連線／斷線事件中顯示的裝置資訊。
struct BluetoothDeviceSnapshot: Equatable, Sendable {
    var name: String
    /// 正規化成小寫、以冒號分隔的位址，例如 "a1:b2:c3:d4:e5:f6"。
    var address: String
    var symbolName: String
    var battery: HeadphoneBattery?
}
