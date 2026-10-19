import CoreGraphics
import Testing
@testable import IsletKit

struct SwipeTrackerTests {
    private func sample(_ dx: CGFloat, _ dy: CGFloat = 0, _ phase: ScrollSample.Phase = .changed, momentum: Bool = false, precise: Bool = true) -> ScrollSample {
        ScrollSample(fingerDX: dx, fingerDY: dy, phase: phase, isMomentum: momentum, isPrecise: precise)
    }

    @Test func contentFollowsTheFingerThenCommitsOnRelease() {
        var tracker = SwipeTracker()
        #expect(tracker.feed(sample(-10, 0, .began)) == .tracking(-10))
        #expect(tracker.feed(sample(-25)) == .tracking(-35))
        #expect(tracker.feed(sample(-20)) == .tracking(-55))
        // 手指還沒放開前不會切歌
        #expect(tracker.feed(sample(0, 0, .ended)) == .commit(.next))
    }

    @Test func swipingRightGoesBack() {
        var tracker = SwipeTracker()
        _ = tracker.feed(sample(30, 0, .began))
        _ = tracker.feed(sample(20))
        #expect(tracker.feed(sample(0, 0, .ended)) == .commit(.previous))
    }

    @Test func shortSwipesSpringBack() {
        var tracker = SwipeTracker()
        _ = tracker.feed(sample(-15, 0, .began))
        #expect(tracker.feed(sample(0, 0, .ended)) == .cancel)
    }

    @Test func verticalScrollingIsIgnoredForTheWholeGesture() {
        var tracker = SwipeTracker()
        #expect(tracker.feed(sample(-2, -10, .began)) == nil)
        // 後來變水平也不算，因為一開始已經判定是垂直
        #expect(tracker.feed(sample(-80, 0)) == nil)
        #expect(tracker.feed(sample(0, 0, .ended)) == nil)
    }

    @Test func momentumAndMouseWheelsAreIgnored() {
        var tracker = SwipeTracker()
        #expect(tracker.feed(sample(-100, 0, .changed, momentum: true)) == nil)
        #expect(tracker.feed(sample(-100, 0, .none, precise: false)) == nil)
    }

    @Test func rubberBandAddsResistanceAndKeepsDirection() {
        #expect(SwipeTracker.rubberBand(0) == 0)
        #expect(SwipeTracker.rubberBand(-40) < 0)
        #expect(abs(SwipeTracker.rubberBand(500)) < 90)
        #expect(SwipeTracker.rubberBand(20) < SwipeTracker.rubberBand(60))
    }
}
