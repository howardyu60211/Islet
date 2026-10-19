import AppKit

/// 內建螢幕瀏海的位置與大小（AppKit 螢幕座標，原點在左下角）。
struct NotchGeometry: Equatable {
    /// 瀏海本體大小（pt）。
    var notchSize: CGSize
    /// 所在螢幕的 frame。
    var screenFrame: CGRect
    /// 瀏海中心的 x 座標。
    var centerX: CGFloat
    /// 螢幕真的有瀏海；否則是在頂端中央畫一個仿瀏海。
    var hasPhysicalNotch: Bool

    static let fallbackSize = CGSize(width: 185, height: 32)

    /// 瀏海寬 = 螢幕寬 − 左右兩塊「沒被遮住」的選單列區域；高 = safe area 頂部內縮。
    static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        topLeftArea: CGRect?,
        topRightArea: CGRect?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = topLeftArea, let right = topRightArea {
            let width = screenFrame.width - left.width - right.width
            if width > 0 {
                return NotchGeometry(
                    notchSize: CGSize(width: width, height: safeAreaTop),
                    screenFrame: screenFrame,
                    centerX: screenFrame.minX + left.width + width / 2,
                    hasPhysicalNotch: true
                )
            }
        }
        let height = menuBarHeight > 0 ? menuBarHeight : fallbackSize.height
        return NotchGeometry(
            notchSize: CGSize(width: fallbackSize.width, height: height),
            screenFrame: screenFrame,
            centerX: screenFrame.midX,
            hasPhysicalNotch: false
        )
    }

    /// 島的 frame 在螢幕座標中的位置：貼齊螢幕頂端、以瀏海為中心。
    func islandRect(size: CGSize) -> CGRect {
        CGRect(
            x: centerX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

extension NotchGeometry {
    init(screen: NSScreen) {
        self = .make(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            topLeftArea: screen.auxiliaryTopLeftArea,
            topRightArea: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// MacBook 內建螢幕；闔上螢幕只用外接時為 nil。
    static var builtIn: NSScreen? {
        screens.first(where: \.isBuiltIn)
    }
}
