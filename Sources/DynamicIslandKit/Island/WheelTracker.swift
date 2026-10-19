import CoreGraphics

/// 島上會處理的按鍵。
enum IslandKey {
    case up
    case down
    case `return`
    case escape

    init?(keyCode: UInt16) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .return
        case 53: self = .escape
        default: return nil
        }
    }
}

/// 剪貼簿的滾輪（像計時器的轉盤）：觸控板上下滑動時跟著手指轉，停下來後對齊最近的一列。
struct WheelTracker: Equatable {
    /// 展開後內容區約 126pt 高，24pt 一列剛好放得下 5 列（選到的那筆上下各 2 筆）。
    static let rowHeight: CGFloat = 24
    /// 超出第一列／最後一列時最多還能再拉多遠（以列為單位）。
    static let overscroll: CGFloat = 0.6
    /// 速度設定的範圍與預設值：1 表示手指移動一列高（24pt）就跳一列。
    static let speedRange: ClosedRange<Double> = 0.15...1
    static let defaultSpeed = 0.4
    /// 放開手指後的慣性捲動再打個折，不然輕輕一撥就轉到底。
    static let momentumFactor: CGFloat = 0.5

    /// 目前轉到的位置（以列為單位，可以是小數；0 是第一列）。
    private(set) var position: CGFloat = 0

    /// 現在對在中間的那一列。
    func index(count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int(position.rounded()), 0), count - 1)
    }

    /// 餵一筆捲動事件；speed 是設定裡的滾輪速度。回傳 true 表示要馬上對齊（滑鼠滾輪：一格跳一列）。
    mutating func feed(_ sample: ScrollSample, count: Int, speed: Double = defaultSpeed) -> Bool {
        guard count > 0, sample.contentDY != 0 else { return false }
        guard sample.isPrecise else {
            // 內容往下移（contentDY > 0）＝ 轉到上面一列
            position = CGFloat(index(count: count) + (sample.contentDY > 0 ? -1 : 1))
            position = min(max(position, 0), CGFloat(count - 1))
            return true
        }
        let upper = CGFloat(count - 1)
        var delta = -sample.contentDY / Self.rowHeight * CGFloat(speed)
        if sample.isMomentum { delta *= Self.momentumFactor }
        // 超出頭尾時有阻力
        if position < 0 || position > upper { delta *= 0.3 }
        position = min(max(position + delta, -Self.overscroll), upper + Self.overscroll)
        return false
    }

    /// 對齊最近的一列。
    mutating func snap(count: Int) {
        position = CGFloat(index(count: count))
    }

    mutating func select(_ index: Int, count: Int) {
        position = CGFloat(min(max(index, 0), max(count - 1, 0)))
    }
}
