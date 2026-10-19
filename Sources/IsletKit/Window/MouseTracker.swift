import AppKit

/// 用 NSEvent 全域＋本地監聽追蹤游標（只監聽滑鼠事件，不需要「輔助使用」權限）。
/// 全域監聽收得到送往其他 App 的事件，本地監聽收得到送往本 App 的事件，兩邊一起才不會漏。
final class MouseTracker {
    enum Kind {
        case moved
        case down
        case dragged
        case up
    }

    var handler: ((Kind, CGPoint) -> Void)?
    /// 游標在本 App 的視窗上時的捲動事件（用來在島上滑動切歌）。
    var scrollHandler: ((ScrollSample, CGPoint) -> Void)?

    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.dispatch(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.dispatch(type) }
            return event
        }) {
            monitors.append(local)
        }
        // 捲動只需要本地監聽：游標在島上時面板才接收滑鼠事件
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let sample = Self.sample(from: event)
            MainActor.assumeIsolated {
                self?.scrollHandler?(sample, NSEvent.mouseLocation)
            }
            return event
        }) {
            monitors.append(scroll)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private nonisolated static func sample(from event: NSEvent) -> ScrollSample {
        // 開了「自然捲動」時，scrollingDelta 的方向就是手指移動的方向
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let phase: ScrollSample.Phase = if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            .began
        } else if event.phase.contains(.changed) {
            .changed
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            .ended
        } else {
            .none
        }
        return ScrollSample(
            fingerDX: event.scrollingDeltaX * sign,
            fingerDY: event.scrollingDeltaY * sign,
            phase: phase,
            isMomentum: !event.momentumPhase.isEmpty,
            isPrecise: event.hasPreciseScrollingDeltas,
            contentDY: event.scrollingDeltaY
        )
    }

    private func dispatch(_ type: NSEvent.EventType) {
        let kind: Kind = switch type {
        case .leftMouseDown: .down
        case .leftMouseDragged: .dragged
        case .leftMouseUp: .up
        default: .moved
        }
        handler?(kind, NSEvent.mouseLocation)
    }
}
