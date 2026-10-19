import Foundation
import Testing
@testable import DynamicIslandKit

/// 可以手動推進的假時鐘。
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

struct TimerModelTests {
    // 這裡檢查的是中文字串，不管跑測試的電腦是什麼語言。
    init() { AppLanguage.current = .traditionalChinese }

    private func makeModel(autoStart: Bool = false) -> (TimerModel, FakeClock, Preferences) {
        let defaults = UserDefaults(suiteName: "DynamicIslandTests-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.pomodoroAutoStart = autoStart
        let clock = FakeClock()
        let model = TimerModel(preferences: preferences, now: { clock.now })
        return (model, clock, preferences)
    }

    @Test func countdownRunsPausesAndResumes() {
        let (model, clock, _) = makeModel()
        model.setCountdown(minutes: 10)
        #expect(model.remaining(at: clock.now) == 600)
        #expect(!model.isActive)

        model.start()
        clock.advance(90)
        #expect(model.remaining(at: clock.now) == 510)
        #expect(model.isRunning)

        model.pause()
        clock.advance(1000)
        #expect(model.remaining(at: clock.now) == 510)
        #expect(model.isActive)

        model.start()
        clock.advance(10)
        #expect(model.remaining(at: clock.now) == 500)
    }

    @Test func finishingACountdownPostsAnEventAndGoesIdle() {
        let (model, _, _) = makeModel()
        var events: [IslandEvent.Kind] = []
        model.onFinished = { events.append($0) }
        model.setCountdown(minutes: 5)
        model.start()
        model.finish()
        #expect(events == [.timerFinished(title: "時間到！", subtitle: "5 分鐘計時結束")])
        #expect(model.runState == .idle)
        #expect(model.duration == 300)
    }

    @Test func countdownMinutesAreClamped() {
        let (model, _, _) = makeModel()
        model.setCountdown(minutes: 1)
        model.adjustCountdown(by: -1)
        #expect(model.countdownMinutes == 1)
        model.setCountdown(minutes: 500)
        #expect(model.countdownMinutes == 180)
    }

    @Test func pomodoroAlternatesFocusAndBreaksWithALongBreakEveryFourSessions() {
        let (model, _, preferences) = makeModel()
        preferences.pomodoroRounds = 8
        model.setMode(.pomodoro)
        #expect(model.phase == .focus)
        #expect(model.duration == TimeInterval(preferences.focusMinutes * 60))

        var phases: [TimerModel.Phase] = []
        for _ in 0..<8 {
            model.finish()
            phases.append(model.phase)
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        // 長休息後繼續累計，直到做完設定的輪數
        #expect(model.completedFocusSessions == 4)
    }

    @Test func pomodoroStopsAfterTheConfiguredRounds() {
        let (model, _, preferences) = makeModel(autoStart: true)
        preferences.pomodoroRounds = 2
        var events: [IslandEvent.Kind] = []
        model.onFinished = { events.append($0) }
        model.setMode(.pomodoro)
        model.finish() // 第 1 輪專注 → 短休息
        model.finish() // 短休息 → 第 2 輪專注
        model.finish() // 第 2 輪專注結束 → 全部完成
        #expect(events.last == .timerFinished(title: "番茄鐘完成！", subtitle: "完成 2 輪專注，好好休息吧"))
        #expect(model.phase == .focus)
        #expect(model.runState == .idle)
        #expect(model.completedFocusSessions == 0)
    }

    @Test func finishingFocusSuggestsTheBreak() {
        let (model, _, _) = makeModel()
        var events: [IslandEvent.Kind] = []
        model.onFinished = { events.append($0) }
        model.setMode(.pomodoro)
        model.finish()
        #expect(events == [.timerFinished(title: "專注時間結束", subtitle: "短休息 5 分鐘吧")])
        #expect(model.runState == .idle)
    }

    @Test func autoStartBeginsTheNextPhase() {
        let (model, _, _) = makeModel(autoStart: true)
        model.setMode(.pomodoro)
        model.finish()
        #expect(model.phase == .shortBreak)
        #expect(model.isRunning)
    }

    @Test func skippingDoesNotCountAsAFocusSession() {
        let (model, _, _) = makeModel()
        model.setMode(.pomodoro)
        model.skipPhase()
        #expect(model.phase == .shortBreak)
        #expect(model.completedFocusSessions == 0)
    }

    @Test func scheduleHandlesCustomIntervals() {
        #expect(PomodoroSchedule.phase(after: .focus, completedFocusSessions: 2, longBreakInterval: 2) == .longBreak)
        #expect(PomodoroSchedule.phase(after: .focus, completedFocusSessions: 1, longBreakInterval: 2) == .shortBreak)
        #expect(PomodoroSchedule.phase(after: .longBreak, completedFocusSessions: 2, longBreakInterval: 2) == .focus)
    }

    @Test func countdownDisplayRoundsUp() {
        #expect(formatCountdown(299.2) == "5:00")
        #expect(formatCountdown(0.4) == "0:01")
        #expect(formatCountdown(0) == "0:00")
    }
}
