import AppKit

/// 把所有服務組在一起，負責啟動與停止。
final class AppServices {
    let preferences = Preferences()
    let battery = BatteryMonitor()
    let nowPlaying = NowPlayingModel()
    let timer: TimerModel
    let shelf = ShelfModel()
    let bluetooth = BluetoothMonitor()
    let volume = VolumeMonitor()
    let focus = FocusMonitor()
    let microphone = MicrophoneMonitor()
    let screenRecording = ScreenRecordingMonitor()
    let clipboard = ClipboardModel()
    let backgroundApps = BackgroundAppsModel()
    let timerAlert: TimerAlert
    let island: IslandViewModel
    let windowController: NotchWindowController
    let settingsWindow: SettingsWindowController
    private var statusMenu: StatusMenuController?

    init() {
        timer = TimerModel(preferences: preferences)
        timerAlert = TimerAlert(nowPlaying: nowPlaying)
        island = IslandViewModel(
            preferences: preferences,
            battery: battery,
            nowPlaying: nowPlaying,
            timer: timer,
            shelf: shelf,
            clipboard: clipboard,
            microphone: microphone,
            screenRecording: screenRecording,
            backgroundApps: backgroundApps
        )
        windowController = NotchWindowController(island: island, preferences: preferences)
        settingsWindow = SettingsWindowController(
            preferences: preferences,
            nowPlaying: nowPlaying,
            focus: focus,
            shelf: shelf,
            clipboard: clipboard,
            backgroundApps: backgroundApps
        )
    }

    func start() {
        island.openSettings = { [weak self] in
            self?.showSettings()
        }
        preferences.onChange = { [weak self] key in
            self?.preferenceChanged(key)
        }
        statusMenu = StatusMenuController(services: self)
        windowController.start()

        battery.onEvent = { [weak self] kind in
            guard let self, self.preferences.batteryAlertsEnabled else { return }
            self.island.post(IslandEvent(kind: kind))
        }
        battery.start()
        backgroundApps.start()

        if preferences.musicEnabled {
            nowPlaying.start()
        }

        timer.onFinished = { [weak self] kind in
            guard let self, self.preferences.timerEnabled else { return }
            self.timerAlert.play(sound: self.preferences.timerSound, pausingMusic: self.preferences.timerPausesMusic)
            self.island.post(IslandEvent(kind: kind))
        }

        bluetooth.onEvent = { [weak self] kind in
            guard let self, self.preferences.bluetoothAlertsEnabled else { return }
            self.island.post(IslandEvent(kind: kind))
        }
        if preferences.bluetoothAlertsEnabled {
            bluetooth.start()
        }

        volume.onChange = { [weak self] level, muted in
            self?.island.post(IslandEvent(kind: .volume(level: level, muted: muted)))
        }
        focus.onChange = { [weak self] mode, active in
            self?.island.post(IslandEvent(kind: .focus(mode, active: active)))
        }
        microphone.onChange = { [weak self] active, app in
            self?.island.post(IslandEvent(kind: .sensor(.microphone, app: app, active: active)))
        }
        screenRecording.onChange = { [weak self] active in
            self?.island.post(IslandEvent(kind: .sensor(.screenRecording, app: nil, active: active)))
        }
        clipboard.onCapture = { [weak self] item in
            guard let self, self.preferences.clipboardAlertsEnabled else { return }
            self.island.post(IslandEvent(kind: .clipboard(item.summary)))
        }
        for key in Self.monitorKeys {
            preferenceChanged(key)
        }
    }

    func stop() {
        battery.stop()
        bluetooth.stop()
        volume.stop()
        focus.stop()
        microphone.stop()
        screenRecording.stop()
        clipboard.stop()
        backgroundApps.stop()
        nowPlaying.stop()
        windowController.stop()
    }

    func showSettings() {
        island.collapse()
        settingsWindow.show()
    }

    func toggleIslandHidden() {
        preferences.islandHidden.toggle()
    }

    /// 開關跟著設定走的監聽器（啟動時也用 preferenceChanged 依目前的設定開啟）。
    private static let monitorKeys = [
        Preferences.Key.volumeAlertsEnabled,
        Preferences.Key.focusAlertsEnabled,
        Preferences.Key.microphoneIndicatorEnabled,
        Preferences.Key.screenRecordingIndicatorEnabled,
        Preferences.Key.clipboardEnabled,
    ]

    /// 設定變更時開關對應的功能。
    private func preferenceChanged(_ key: String) {
        switch key {
        case Preferences.Key.islandHidden:
            windowController.updatePlacement()
        case Preferences.Key.menuBarIconHidden:
            statusMenu?.setIconVisible(!preferences.menuBarIconHidden)
        case Preferences.Key.musicEnabled:
            if preferences.musicEnabled {
                nowPlaying.start()
            } else {
                nowPlaying.stop()
            }
        case Preferences.Key.bluetoothAlertsEnabled:
            if preferences.bluetoothAlertsEnabled {
                bluetooth.start()
            } else {
                bluetooth.stop()
            }
        case Preferences.Key.volumeAlertsEnabled:
            preferences.volumeAlertsEnabled ? volume.start() : volume.stop()
        case Preferences.Key.focusAlertsEnabled:
            preferences.focusAlertsEnabled ? focus.start() : focus.stop()
        case Preferences.Key.microphoneIndicatorEnabled:
            preferences.microphoneIndicatorEnabled ? microphone.start() : microphone.stop()
        case Preferences.Key.screenRecordingIndicatorEnabled:
            preferences.screenRecordingIndicatorEnabled ? screenRecording.start() : screenRecording.stop()
        case Preferences.Key.clipboardEnabled:
            preferences.clipboardEnabled ? clipboard.start() : clipboard.stop()
        case Preferences.Key.timerEnabled:
            if !preferences.timerEnabled {
                timer.reset()
            }
        case Preferences.Key.focusMinutes, Preferences.Key.shortBreakMinutes, Preferences.Key.longBreakMinutes, Preferences.Key.pomodoroRounds:
            timer.preferencesChanged()
        default:
            break
        }
    }
}

#if DEBUG
/// Debug 建置的「模擬事件」選單項目，不用實機也能看每一種狀態。
struct DebugSimulation {
    let title: String
    let run: () -> Void
}

extension AppServices {
    func debugSimulations() -> [DebugSimulation] {
        let island = island
        let nowPlaying = nowPlaying
        let airPods = BluetoothDeviceSnapshot(
            name: "AirPods Pro",
            address: "00:00:00:00:00:01",
            symbolName: "airpods.pro",
            battery: HeadphoneBattery(left: 82, right: 79, caseLevel: 45)
        )
        return [
            DebugSimulation(title: tr("插上電源", "Plug In")) { island.post(IslandEvent(kind: .charging(level: 76))) },
            DebugSimulation(title: tr("拔掉電源", "Unplug")) { island.post(IslandEvent(kind: .unplugged(level: 76))) },
            DebugSimulation(title: tr("充飽電", "Fully Charged")) { island.post(IslandEvent(kind: .fullyCharged)) },
            DebugSimulation(title: tr("低電量 10%", "Low Battery 10%")) { island.post(IslandEvent(kind: .lowBattery(level: 10))) },
            DebugSimulation(title: tr("AirPods 連線", "AirPods Connected")) { island.post(IslandEvent(kind: .bluetooth(device: airPods, connected: true))) },
            DebugSimulation(title: tr("AirPods 中斷", "AirPods Disconnected")) { island.post(IslandEvent(kind: .bluetooth(device: airPods, connected: false))) },
            DebugSimulation(title: tr("計時結束", "Timer Finished")) {
                island.post(IslandEvent(kind: .timerFinished(
                    title: tr("專注時間結束", "Focus time's over"),
                    subtitle: tr("短休息 5 分鐘吧", "Time for a 5-minute short break")
                )))
            },
            DebugSimulation(title: tr("假的正在播放", "Fake Now Playing")) { nowPlaying.apply(.debugSample) },
            DebugSimulation(title: tr("計時結束（含提示音）", "Timer Finished (with Sound)")) { [self] in
                timerAlert.play(sound: preferences.timerSound, pausingMusic: preferences.timerPausesMusic)
                island.post(IslandEvent(kind: .timerFinished(
                    title: tr("時間到！", "Time's up!"),
                    subtitle: tr("1 分鐘計時結束", "1-minute timer finished")
                )))
            },
            DebugSimulation(title: tr("音量 60%", "Volume 60%")) { island.post(IslandEvent(kind: .volume(level: 60, muted: false))) },
            DebugSimulation(title: tr("靜音", "Mute")) { island.post(IslandEvent(kind: .volume(level: 60, muted: true))) },
            DebugSimulation(title: tr("專注模式開啟", "Focus On")) { island.post(IslandEvent(kind: .focus(.debugSample, active: true))) },
            DebugSimulation(title: tr("專注模式關閉", "Focus Off")) { island.post(IslandEvent(kind: .focus(.debugSample, active: false))) },
            DebugSimulation(title: tr("麥克風使用中", "Microphone In Use")) { [microphone] in
                microphone.debugSetActive(true, apps: [.debugSample])
                island.post(IslandEvent(kind: .sensor(.microphone, app: .debugSample, active: true)))
            },
            DebugSimulation(title: tr("麥克風停止", "Microphone Stopped")) { [microphone] in
                microphone.debugSetActive(false, apps: [])
                island.post(IslandEvent(kind: .sensor(.microphone, app: .debugSample, active: false)))
            },
            DebugSimulation(title: tr("螢幕錄影開始", "Screen Recording Started")) { island.post(IslandEvent(kind: .sensor(.screenRecording, app: nil, active: true))) },
            DebugSimulation(title: tr("拷貝文字", "Copy Text")) {
                island.post(IslandEvent(kind: .clipboard(ClipboardSummary(id: UUID(), kind: .text, excerpt: tr("會議改到週四下午三點", "Meeting moved to Thursday 3 PM"), image: nil))))
            },
            DebugSimulation(title: tr("開始 1 分鐘計時", "Start 1-Minute Timer")) { [timer] in
                timer.setCountdown(minutes: 1)
                timer.start()
            },
        ]
    }
}
#endif
