import Foundation
import Observation

enum ExpandMode: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: Self { self }

    var title: String {
        switch self {
        case .hover: tr("滑鼠停留", "Hover")
        case .click: tr("點擊", "Click")
        }
    }
}

/// 所有使用者設定，存在 UserDefaults；是 @Observable，所以島和設定視窗會即時反映變更。
@Observable
final class Preferences {
    enum Key {
        static let expandMode = "expandMode"
        static let hoverDelay = "hoverDelay"
        static let hapticFeedback = "hapticFeedback"
        static let islandHidden = "islandHidden"
        static let menuBarIconHidden = "menuBarIconHidden"
        static let pairActivities = "pairActivities"
        static let musicEnabled = "musicEnabled"
        static let musicCompactEnabled = "musicCompactEnabled"
        static let batteryAlertsEnabled = "batteryAlertsEnabled"
        static let shelfEnabled = "shelfEnabled"
        static let timerEnabled = "timerEnabled"
        static let bluetoothAlertsEnabled = "bluetoothAlertsEnabled"
        static let focusAlertsEnabled = "focusAlertsEnabled"
        static let volumeAlertsEnabled = "volumeAlertsEnabled"
        static let microphoneIndicatorEnabled = "microphoneIndicatorEnabled"
        static let screenRecordingIndicatorEnabled = "screenRecordingIndicatorEnabled"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardAlertsEnabled = "clipboardAlertsEnabled"
        static let clipboardWheelSpeed = "clipboardWheelSpeed"
        static let clipboardHistoryLimit = "clipboardHistoryLimit"
        static let focusMinutes = "pomodoroFocusMinutes"
        static let shortBreakMinutes = "pomodoroShortBreakMinutes"
        static let longBreakMinutes = "pomodoroLongBreakMinutes"
        static let longBreakInterval = "pomodoroLongBreakInterval"
        static let pomodoroAutoStart = "pomodoroAutoStart"
        static let pomodoroRounds = "pomodoroRounds"
        static let timerSound = "timerSound"
        static let timerPausesMusic = "timerPausesMusic"
    }

    /// 任何設定變更後呼叫（參數是 Key），讓 AppServices 開關對應的功能。
    @ObservationIgnored var onChange: (String) -> Void = { _ in }
    @ObservationIgnored private let defaults: UserDefaults

    // 一般
    var expandMode: ExpandMode { didSet { save(expandMode.rawValue, Key.expandMode) } }
    var hoverDelay: Double { didSet { save(hoverDelay, Key.hoverDelay) } }
    var hapticFeedback: Bool { didSet { save(hapticFeedback, Key.hapticFeedback) } }
    var islandHidden: Bool { didSet { save(islandHidden, Key.islandHidden) } }
    /// 不在選單列放膠囊圖示；設定從島的齒輪按鈕或重新打開 App 進入。
    var menuBarIconHidden: Bool { didSet { save(menuBarIconHidden, Key.menuBarIconHidden) } }
    /// 兩個活動同時進行（音樂＋計時器、音樂＋麥克風…）時左右並排顯示。
    var pairActivities: Bool { didSet { save(pairActivities, Key.pairActivities) } }

    // 功能開關
    var musicEnabled: Bool { didSet { save(musicEnabled, Key.musicEnabled) } }
    var musicCompactEnabled: Bool { didSet { save(musicCompactEnabled, Key.musicCompactEnabled) } }
    var batteryAlertsEnabled: Bool { didSet { save(batteryAlertsEnabled, Key.batteryAlertsEnabled) } }
    var shelfEnabled: Bool { didSet { save(shelfEnabled, Key.shelfEnabled) } }
    var timerEnabled: Bool { didSet { save(timerEnabled, Key.timerEnabled) } }
    var bluetoothAlertsEnabled: Bool { didSet { save(bluetoothAlertsEnabled, Key.bluetoothAlertsEnabled) } }
    var focusAlertsEnabled: Bool { didSet { save(focusAlertsEnabled, Key.focusAlertsEnabled) } }
    var volumeAlertsEnabled: Bool { didSet { save(volumeAlertsEnabled, Key.volumeAlertsEnabled) } }
    var microphoneIndicatorEnabled: Bool { didSet { save(microphoneIndicatorEnabled, Key.microphoneIndicatorEnabled) } }
    var screenRecordingIndicatorEnabled: Bool { didSet { save(screenRecordingIndicatorEnabled, Key.screenRecordingIndicatorEnabled) } }
    var clipboardEnabled: Bool { didSet { save(clipboardEnabled, Key.clipboardEnabled) } }
    var clipboardAlertsEnabled: Bool { didSet { save(clipboardAlertsEnabled, Key.clipboardAlertsEnabled) } }
    /// 觸控板轉剪貼簿滾輪的速度（見 WheelTracker.speedRange）。
    var clipboardWheelSpeed: Double { didSet { save(clipboardWheelSpeed, Key.clipboardWheelSpeed) } }
    /// 剪貼簿最多保留幾筆（不含釘選的，見 ClipboardModel.historyLimits）。
    var clipboardHistoryLimit: Int { didSet { save(clipboardHistoryLimit, Key.clipboardHistoryLimit) } }

    // 番茄鐘（分鐘）
    var focusMinutes: Int { didSet { save(focusMinutes, Key.focusMinutes) } }
    var shortBreakMinutes: Int { didSet { save(shortBreakMinutes, Key.shortBreakMinutes) } }
    var longBreakMinutes: Int { didSet { save(longBreakMinutes, Key.longBreakMinutes) } }
    /// 每幾輪專注後來一次長休息。
    var longBreakInterval: Int { didSet { save(longBreakInterval, Key.longBreakInterval) } }
    var pomodoroAutoStart: Bool { didSet { save(pomodoroAutoStart, Key.pomodoroAutoStart) } }
    /// 總共要做幾輪專注，做完就停。
    var pomodoroRounds: Int { didSet { save(pomodoroRounds, Key.pomodoroRounds) } }

    // 計時結束提示
    /// /System/Library/Sounds 裡的音效名稱。
    var timerSound: String { didSet { save(timerSound, Key.timerSound) } }
    /// 提示音響的時候先暫停正在播的音樂，響完再繼續。
    var timerPausesMusic: Bool { didSet { save(timerPausesMusic, Key.timerPausesMusic) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        expandMode = ExpandMode(rawValue: defaults.string(forKey: Key.expandMode) ?? "") ?? .hover
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.15
        hapticFeedback = defaults.object(forKey: Key.hapticFeedback) as? Bool ?? true
        islandHidden = defaults.object(forKey: Key.islandHidden) as? Bool ?? false
        menuBarIconHidden = defaults.object(forKey: Key.menuBarIconHidden) as? Bool ?? false
        pairActivities = defaults.object(forKey: Key.pairActivities) as? Bool ?? true

        musicEnabled = defaults.object(forKey: Key.musicEnabled) as? Bool ?? true
        musicCompactEnabled = defaults.object(forKey: Key.musicCompactEnabled) as? Bool ?? true
        batteryAlertsEnabled = defaults.object(forKey: Key.batteryAlertsEnabled) as? Bool ?? true
        shelfEnabled = defaults.object(forKey: Key.shelfEnabled) as? Bool ?? true
        timerEnabled = defaults.object(forKey: Key.timerEnabled) as? Bool ?? true
        bluetoothAlertsEnabled = defaults.object(forKey: Key.bluetoothAlertsEnabled) as? Bool ?? true
        focusAlertsEnabled = defaults.object(forKey: Key.focusAlertsEnabled) as? Bool ?? true
        volumeAlertsEnabled = defaults.object(forKey: Key.volumeAlertsEnabled) as? Bool ?? true
        microphoneIndicatorEnabled = defaults.object(forKey: Key.microphoneIndicatorEnabled) as? Bool ?? true
        screenRecordingIndicatorEnabled = defaults.object(forKey: Key.screenRecordingIndicatorEnabled) as? Bool ?? true
        clipboardEnabled = defaults.object(forKey: Key.clipboardEnabled) as? Bool ?? true
        clipboardAlertsEnabled = defaults.object(forKey: Key.clipboardAlertsEnabled) as? Bool ?? true
        clipboardWheelSpeed = defaults.object(forKey: Key.clipboardWheelSpeed) as? Double ?? WheelTracker.defaultSpeed
        clipboardHistoryLimit = defaults.object(forKey: Key.clipboardHistoryLimit) as? Int ?? ClipboardModel.defaultHistoryLimit

        focusMinutes = defaults.object(forKey: Key.focusMinutes) as? Int ?? 25
        shortBreakMinutes = defaults.object(forKey: Key.shortBreakMinutes) as? Int ?? 5
        longBreakMinutes = defaults.object(forKey: Key.longBreakMinutes) as? Int ?? 15
        longBreakInterval = defaults.object(forKey: Key.longBreakInterval) as? Int ?? 4
        pomodoroAutoStart = defaults.object(forKey: Key.pomodoroAutoStart) as? Bool ?? false
        pomodoroRounds = defaults.object(forKey: Key.pomodoroRounds) as? Int ?? 4
        timerSound = defaults.string(forKey: Key.timerSound) ?? "Hero"
        timerPausesMusic = defaults.object(forKey: Key.timerPausesMusic) as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange(key)
    }
}
