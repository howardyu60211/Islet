import Foundation
import Observation

/// 計時器與番茄鐘。
@Observable
final class TimerModel {
    enum Mode: String, CaseIterable, Identifiable {
        case countdown
        case pomodoro

        var id: Self { self }

        var title: String {
            switch self {
            case .countdown: tr("計時器", "Timer")
            case .pomodoro: tr("番茄鐘", "Pomodoro")
            }
        }
    }

    enum Phase: Equatable {
        case countdown
        case focus
        case shortBreak
        case longBreak

        var title: String {
            switch self {
            case .countdown: tr("計時器", "Timer")
            case .focus: tr("專注", "Focus")
            case .shortBreak: tr("短休息", "Short Break")
            case .longBreak: tr("長休息", "Long Break")
            }
        }

        var symbol: String {
            switch self {
            case .countdown: "timer"
            case .focus: "target"
            case .shortBreak, .longBreak: "cup.and.saucer.fill"
            }
        }

        var isBreak: Bool { self == .shortBreak || self == .longBreak }
    }

    enum RunState: Equatable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    static let presetMinutes = [1, 10, 30, 60, 90, 120]

    private(set) var mode: Mode = .countdown
    private(set) var phase: Phase = .countdown
    private(set) var runState: RunState = .idle
    /// 目前這一段的總長度（秒）。
    private(set) var duration: TimeInterval = 10 * 60
    /// 這一輪已完成幾次專注（用來決定何時長休息）。
    private(set) var completedFocusSessions = 0
    /// 倒數模式的分鐘數。
    private(set) var countdownMinutes = 10

    /// 時間到時呼叫，參數是要顯示的事件。
    @ObservationIgnored var onFinished: (IslandEvent.Kind) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    init(preferences: Preferences, now: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.now = now
    }

    // MARK: - 狀態

    /// 正在跑或暫停中（收合時要顯示）。
    var isActive: Bool { runState != .idle }

    var isRunning: Bool {
        if case .running = runState { return true }
        return false
    }

    func remaining(at date: Date) -> TimeInterval {
        switch runState {
        case .idle: duration
        case .running(let endDate): max(0, endDate.timeIntervalSince(date))
        case .paused(let remaining): remaining
        }
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining(at: date) / duration
    }

    // MARK: - 操作

    func start() {
        let remaining = remaining(at: now())
        guard remaining > 0 else { return }
        runState = .running(endDate: now().addingTimeInterval(remaining))
        scheduleFinish(after: remaining)
    }

    func pause() {
        guard case .running(let endDate) = runState else { return }
        finishTask?.cancel()
        runState = .paused(remaining: max(0, endDate.timeIntervalSince(now())))
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// 回到這一段的開頭（番茄鐘的輪數不變）。
    func reset() {
        finishTask?.cancel()
        runState = .idle
        duration = length(of: phase)
    }

    func setMode(_ newMode: Mode) {
        finishTask?.cancel()
        mode = newMode
        completedFocusSessions = 0
        phase = newMode == .countdown ? .countdown : .focus
        runState = .idle
        duration = length(of: phase)
    }

    /// 倒數模式下選擇分鐘數（會重新開始）。
    func setCountdown(minutes: Int) {
        finishTask?.cancel()
        countdownMinutes = min(max(minutes, 1), 180)
        if mode != .countdown {
            mode = .countdown
            phase = .countdown
        }
        runState = .idle
        duration = TimeInterval(countdownMinutes * 60)
    }

    func adjustCountdown(by minutes: Int) {
        setCountdown(minutes: countdownMinutes + minutes)
    }

    /// 番茄鐘：直接跳到下一段。
    func skipPhase() {
        guard mode == .pomodoro else { return }
        finishTask?.cancel()
        advancePhase(countingFocus: false)
    }

    /// 番茄鐘時長設定改變時，沒在跑的話套用新長度。
    func preferencesChanged() {
        if runState == .idle {
            duration = length(of: phase)
        }
    }

    /// 時間到（也給測試直接呼叫）。
    func finish() {
        finishTask?.cancel()
        switch phase {
        case .countdown:
            runState = .idle
            onFinished(.timerFinished(
                title: tr("時間到！", "Time's up!"),
                subtitle: tr("\(countdownMinutes) 分鐘計時結束", "\(countdownMinutes)-minute timer finished")
            ))
        case .focus:
            let rounds = max(preferences.pomodoroRounds, 1)
            if completedFocusSessions + 1 >= rounds {
                // 全部輪數完成：回到第一輪的專注，等使用者再開始
                completedFocusSessions = 0
                phase = .focus
                duration = length(of: .focus)
                runState = .idle
                onFinished(.timerFinished(
                    title: tr("番茄鐘完成！", "Pomodoro complete!"),
                    subtitle: tr("完成 \(rounds) 輪專注，好好休息吧", "\(rounds) focus rounds done — enjoy your break")
                ))
                return
            }
            let next = advancePhase(countingFocus: true)
            onFinished(.timerFinished(
                title: tr("專注時間結束", "Focus time's over"),
                subtitle: tr("\(next.title) \(minutes(of: next)) 分鐘吧", "Time for a \(minutes(of: next))-minute \(next.title.lowercased())")
            ))
        case .shortBreak, .longBreak:
            advancePhase(countingFocus: false)
            onFinished(.timerFinished(title: tr("休息結束", "Break's over"), subtitle: tr("開始下一輪專注", "Start the next focus round")))
        }
    }

    // MARK: - 內部

    @discardableResult
    private func advancePhase(countingFocus: Bool) -> Phase {
        if countingFocus {
            completedFocusSessions += 1
        }
        let next = PomodoroSchedule.phase(
            after: phase,
            completedFocusSessions: completedFocusSessions,
            longBreakInterval: preferences.longBreakInterval
        )
        phase = next
        duration = length(of: next)
        runState = .idle
        if preferences.pomodoroAutoStart {
            start()
        }
        return next
    }

    private func scheduleFinish(after seconds: TimeInterval) {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func minutes(of phase: Phase) -> Int {
        switch phase {
        case .countdown: countdownMinutes
        case .focus: preferences.focusMinutes
        case .shortBreak: preferences.shortBreakMinutes
        case .longBreak: preferences.longBreakMinutes
        }
    }

    private func length(of phase: Phase) -> TimeInterval {
        TimeInterval(minutes(of: phase) * 60)
    }
}

/// 番茄鐘的下一段：專注後休息（每 N 次專注來一次長休息），休息後回到專注。
enum PomodoroSchedule {
    static func phase(after phase: TimerModel.Phase, completedFocusSessions: Int, longBreakInterval: Int) -> TimerModel.Phase {
        switch phase {
        case .focus:
            let interval = max(longBreakInterval, 1)
            return completedFocusSessions > 0 && completedFocusSessions % interval == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        case .countdown:
            return .countdown
        }
    }
}
