import CoreGraphics
import Testing
@testable import IsletKit

struct NotchGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test func notchSizeComesFromTheUnobscuredMenuBarAreas() {
        let geometry = NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 32,
            topLeftArea: CGRect(x: 0, y: 924, width: 640, height: 32),
            topRightArea: CGRect(x: 830, y: 924, width: 640, height: 32),
            menuBarHeight: 33
        )
        #expect(geometry.hasPhysicalNotch)
        #expect(geometry.notchSize == CGSize(width: 190, height: 32))
        #expect(geometry.centerX == 735)
    }

    @Test func offCenterNotchUsesTheLeftAreaWidth() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: -1470, y: 0, width: 1470, height: 956),
            safeAreaTop: 32,
            topLeftArea: CGRect(x: -1470, y: 924, width: 600, height: 32),
            topRightArea: CGRect(x: -680, y: 924, width: 680, height: 32),
            menuBarHeight: 33
        )
        #expect(geometry.notchSize.width == 190)
        #expect(geometry.centerX == CGFloat(-1470 + 600 + 95))
    }

    @Test func screensWithoutANotchGetAFallbackPill() {
        let geometry = NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 0,
            topLeftArea: nil,
            topRightArea: nil,
            menuBarHeight: 24
        )
        #expect(!geometry.hasPhysicalNotch)
        #expect(geometry.notchSize == CGSize(width: NotchGeometry.fallbackSize.width, height: 24))
        #expect(geometry.centerX == screen.midX)
    }

    @Test func autoHiddenMenuBarFallsBackToTheDefaultHeight() {
        let geometry = NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 0,
            topLeftArea: nil,
            topRightArea: nil,
            menuBarHeight: 0
        )
        #expect(geometry.notchSize == NotchGeometry.fallbackSize)
    }

    @Test func islandRectHangsFromTheTopEdgeAroundTheNotchCenter() {
        let geometry = NotchGeometry(
            notchSize: CGSize(width: 190, height: 32),
            screenFrame: screen,
            centerX: 735,
            hasPhysicalNotch: true
        )
        let rect = geometry.islandRect(size: CGSize(width: 200, height: 40))
        #expect(rect == CGRect(x: 635, y: 916, width: 200, height: 40))
    }
}
