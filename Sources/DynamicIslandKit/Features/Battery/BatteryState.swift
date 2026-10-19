import Foundation

/// 內建電池目前的狀態。
struct BatteryState: Equatable {
    /// 0–100。
    var level: Int
    /// 正在充電。
    var isCharging: Bool
    /// 接著電源（不一定在充電，例如已充飽或最佳化充電暫停中）。
    var isPluggedIn: Bool
    /// 系統認為已充飽。
    var isCharged: Bool
}

/// 決定什麼時候該跳出電池提示：插上電源、低電量（20%、10% 各一次）、充飽一次。
struct BatteryAlertTracker {
    static let lowThresholds = [20, 10]

    private var previous: BatteryState?
    private var alertedThresholds: Set<Int> = []
    private var announcedFull = false

    mutating func update(with state: BatteryState) -> IslandEvent.Kind? {
        defer { previous = state }
        // 第一次讀到電池狀態時不提示（App 剛啟動）
        guard let previous else {
            announcedFull = state.isCharged || state.level >= 100
            return nil
        }

        if state.isPluggedIn, !previous.isPluggedIn {
            alertedThresholds.removeAll()
            announcedFull = state.isCharged || state.level >= 100
            return .charging(level: state.level)
        }

        if previous.isPluggedIn, !state.isPluggedIn {
            announcedFull = false
            return .unplugged(level: state.level)
        }

        if state.isPluggedIn {
            if (state.isCharged || state.level >= 100), !announcedFull {
                announcedFull = true
                return .fullyCharged
            }
            return nil
        }

        // 用電池中
        announcedFull = false
        for threshold in Self.lowThresholds.sorted() where state.level <= threshold && !alertedThresholds.contains(threshold) {
            // 一次跌過好幾個門檻時只提示一次
            alertedThresholds.formUnion(Self.lowThresholds.filter { $0 >= threshold })
            return .lowBattery(level: state.level)
        }
        return nil
    }
}
