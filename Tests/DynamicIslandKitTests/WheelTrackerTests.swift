import CoreGraphics
import Testing
@testable import DynamicIslandKit

struct WheelTrackerTests {
    private func trackpad(_ contentDY: CGFloat, phase: ScrollSample.Phase = .changed) -> ScrollSample {
        ScrollSample(fingerDX: 0, fingerDY: 0, phase: phase, isMomentum: false, isPrecise: true, contentDY: contentDY)
    }

    private func mouseWheel(_ contentDY: CGFloat) -> ScrollSample {
        ScrollSample(fingerDX: 0, fingerDY: 0, phase: .none, isMomentum: false, isPrecise: false, contentDY: contentDY)
    }

    @Test func trackpadFollowsTheFingerAndSnapsToTheNearestRow() {
        var wheel = WheelTracker()
        // 內容往上捲 1.6 列 → 轉到後面的項目
        let snapsNow = wheel.feed(trackpad(-WheelTracker.rowHeight * 1.6), count: 5, speed: 1)
        #expect(!snapsNow)
        #expect(wheel.index(count: 5) == 2)
        wheel.snap(count: 5)
        #expect(wheel.position == 2)
    }

    @Test func slowerSpeedNeedsALongerSwipePerRow() {
        var slow = WheelTracker()
        _ = slow.feed(trackpad(-WheelTracker.rowHeight * 2), count: 10, speed: 0.25)
        #expect(slow.index(count: 10) == 1)
        // 慣性捲動再打折
        var momentum = WheelTracker()
        let flick = ScrollSample(fingerDX: 0, fingerDY: 0, phase: .none, isMomentum: true, isPrecise: true, contentDY: -WheelTracker.rowHeight * 4)
        _ = momentum.feed(flick, count: 10, speed: 1)
        #expect(momentum.position == 4 * WheelTracker.momentumFactor)
    }

    @Test func arrowKeysAreRecognized() {
        #expect(IslandKey(keyCode: 126) == .up)
        #expect(IslandKey(keyCode: 125) == .down)
        #expect(IslandKey(keyCode: 36) == .return)
        #expect(IslandKey(keyCode: 53) == .escape)
        #expect(IslandKey(keyCode: 0) == nil)
    }

    @Test func overscrollIsDampedAndSnapsBack() {
        var wheel = WheelTracker()
        _ = wheel.feed(trackpad(WheelTracker.rowHeight * 5), count: 3)
        #expect(wheel.position >= -WheelTracker.overscroll)
        #expect(wheel.position < 0)
        #expect(wheel.index(count: 3) == 0)
        wheel.snap(count: 3)
        #expect(wheel.position == 0)
    }

    @Test func mouseWheelStepsOneRowAtATime() {
        var wheel = WheelTracker()
        let down = wheel.feed(mouseWheel(-3), count: 4)
        #expect(down)
        #expect(wheel.position == 1)
        let up = wheel.feed(mouseWheel(2), count: 4)
        #expect(up)
        #expect(wheel.position == 0)
        // 已經在第一列，不會再往上
        _ = wheel.feed(mouseWheel(2), count: 4)
        #expect(wheel.position == 0)
    }

    @Test func selectionIsClampedToTheItems() {
        var wheel = WheelTracker()
        wheel.select(10, count: 3)
        #expect(wheel.index(count: 3) == 2)
        #expect(wheel.index(count: 0) == 0)
    }
}
