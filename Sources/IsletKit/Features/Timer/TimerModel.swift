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

    /// 一個獨立的時鐘。計時器和番茄鐘各有一個，可以同時跑。
    struct Clock {
        /// 這一段是什麼（計時器固定是 .countdown）。
        var phase: Phase
        var runState: RunState = .idle
        /// 這一段的總長度（秒）。
        var duration: TimeInterval

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
    }

    static let presetMinutes = [1, 10, 30, 60, 90, 120]

    /// 展開時顯示哪一個。只是切換畫面，另一個照常在背景跑。
    private(set) var mode: Mode = .countdown
    private(set) var countdownClock = Clock(phase: .countdown, duration: 10 * 60)
    private(set) var pomodoroClock = Clock(phase: .focus, duration: 25 * 60)
    /// 已完成幾次專注（決定第幾輪、何時長休息）。番茄鐘會一直往下走，按「從頭開始」才歸零。
    private(set) var completedFocusSessions = 0
    /// 倒數模式的分鐘數。
    private(set) var countdownMinutes = 10

    /// 時間到時呼叫，參數是要顯示的事件。
    @ObservationIgnored var onFinished: (IslandEvent.Kind) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var finishTasks: [Mode: Task<Void, Never>] = [:]

    init(preferences: Preferences, now: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.now = now
        pomodoroClock.duration = length(of: .focus)
    }

    // MARK: - 狀態

    func clock(_ which: Mode) -> Clock {
        self[keyPath: Self.clockPath(which)]
    }

    /// 展開時顯示的那一個的狀態。
    var phase: Phase { clock(mode).phase }
    var runState: RunState { clock(mode).runState }
    var isRunning: Bool { clock(mode).isRunning }
    func remaining(at date: Date) -> TimeInterval { clock(mode).remaining(at: date) }
    func progress(at date: Date) -> Double { clock(mode).progress(at: date) }

    /// 有任何一個在跑或暫停中（收合時要顯示）。
    var isActive: Bool { Mode.allCases.contains { clock($0).runState != .idle } }

    /// 另一個（不是展開時顯示的那個）在背景跑或暫停中。
    func isActiveInBackground(_ which: Mode) -> Bool {
        which != mode && clock(which).runState != .idle
    }

    /// 收合時顯示哪一個：正在跑而且最快結束的；都沒在跑就顯示暫停中的，優先目前選的模式。
    var compactMode: Mode {
        let running = Mode.allCases.compactMap { which -> (Mode, Date)? in
            if case .running(let endDate) = clock(which).runState { return (which, endDate) }
            return nil
        }
        if let soonest = running.min(by: { $0.1 < $1.1 }) { return soonest.0 }
        if clock(mode).runState != .idle { return mode }
        return Mode.allCases.first { clock($0).runState != .idle } ?? mode
    }

    /// 番茄鐘目前是第幾輪（1 起算）：專注中是正在做的那一輪，休息時是剛做完的那一輪。
    var currentRound: Int {
        max(completedFocusSessions + (pomodoroClock.phase == .focus ? 1 : 0), 1)
    }

    // MARK: - 操作（沒指定的話作用在展開時顯示的那一個）

    func start(_ which: Mode? = nil) {
        let which = which ?? mode
        let remaining = clock(which).remaining(at: now())
        guard remaining > 0 else { return }
        self[keyPath: Self.clockPath(which)].runState = .running(endDate: now().addingTimeInterval(remaining))
        scheduleFinish(which, after: remaining)
    }

    func pause() {
        guard case .running(let endDate) = runState else { return }
        cancelFinish(mode)
        self[keyPath: Self.clockPath(mode)].runState = .paused(remaining: max(0, endDate.timeIntervalSince(now())))
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// 回到這一段的開頭（番茄鐘的輪數不變）。
    func reset(_ which: Mode? = nil) {
        let which = which ?? mode
        cancelFinish(which)
        let phase = clock(which).phase
        self[keyPath: Self.clockPath(which)] = Clock(phase: phase, duration: length(of: phase))
    }

    /// 兩個都停下來（關掉計時器功能時）。
    func resetAll() {
        Mode.allCases.forEach { reset($0) }
    }

    /// 切換展開時顯示的模式，不影響正在跑的計時。
    func setMode(_ newMode: Mode) {
        mode = newMode
    }

    /// 番茄鐘回到第 1 輪的專注，等使用者再開始。
    func restartPomodoro() {
        cancelFinish(.pomodoro)
        completedFocusSessions = 0
        pomodoroClock = Clock(phase: .focus, duration: length(of: .focus))
    }

    /// 已經在第 1 輪的開頭時，「從頭開始」沒有作用。
    var canRestartPomodoro: Bool {
        completedFocusSessions > 0 || pomodoroClock.phase != .focus || pomodoroClock.runState != .idle
    }

    /// 選擇倒數的分鐘數（計時器會重新開始，番茄鐘不受影響）。
    func setCountdown(minutes: Int) {
        cancelFinish(.countdown)
        countdownMinutes = min(max(minutes, 1), 180)
        mode = .countdown
        countdownClock = Clock(phase: .countdown, duration: TimeInterval(countdownMinutes * 60))
    }

    func adjustCountdown(by minutes: Int) {
        setCountdown(minutes: countdownMinutes + minutes)
    }

    /// 番茄鐘：直接結束這一段、跳到下一段。跳過專注也算做完這一輪，輪數才會一直往前走。
    /// 因為是使用者自己按的，不發提示。
    func skipPhase() {
        cancelFinish(.pomodoro)
        completePomodoroPhase()
    }

    /// 番茄鐘時長設定改變時，沒在跑的話套用新長度。
    func preferencesChanged() {
        if pomodoroClock.runState == .idle {
            pomodoroClock.duration = length(of: pomodoroClock.phase)
        }
    }

    /// 時間到（也給測試直接呼叫）。
    func finish(_ which: Mode? = nil) {
        let which = which ?? mode
        cancelFinish(which)
        switch which {
        case .countdown:
            countdownClock.runState = .idle
            onFinished(.timerFinished(
                title: tr("時間到！", "Time's up!"),
                subtitle: tr("\(countdownMinutes) 分鐘計時結束", "\(countdownMinutes)-minute timer finished")
            ))
        case .pomodoro:
            let next = completePomodoroPhase()
            if next.isBreak {
                onFinished(.timerFinished(
                    title: tr("專注時間結束", "Focus time's over"),
                    subtitle: tr("\(next.title) \(minutes(of: next)) 分鐘吧", "Time for a \(minutes(of: next))-minute \(next.title.lowercased())")
                ))
            } else {
                onFinished(.timerFinished(title: tr("休息結束", "Break's over"), subtitle: tr("開始下一輪專注", "Start the next focus round")))
            }
        }
    }

    // MARK: - 內部

    private static func clockPath(_ which: Mode) -> ReferenceWritableKeyPath<TimerModel, Clock> {
        switch which {
        case .countdown: \.countdownClock
        case .pomodoro: \.pomodoroClock
        }
    }

    /// 結束目前這一段（時間到或跳過）：專注做完就 +1 輪，換到下一段；有開自動接續就直接開始。
    @discardableResult
    private func completePomodoroPhase() -> Phase {
        if pomodoroClock.phase == .focus {
            completedFocusSessions += 1
        }
        let next = PomodoroSchedule.phase(
            after: pomodoroClock.phase,
            completedFocusSessions: completedFocusSessions,
            longBreakInterval: preferences.longBreakInterval
        )
        pomodoroClock = Clock(phase: next, duration: length(of: next))
        if preferences.pomodoroAutoStart {
            start(.pomodoro)
        }
        return next
    }

    private func scheduleFinish(_ which: Mode, after seconds: TimeInterval) {
        cancelFinish(which)
        finishTasks[which] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(which)
        }
    }

    private func cancelFinish(_ which: Mode) {
        finishTasks.removeValue(forKey: which)?.cancel()
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
