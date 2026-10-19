import Testing
@testable import DynamicIslandKit

struct BatteryAlertTrackerTests {
    private func battery(_ level: Int, plugged: Bool = false, charged: Bool = false) -> BatteryState {
        BatteryState(level: level, isCharging: plugged && !charged, isPluggedIn: plugged, isCharged: charged)
    }

    @Test func firstReadingNeverAlerts() {
        var tracker = BatteryAlertTracker()
        #expect(tracker.update(with: battery(5)) == nil)
    }

    @Test func pluggingInShowsCharging() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(55))
        #expect(tracker.update(with: battery(55, plugged: true)) == .charging(level: 55))
        #expect(tracker.update(with: battery(56, plugged: true)) == nil)
    }

    @Test func lowBatteryAlertsOncePerThreshold() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(25))
        #expect(tracker.update(with: battery(21)) == nil)
        #expect(tracker.update(with: battery(20)) == .lowBattery(level: 20))
        #expect(tracker.update(with: battery(19)) == nil)
        #expect(tracker.update(with: battery(10)) == .lowBattery(level: 10))
        #expect(tracker.update(with: battery(9)) == nil)
    }

    @Test func droppingPastBothThresholdsAlertsOnce() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(30))
        #expect(tracker.update(with: battery(8)) == .lowBattery(level: 8))
        #expect(tracker.update(with: battery(7)) == nil)
    }

    @Test func chargingResetsLowBatteryAlerts() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(21))
        #expect(tracker.update(with: battery(20)) == .lowBattery(level: 20))
        _ = tracker.update(with: battery(20, plugged: true))
        _ = tracker.update(with: battery(22))
        #expect(tracker.update(with: battery(20)) == .lowBattery(level: 20))
    }

    @Test func fullChargeIsAnnouncedOnce() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(98, plugged: true))
        #expect(tracker.update(with: battery(100, plugged: true, charged: true)) == .fullyCharged)
        #expect(tracker.update(with: battery(100, plugged: true, charged: true)) == nil)
    }

    @Test func pluggingInWhenAlreadyFullDoesNotAlsoAnnounceFull() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(100))
        #expect(tracker.update(with: battery(100, plugged: true, charged: true)) == .charging(level: 100))
        #expect(tracker.update(with: battery(100, plugged: true, charged: true)) == nil)
    }

    @Test func unpluggingShowsTheBatteryLevel() {
        var tracker = BatteryAlertTracker()
        _ = tracker.update(with: battery(80, plugged: true))
        #expect(tracker.update(with: battery(80)) == .unplugged(level: 80))
        #expect(tracker.update(with: battery(79)) == nil)
    }
}
