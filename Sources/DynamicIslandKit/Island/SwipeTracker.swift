import CoreGraphics
import Foundation

/// 觸控板捲動事件中我們需要的部分（從 NSEvent 取出，方便測試）。
struct ScrollSample {
    enum Phase {
        case began
        case changed
        case ended
        /// 一般滑鼠滾輪，沒有手勢階段。
        case none
    }

    /// 手指的移動方向（已經依「自然捲動」設定換算），往右為正。
    var fingerDX: CGFloat
    var fingerDY: CGFloat
    var phase: Phase
    /// 放開手指後的慣性捲動。
    var isMomentum: Bool
    /// 觸控板或 Magic Mouse（有精確的捲動量）。
    var isPrecise: Bool
    /// 內容該往哪裡捲（系統已經依「自然捲動」換算好），往下為正；滑鼠滾輪也適用。
    var contentDY: CGFloat = 0
}

/// 在島上左右滑動切歌：手指移動時回報位移讓內容跟著走，放開時決定要切歌還是彈回。
struct SwipeTracker {
    enum Direction {
        case next
        case previous
    }

    enum Update: Equatable {
        /// 手指還在滑，內容跟著移動（原始水平位移，往右為正）。
        case tracking(CGFloat)
        /// 放開時超過門檻：切歌。
        case commit(Direction)
        /// 放開時沒超過門檻：彈回原位。
        case cancel
    }

    /// 放開時水平位移超過這個值就切歌。
    static let threshold: CGFloat = 40
    /// 移動超過這個距離才決定是水平還是垂直手勢。
    static let axisLockDistance: CGFloat = 6

    private enum Axis {
        case undecided
        case horizontal
        case vertical
    }

    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var axis = Axis.undecided

    mutating func feed(_ sample: ScrollSample) -> Update? {
        guard sample.isPrecise, !sample.isMomentum else { return nil }
        switch sample.phase {
        case .began:
            reset()
            accumulate(sample)
            return trackingUpdate()
        case .changed:
            accumulate(sample)
            return trackingUpdate()
        case .ended:
            defer { reset() }
            guard axis == .horizontal else { return nil }
            guard abs(accumulatedX) >= Self.threshold else { return .cancel }
            // 手指往左滑 = 下一首（像翻到下一張），往右 = 上一首
            return .commit(accumulatedX < 0 ? .next : .previous)
        case .none:
            return nil
        }
    }

    mutating func reset() {
        accumulatedX = 0
        accumulatedY = 0
        axis = .undecided
    }

    /// 內容實際移動的距離：越拉越有阻力，最多約 90pt。
    static func rubberBand(_ offset: CGFloat) -> CGFloat {
        let limit: CGFloat = 90
        let damped = limit * (1 - exp(-abs(offset) * 0.8 / limit))
        return offset < 0 ? -damped : damped
    }

    private mutating func accumulate(_ sample: ScrollSample) {
        accumulatedX += sample.fingerDX
        accumulatedY += sample.fingerDY
        if axis == .undecided, abs(accumulatedX) + abs(accumulatedY) >= Self.axisLockDistance {
            axis = abs(accumulatedX) > abs(accumulatedY) * 1.2 ? .horizontal : .vertical
        }
    }

    private func trackingUpdate() -> Update? {
        axis == .horizontal ? .tracking(accumulatedX) : nil
    }
}
