import AppKit
import QuartzCore

/// 修正 grouped Form 區塊邊框在 1x 螢幕上只剩右邊與下邊的問題。
///
/// 系統把每個區塊的邊框畫成 `borderWidth = 0.5` 的 CALayer（Retina 上剛好一個像素）。
/// 到了 1x 螢幕，Core Animation 會把半個像素寬的邊框對齊到整數像素，
/// 結果兩邊變成 1px、另外兩邊變成 0px。這裡把它改成剛好一個實體像素。
///
/// SwiftUI 在區塊內容改變時會把邊框重設回 0.5，所以每次 Core Animation 提交之後都要再檢查一次。
final class HairlineBorderFix {
    private static let systemHairline: CGFloat = 0.5

    private weak var window: NSWindow?
    private var observer: CFRunLoopObserver?
    /// 被改過的 layer，搬回 Retina 螢幕時要改回 0.5。
    private let adjusted = NSHashTable<CALayer>.weakObjects()

    init(window: NSWindow) {
        self.window = window
        // CA 的提交是在 beforeWaiting、order 2000000 做的，排在它後面才看得到 SwiftUI 剛設的值。
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 2_000_001) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    isolated deinit {
        if let observer { CFRunLoopObserverInvalidate(observer) }
    }

    private func apply() {
        guard let window, window.isVisible, let root = window.contentView?.layer else { return }
        let pixel = 1 / max(window.backingScaleFactor, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if pixel > Self.systemHairline {
            fix(root, pixel: pixel)
        } else {
            for layer in adjusted.allObjects where layer.borderWidth != Self.systemHairline {
                layer.borderWidth = Self.systemHairline
            }
            adjusted.removeAllObjects()
        }
        CATransaction.commit()
    }

    private func fix(_ layer: CALayer, pixel: CGFloat) {
        if layer.borderWidth == Self.systemHairline {
            layer.borderWidth = pixel
            adjusted.add(layer)
        }
        layer.sublayers?.forEach { fix($0, pixel: pixel) }
    }
}
