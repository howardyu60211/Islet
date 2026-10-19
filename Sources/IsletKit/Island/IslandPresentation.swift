import CoreGraphics
import Foundation

/// 展開後上方的分頁。
enum IslandTab: String, CaseIterable, Identifiable {
    case media
    case shelf
    case clipboard
    case timer

    var id: Self { self }

    var title: String {
        switch self {
        case .media: tr("音樂", "Music")
        case .shelf: tr("暫存架", "Shelf")
        case .clipboard: tr("剪貼簿", "Clipboard")
        case .timer: tr("計時器", "Timer")
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .timer: "timer"
        }
    }
}

/// 短暫顯示幾秒的事件（插電、藍牙連線、計時結束、音量…）。
struct IslandEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case charging(level: Int)
        case unplugged(level: Int)
        case fullyCharged
        case lowBattery(level: Int)
        case bluetooth(device: BluetoothDeviceSnapshot, connected: Bool)
        case timerFinished(title: String, subtitle: String)
        /// 音量 0～100。
        case volume(level: Int, muted: Bool)
        case focus(FocusMode, active: Bool)
        /// 麥克風或螢幕錄影開始／停止使用。
        case sensor(Sensor, app: SensorApp?, active: Bool)
        /// 拷貝或剪下（剪貼簿分不出兩者）。
        case clipboard(ClipboardSummary)
    }

    /// 同一類事件只保留最新的一個。
    enum Category: Hashable {
        case power
        case bluetooth(address: String)
        case timer
        case volume
        case focus
        case sensor(Sensor)
        case clipboard
    }

    let id = UUID()
    let kind: Kind

    var duration: TimeInterval {
        switch kind {
        case .charging, .fullyCharged: 3
        case .unplugged: 2.5
        case .lowBattery, .bluetooth: 4
        case .timerFinished: 6
        case .volume: 1.5
        case .focus: 2.5
        case .sensor(_, _, let active): active ? 3 : 2
        case .clipboard: 1.6
        }
    }

    /// 只有馬上顯示才有意義的事件（音量、拷貝）：島正在顯示別的東西時直接丟掉，不排隊。
    var isTransient: Bool {
        switch kind {
        case .volume, .clipboard: true
        default: false
        }
    }

    var category: Category {
        switch kind {
        case .charging, .unplugged, .fullyCharged, .lowBattery: .power
        case .bluetooth(let device, _): .bluetooth(address: device.address)
        case .timerFinished: .timer
        case .volume: .volume
        case .focus: .focus
        case .sensor(let sensor, _, _): .sensor(sensor)
        case .clipboard: .clipboard
        }
    }

    /// 事件顯示中滑鼠移上去展開時，要直接切到的分頁。
    var relatedTab: IslandTab? {
        switch kind {
        case .timerFinished: .timer
        default: nil
        }
    }
}

/// 會一直持續的活動；兩個同時進行時可以並排顯示（左右各一個）。
enum LiveActivity: Equatable {
    case nowPlaying
    case timer
    /// 麥克風、螢幕錄影使用中（只會跟其他活動並排出現，不會單獨佔用島）。
    case sensors([Sensor])

    /// 並排時這一側需要的寬度。
    var sideWidth: CGFloat {
        switch self {
        case .nowPlaying: 58
        case .timer: 80
        case .sensors(let sensors): CGFloat(sensors.count) * 18 + 28
        }
    }

    var key: String {
        switch self {
        case .nowPlaying: "nowPlaying"
        case .timer: "timer"
        case .sensors(let sensors): "sensors-" + sensors.map(\.rawValue).joined(separator: "+")
        }
    }

    var isNowPlaying: Bool { self == .nowPlaying }
}

/// 收合時在瀏海左右兩側顯示的「即時活動」。
enum CompactActivity: Equatable {
    case nowPlaying
    case timer
    /// 兩個活動並排：左邊一個、右邊一個。
    case pair(LiveActivity, LiveActivity)
    case charging(level: Int)
    case unplugged(level: Int)
    case volume(level: Int, muted: Bool)
    case focus(FocusMode, active: Bool)
    case sensor(Sensor, app: SensorApp?, active: Bool)
    case clipboard(ClipboardSummary)

    /// 瀏海左右兩側各多出的寬度。
    var sideWidth: CGFloat {
        switch self {
        case .nowPlaying: 40
        case .timer: 66
        case .charging: 76
        case .unplugged: 84
        case .volume: 84
        // 英文的「Do Not Disturb」「Microphone」比中文長，兩側放寬一點
        case .focus, .sensor, .clipboard: AppLanguage.current == .english ? 100 : 84
        // 島對齊瀏海置中，所以兩側取比較寬的那個
        case .pair(let leading, let trailing): max(leading.sideWidth, trailing.sideWidth)
        }
    }

    var includesNowPlaying: Bool {
        switch self {
        case .nowPlaying: true
        case .pair(let leading, let trailing): leading.isNowPlaying || trailing.isNowPlaying
        default: false
        }
    }

    /// 內容不同時才做轉場；音量的 key 固定，連續調整時音量條原地變化。
    var key: String {
        switch self {
        case .nowPlaying: "nowPlaying"
        case .timer: "timer"
        case .charging: "charging"
        case .unplugged: "unplugged"
        case .volume: "volume"
        case .focus(let mode, let active): "focus-\(mode.identifier)-\(active)"
        case .sensor(let sensor, _, let active): "sensor-\(sensor.rawValue)-\(active)"
        // 每次拷貝都重新播一次進場動畫
        case .clipboard(let summary): "clipboard-\(summary.id)"
        case .pair(let leading, let trailing): "pair-\(leading.key)-\(trailing.key)"
        }
    }
}

/// 島目前的樣子。
enum IslandPresentation: Equatable {
    /// 跟瀏海一樣大，和實體瀏海融為一體。
    case idle
    /// 同瀏海高度，往兩側變寬。
    case compact(CompactActivity)
    /// 往下長高的短暫通知。
    case banner(IslandEvent)
    /// 滑鼠停留後的完整面板。
    case expanded

    /// 優先序：展開 > 短暫事件 > 常駐活動。
    /// 常駐活動只有一個時：計時器 > 音樂；同時有兩個時（且 pairsActivities）左右並排，
    /// 音樂固定在左邊（封面位置跟只有音樂時一樣），麥克風／螢幕錄影只會排在別的活動旁邊。
    static func resolve(
        isExpanded: Bool,
        event: IslandEvent?,
        timerActive: Bool,
        musicActive: Bool,
        activeSensors: [Sensor] = [],
        pairsActivities: Bool = true
    ) -> IslandPresentation {
        if isExpanded { return .expanded }
        if let event {
            switch event.kind {
            case .charging(let level): return .compact(.charging(level: level))
            case .unplugged(let level): return .compact(.unplugged(level: level))
            case .volume(let level, let muted): return .compact(.volume(level: level, muted: muted))
            case .focus(let mode, let active): return .compact(.focus(mode, active: active))
            case .sensor(let sensor, let app, let active): return .compact(.sensor(sensor, app: app, active: active))
            case .clipboard(let summary): return .compact(.clipboard(summary))
            default: break
            }
            return .banner(event)
        }
        if pairsActivities {
            var live: [LiveActivity] = []
            if musicActive { live.append(.nowPlaying) }
            if timerActive { live.append(.timer) }
            if !live.isEmpty, !activeSensors.isEmpty { live.append(.sensors(activeSensors)) }
            if live.count >= 2 { return .compact(.pair(live[0], live[1])) }
        }
        if timerActive { return .compact(.timer) }
        if musicActive { return .compact(.nowPlaying) }
        return .idle
    }

    /// 內容不同時才做轉場動畫。
    var contentKey: String {
        switch self {
        case .idle: "idle"
        case .compact(let activity): "compact-\(activity.key)"
        case .banner(let event): "banner-\(event.id)"
        case .expanded: "expanded"
        }
    }

    var isExpanded: Bool { self == .expanded }
}

/// 各種樣子的尺寸與圓角。
struct IslandMetrics: Equatable {
    /// 島本體（不含上方耳角）的大小。
    var bodySize: CGSize
    /// 上方內凹耳角的半徑；耳角會讓 frame 比本體左右各寬一個半徑。
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var frameSize: CGSize {
        CGSize(width: bodySize.width + topRadius * 2, height: bodySize.height)
    }

    static let expandedWidth: CGFloat = 600
    static let expandedContentHeight: CGFloat = 150
    static let bannerContentHeight: CGFloat = 54

    static func make(for presentation: IslandPresentation, notch: CGSize) -> IslandMetrics {
        switch presentation {
        case .idle:
            // 比實體瀏海略小，完全藏在瀏海後面，不會在選單列露出黑邊。
            IslandMetrics(
                bodySize: CGSize(width: notch.width - 4, height: notch.height - 1),
                topRadius: 4,
                bottomRadius: 9
            )
        case .compact(let activity):
            IslandMetrics(
                bodySize: CGSize(width: notch.width + activity.sideWidth * 2, height: notch.height),
                topRadius: 6,
                bottomRadius: 12
            )
        case .banner:
            IslandMetrics(
                bodySize: CGSize(width: max(notch.width + 170, 360), height: notch.height + bannerContentHeight),
                topRadius: 10,
                bottomRadius: 22
            )
        case .expanded:
            IslandMetrics(
                bodySize: CGSize(width: expandedWidth, height: notch.height + expandedContentHeight),
                topRadius: 14,
                bottomRadius: 26
            )
        }
    }
}
