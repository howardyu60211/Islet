import Foundation
import Testing
@testable import IsletKit

/// 可以手動推進的假時鐘。
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

struct TimerModelTests {
    // 這裡檢查的是中文字串，不管跑測試的電腦是什麼語言。
    init() { AppLanguage.current = .traditionalChinese }

    private func makeModel(autoStart: Bool = false) -> (TimerModel, FakeClock, Preferences) {
        let defaults = UserDefaults(suiteName: "IsletTests-\(UUID().uuidString)")!
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
        #expect(model.clock(.countdown).duration == 300)
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
        model.setMode(.pomodoro)
        #expect(model.phase == .focus)
        #expect(model.clock(.pomodoro).duration == TimeInterval(preferences.focusMinutes * 60))

        var phases: [TimerModel.Phase] = []
        for _ in 0..<8 {
            model.finish()
            phases.append(model.phase)
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        #expect(model.completedFocusSessions == 4)
    }

    @Test func pomodoroKeepsCountingRoundsWithoutStopping() {
        let (model, _, _) = makeModel()
        var events: [IslandEvent.Kind] = []
        model.onFinished = { events.append($0) }
        model.setMode(.pomodoro)
        for _ in 0..<40 { model.finish() } // 20 輪專注 + 20 次休息
        #expect(model.phase == .focus)
        #expect(model.currentRound == 21)
        #expect(model.completedFocusSessions == 20)
        #expect(events.last == .timerFinished(title: "休息結束", subtitle: "開始下一輪專注"))
    }

    @Test func autoContinueControlsWhetherTheNextPhaseStarts() {
        let (model, _, preferences) = makeModel()
        model.setMode(.pomodoro)
        model.start()
        model.finish()
        #expect(model.phase == .shortBreak)
        #expect(model.runState == .idle)

        preferences.pomodoroAutoStart = true
        model.start()
        model.finish()
        #expect(model.phase == .focus)
        #expect(model.isRunning)
    }

    @Test func switchingModesKeepsThePomodoroWhereItWas() {
        let (model, _, _) = makeModel()
        model.setMode(.pomodoro)
        model.finish()
        #expect(Step(model.phase, model.currentRound) == Step(.shortBreak, 1))
        model.setMode(.countdown)
        model.setMode(.pomodoro)
        #expect(Step(model.phase, model.currentRound) == Step(.shortBreak, 1))
    }

    @Test func countdownAndPomodoroRunAtTheSameTime() {
        let (model, clock, preferences) = makeModel()
        model.setMode(.pomodoro)
        model.start()
        clock.advance(60)

        model.setCountdown(minutes: 5) // 切到計時器
        model.start()
        clock.advance(60)

        #expect(model.mode == .countdown)
        #expect(model.clock(.countdown).isRunning)
        #expect(model.clock(.countdown).remaining(at: clock.now) == 240)
        #expect(model.clock(.pomodoro).isRunning)
        #expect(model.clock(.pomodoro).remaining(at: clock.now) == TimeInterval(preferences.focusMinutes * 60 - 120))
        #expect(model.isActiveInBackground(.pomodoro))

        // 暫停／時間到只影響自己那一個
        model.pause()
        #expect(!model.clock(.countdown).isRunning)
        #expect(model.clock(.pomodoro).isRunning)
        model.finish(.countdown)
        #expect(model.clock(.countdown).runState == .idle)
        #expect(model.clock(.pomodoro).isRunning)
        #expect(model.clock(.pomodoro).phase == .focus)
    }

    @Test func pomodoroFinishesInTheBackgroundWithoutTouchingTheCountdown() {
        let (model, clock, _) = makeModel()
        var events: [IslandEvent.Kind] = []
        model.onFinished = { events.append($0) }
        model.setMode(.pomodoro)
        model.start()
        model.setCountdown(minutes: 5)
        model.start()
        model.finish(.pomodoro)
        #expect(events == [.timerFinished(title: "專注時間結束", subtitle: "短休息 5 分鐘吧")])
        #expect(model.clock(.pomodoro).phase == .shortBreak)
        #expect(model.mode == .countdown)
        #expect(model.clock(.countdown).remaining(at: clock.now) == 300)
        #expect(model.clock(.countdown).isRunning)
    }

    @Test func compactShowsTheClockThatEndsFirst() {
        let (model, _, _) = makeModel()
        #expect(!model.isActive)
        model.setMode(.pomodoro)
        model.start() // 25 分
        model.setCountdown(minutes: 5)
        model.start()
        #expect(model.compactMode == .countdown)
        model.pause()
        // 暫停的排在正在跑的後面
        #expect(model.compactMode == .pomodoro)
        model.reset()
        model.setMode(.countdown)
        #expect(model.compactMode == .pomodoro)
        #expect(model.isActive)

        model.resetAll()
        #expect(!model.isActive)
    }

    @Test func choosingTheCurrentModeKeepsTheTimerRunning() {
        let (model, _, _) = makeModel()
        model.setMode(.pomodoro)
        model.start()
        model.setMode(.pomodoro)
        #expect(model.isRunning)
    }

    @Test func startingOverGoesBackToRoundOne() {
        let (model, _, _) = makeModel()
        model.setMode(.pomodoro)
        #expect(!model.canRestartPomodoro)
        model.start()
        model.finish()
        model.finish()
        model.finish()
        #expect(Step(model.phase, model.currentRound) == Step(.shortBreak, 2))
        #expect(model.canRestartPomodoro)

        model.restartPomodoro()
        #expect(Step(model.phase, model.currentRound) == Step(.focus, 1))
        #expect(model.completedFocusSessions == 0)
        #expect(model.runState == .idle)
        #expect(!model.canRestartPomodoro)
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

    /// 連按跳過時每一步的（階段, 輪數）。
    private func skipSteps(_ model: TimerModel, count: Int) -> [Step] {
        (0..<count).map { _ in
            model.skipPhase()
            return Step(model.phase, model.currentRound)
        }
    }

    private struct Step: Equatable, CustomStringConvertible {
        let phase: TimerModel.Phase
        let round: Int
        init(_ phase: TimerModel.Phase, _ round: Int) { self.phase = phase; self.round = round }
        var description: String { "\(phase) \(round)" }
    }

    @Test func skippingKeepsMovingForwardThroughTheRounds() {
        let (model, _, preferences) = makeModel()
        preferences.longBreakInterval = 2
        var events: [IslandEvent.Kind] = []
        model.onFinished = { events.append($0) }
        model.setMode(.pomodoro)
        #expect(Step(model.phase, model.currentRound) == Step(.focus, 1))

        #expect(skipSteps(model, count: 7) == [
            Step(.shortBreak, 1), Step(.focus, 2),
            Step(.longBreak, 2), Step(.focus, 3),
            Step(.shortBreak, 3), Step(.focus, 4),
            Step(.longBreak, 4),
        ])
        #expect(model.completedFocusSessions == 4)
        #expect(model.runState == .idle)
        // 跳過是使用者自己按的，不跳提示
        #expect(events.isEmpty)
    }

    @Test func skippingAfterAFinishedFocusKeepsMovingForward() {
        let (model, _, _) = makeModel()
        model.setMode(.pomodoro)
        model.finish() // 第 1 輪專注做完 → 短休息
        #expect(Step(model.phase, model.currentRound) == Step(.shortBreak, 1))

        #expect(skipSteps(model, count: 4) == [
            Step(.focus, 2), Step(.shortBreak, 2),
            Step(.focus, 3), Step(.shortBreak, 3),
        ])
    }

    @Test func skippingStartsTheNextPhaseWhenAutoStartIsOn() {
        let (model, _, _) = makeModel(autoStart: true)
        model.setMode(.pomodoro)
        model.start()
        model.skipPhase()
        #expect(model.phase == .shortBreak)
        #expect(model.isRunning)
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
