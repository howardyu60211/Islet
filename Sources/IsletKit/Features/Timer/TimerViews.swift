import SwiftUI

extension TimerModel.Phase {
    var tint: Color {
        isBreak ? .green : .orange
    }
}

/// 倒數顯示用無條件進位（剛開始顯示 5:00，最後一秒顯示 0:01）。
func formatCountdown(_ seconds: TimeInterval) -> String {
    formatTime(seconds.rounded(.up))
}

/// 跟著時間更新的內容：跑的時候每秒更新一次，而且對齊結束時間，數字才會準時跳。
/// 收合時一直在畫面上，所以不加會持續播放的動畫（每秒一個動畫等於一直在重畫）。
private struct TimerTicker<Content: View>: View {
    let runState: TimerModel.RunState
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if case .running(let endDate) = runState {
            let aligned = endDate.addingTimeInterval(-(endDate.timeIntervalSinceNow.rounded(.up) + 1))
            TimelineView(.periodic(from: aligned, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(Date())
        }
    }
}

// MARK: - 收合時

/// 計時器和番茄鐘可以同時跑，收合時顯示 `compactMode` 那一個（最快結束的）。
struct TimerCompactLeading: View {
    let model: TimerModel

    var body: some View {
        let clock = model.clock(model.compactMode)
        TimerTicker(runState: clock.runState) { date in
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: clock.progress(at: date))
                    .stroke(clock.phase.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: clock.isRunning ? clock.phase.symbol : "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(clock.phase.tint)
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct TimerCompactTrailing: View {
    let model: TimerModel

    var body: some View {
        let clock = model.clock(model.compactMode)
        TimerTicker(runState: clock.runState) { date in
            Text(formatCountdown(clock.remaining(at: date)))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(clock.isRunning ? clock.phase.tint : clock.phase.tint.opacity(0.6))
        }
    }
}

// MARK: - 展開後

struct TimerPanelView: View {
    let model: TimerModel
    let preferences: Preferences

    var body: some View {
        HStack(spacing: 26) {
            TimerDial(model: model)
                .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    ForEach(TimerModel.Mode.allCases) { mode in
                        ModePill(model: model, mode: mode)
                    }
                }
                if model.mode == .countdown {
                    CountdownPresets(model: model)
                } else {
                    PomodoroSettings(preferences: preferences)
                }
                TimerControls(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

private struct TimerDial: View {
    let model: TimerModel

    var body: some View {
        TimerTicker(runState: model.runState) { date in
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: model.progress(at: date))
                    .stroke(model.phase.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(formatCountdown(model.remaining(at: date)))
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.smooth(duration: 0.25), value: Int(model.remaining(at: date).rounded(.up)))
                    Text(model.phase.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.phase.tint)
                    // 番茄鐘的輪數一直往下累計，獨立一行，英文的「Short Break · Round 12」才不會超出圓環
                    if model.mode == .pomodoro {
                        Text(tr("第 \(model.currentRound) 輪", "Round \(model.currentRound)"))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }
}

/// 模式切換按鈕。另一個在背景跑的話，按鈕上順便顯示它的剩餘時間。
private struct ModePill: View {
    let model: TimerModel
    let mode: TimerModel.Mode

    var body: some View {
        let clock = model.clock(mode)
        let showsTime = model.isActiveInBackground(mode)
        // 沒顯示時間時不用每秒更新
        TimerTicker(runState: showsTime ? clock.runState : .idle) { date in
            let title = showsTime ? "\(mode.title) \(formatCountdown(clock.remaining(at: date)))" : mode.title
            PillButton(title: title, isSelected: model.mode == mode) {
                model.setMode(mode)
            }
        }
    }
}

private struct CountdownPresets: View {
    let model: TimerModel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(TimerModel.presetMinutes, id: \.self) { minutes in
                PillButton(title: tr("\(minutes) 分", "\(minutes) min"), isSelected: model.countdownMinutes == minutes, compact: true) {
                    model.setCountdown(minutes: minutes)
                }
            }
            Divider().frame(height: 14).overlay(.white.opacity(0.2))
            RoundIconButton(symbol: "minus", label: tr("少一分鐘", "One minute less")) { model.adjustCountdown(by: -1) }
            RoundIconButton(symbol: "plus", label: tr("多一分鐘", "One minute more")) { model.adjustCountdown(by: 1) }
        }
    }
}

/// 番茄鐘：直接在島上調整專注、休息時間，以及要不要自動接續下一段。
private struct PomodoroSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        HStack(spacing: 10) {
            MiniStepper(title: tr("專注", "Focus"), value: $preferences.focusMinutes, unit: tr("分", "min"), range: 5...120, step: 5)
            MiniStepper(title: tr("休息", "Break"), value: $preferences.shortBreakMinutes, unit: tr("分", "min"), range: 1...30, step: 1)
            PillButton(title: tr("自動接續", "Auto-continue"), isSelected: preferences.pomodoroAutoStart, compact: true) {
                preferences.pomodoroAutoStart.toggle()
            }
        }
        .frame(height: 22)
    }
}

/// 「專注 − 25分 +」這種小型加減按鈕。
private struct MiniStepper: View {
    let title: String
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            RoundIconButton(symbol: "minus", label: tr("減少\(title)", "Decrease \(title)")) {
                value = max(range.lowerBound, value - step)
            }
            .disabled(value <= range.lowerBound)
            Text(tr("\(value)\(unit)", "\(value) \(unit)"))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(minWidth: 34)
            RoundIconButton(symbol: "plus", label: tr("增加\(title)", "Increase \(title)")) {
                value = min(range.upperBound, value + step)
            }
            .disabled(value >= range.upperBound)
        }
    }
}

private struct TimerControls: View {
    let model: TimerModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.toggle()
            } label: {
                Label(model.isRunning ? tr("暫停", "Pause") : (model.runState == .idle ? tr("開始", "Start") : tr("繼續", "Resume")),
                      systemImage: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(Capsule().fill(model.phase.tint.opacity(0.9)))
                    .foregroundStyle(.black)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            PillButton(title: tr("重設", "Reset"), isSelected: false) { model.reset() }
                .disabled(model.runState == .idle)
                .opacity(model.runState == .idle ? 0.4 : 1)

            if model.mode == .pomodoro {
                PillButton(title: tr("跳過", "Skip"), isSelected: false) { model.skipPhase() }
                // 輪數會一直累計，這裡讓使用者回到第 1 輪
                PillButton(title: tr("從頭開始", "Start Over"), isSelected: false) { model.restartPomodoro() }
                    .disabled(!model.canRestartPomodoro)
                    .opacity(model.canRestartPomodoro ? 1 : 0.4)
            }
        }
    }
}

/// 島上通用的膠囊按鈕。
struct PillButton: View {
    let title: String
    let isSelected: Bool
    var compact = false
    let action: () -> Void

    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .medium).monospacedDigit())
                .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                .padding(.horizontal, compact ? 8 : 12)
                .frame(height: compact ? 22 : 26)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(isHovering ? 0.16 : 0.09))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(isHovering ? 0.16 : 0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}
