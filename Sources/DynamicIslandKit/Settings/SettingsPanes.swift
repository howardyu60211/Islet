import SwiftUI

// 設定視窗每一頁的內容。每一頁都是幾個 Section，由 SettingsView 放進同一個 Form 裡。

struct GeneralSettings: View {
    @Bindable var preferences: Preferences

    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var launchAtLoginError: String?
    @ViewState private var language = AppLanguage.override
    /// 這次啟動時的語言設定；改過之後才提示要重新啟動。
    private static let languageAtLaunch = AppLanguage.override

    var body: some View {
        Section {
            Picker(tr("語言", "Language"), selection: languageBinding) {
                Text(tr("跟隨系統", "System Default")).tag(AppLanguage?.none)
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName).tag(AppLanguage?.some(language))
                }
            }
            if language != Self.languageAtLaunch, (language ?? AppLanguage.system) != AppLanguage.current {
                SettingsNote(tr("重新啟動動態島後才會換成新的語言。", "DynamicIsland needs to restart to switch languages.")) {
                    Button(tr("重新啟動", "Restart")) { Self.relaunch() }
                }
            }
        }

        Section(tr("啟動", "Startup")) {
            Toggle(tr("登入時自動開啟", "Open at Login"), isOn: launchAtLoginBinding)
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if LaunchAtLogin.requiresApproval {
                SettingsNote(tr("需要在系統設定的「登入項目」中允許。", "Allow it under Login Items in System Settings.")) {
                    Button(tr("打開系統設定", "Open System Settings")) { LaunchAtLogin.openSystemSettings() }
                }
            }
        }

        Section(tr("展開", "Expanding")) {
            Picker(tr("展開方式", "Expand On"), selection: $preferences.expandMode) {
                ForEach(ExpandMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if preferences.expandMode == .hover {
                LabeledContent(tr("停留多久才展開", "Hover Delay")) {
                    HStack {
                        Slider(value: $preferences.hoverDelay, in: 0...1, step: 0.05)
                            .frame(width: 160)
                        Text(String(format: tr("%.2f 秒", "%.2f s"), preferences.hoverDelay))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
            Toggle(tr("展開時觸控板輕震", "Haptic Feedback When Expanding"), isOn: $preferences.hapticFeedback)
        }

        Section {
            Toggle(tr("同時顯示兩個活動", "Show Two Activities at Once"), isOn: $preferences.pairActivities)
        } header: {
            Text(tr("收合時", "When Collapsed"))
        } footer: {
            SettingsFooter(tr("例如音樂播放時又開始計時，或正在使用麥克風、螢幕錄影：瀏海左右兩側各顯示一個。關掉的話只顯示優先的那一個（計時器 > 音樂）。", "For example, a timer started while music is playing, or the microphone or screen recording in use: one appears on each side of the notch. When off, only the higher-priority one is shown (timer > music)."))
        }

        Section {
            Toggle(tr("隱藏動態島", "Hide the Island"), isOn: $preferences.islandHidden)
        } header: {
            Text(tr("顯示", "Display"))
        } footer: {
            SettingsFooter(tr("隱藏後也可以從選單列的膠囊圖示再打開。", "You can bring it back from the capsule icon in the menu bar."))
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { enabled in
            do {
                try LaunchAtLogin.setEnabled(enabled)
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = tr("無法變更：\(error.localizedDescription)", "Couldn’t change this: \(error.localizedDescription)")
            }
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private var languageBinding: Binding<AppLanguage?> {
        Binding {
            language
        } set: { newValue in
            AppLanguage.override = newValue
            language = newValue
        }
    }

    /// 等這個行程結束後再打開同一個 App（直接開會先被當成同一個實例）。
    private static func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? reopen.run()
        NSApp.terminate(nil)
    }
}

struct NotificationSettings: View {
    @Bindable var preferences: Preferences
    let focus: FocusMonitor

    var body: some View {
        Section(tr("系統狀態", "System Status")) {
            Toggle(tr("插上電源、低電量與充飽電", "Plugging In, Low Battery and Fully Charged"), isOn: $preferences.batteryAlertsEnabled)
            Toggle(tr("藍牙耳機連線與中斷", "Bluetooth Headphones Connecting and Disconnecting"), isOn: $preferences.bluetoothAlertsEnabled)
            Toggle(tr("調整音量與靜音", "Volume Changes and Mute"), isOn: $preferences.volumeAlertsEnabled)
            Toggle(tr("專注模式開啟與關閉", "Focus Turning On and Off"), isOn: $preferences.focusAlertsEnabled)
            if preferences.focusAlertsEnabled, focus.needsFullDiskAccess {
                SettingsNote(tr("macOS 沒有公開專注模式的狀態，需要在「完整磁碟取用權限」中允許動態島。", "macOS doesn’t expose Focus status publicly, so DynamicIsland needs Full Disk Access.")) {
                    Button(tr("打開系統設定", "Open System Settings")) { Self.openFullDiskAccessSettings() }
                }
            }
        }

        Section {
            Toggle(tr("麥克風使用中", "Microphone in Use"), isOn: $preferences.microphoneIndicatorEnabled)
            Toggle(tr("螢幕錄影或分享中", "Screen Being Recorded or Shared"), isOn: $preferences.screenRecordingIndicatorEnabled)
                .disabled(!ScreenRecordingMonitor.isSupported)
        } header: {
            Text(tr("隱私指示", "Privacy Indicators"))
        } footer: {
            SettingsFooter(tr("開始和停止使用時各提示一次；使用中時展開的頂部條會顯示橘色（麥克風）或紫色（螢幕錄影）的圖示，正在播音樂或計時的話，瀏海右側也會一直顯示。", "Alerts once when use starts and once when it stops. While in use, the expanded top bar shows an orange (microphone) or purple (screen recording) icon, and if music or a timer is running it also stays on the right of the notch."))
        }
    }

    private static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MusicSettings: View {
    @Bindable var preferences: Preferences
    let nowPlaying: NowPlayingModel

    var body: some View {
        Section {
            Toggle(tr("顯示正在播放", "Show Now Playing"), isOn: $preferences.musicEnabled)
        }

        Section(tr("收合時", "When Collapsed")) {
            Toggle(tr("在瀏海兩側顯示封面與音波", "Show Artwork and Waveform Beside the Notch"), isOn: $preferences.musicCompactEnabled)
        }
        .disabled(!preferences.musicEnabled)

        Section {
            LabeledContent(tr("資料來源", "Source"), value: nowPlaying.backend.title)
        } footer: {
            SettingsFooter(tr("全系統模式支援任何 App（包含瀏覽器裡的影片）；如果 macOS 擋掉這個做法，會改用只支援 Music 與 Spotify 的模式。", "System-wide mode works with any app, including videos in a browser. If macOS blocks it, the app switches to a mode that only supports Music and Spotify."))
        }
    }
}

struct ShelfSettings: View {
    @Bindable var preferences: Preferences
    let shelf: ShelfModel

    var body: some View {
        Section {
            Toggle(tr("啟用檔案櫃", "Enable the Shelf"), isOn: $preferences.shelfEnabled)
        } footer: {
            SettingsFooter(tr("把檔案拖到瀏海就會展開，可以放進檔案櫃或直接 AirDrop。項目可以拖出、雙擊開啟，右鍵有更多選項。", "Drag files onto the notch to expand it, then drop them on the shelf or straight onto AirDrop. Drag items back out, double-click to open, or right-click for more options."))
        }

        Section(tr("內容", "Contents")) {
            LabeledContent(tr("目前的檔案", "Files"), value: tr("\(shelf.items.count) 個", "\(shelf.items.count)"))
            SettingsNote(tr(
                "最多 \(ShelfModel.maxItems) 個；只記住檔案的位置，不會複製檔案本身。",
                "Up to \(ShelfModel.maxItems) items. Only their locations are remembered; the files themselves aren’t copied."
            )) {
                Button(tr("清空檔案櫃", "Clear the Shelf")) { shelf.removeAll() }
                    .disabled(shelf.items.isEmpty)
            }
        }
        .disabled(!preferences.shelfEnabled)
    }
}

struct ClipboardSettings: View {
    @Bindable var preferences: Preferences
    let clipboard: ClipboardModel

    var body: some View {
        Section {
            Toggle(tr("剪貼簿紀錄", "Clipboard History"), isOn: $preferences.clipboardEnabled)
            Toggle(tr("拷貝或剪下時在瀏海顯示動畫", "Animate the Notch When You Copy or Cut"), isOn: $preferences.clipboardAlertsEnabled)
                .disabled(!preferences.clipboardEnabled)
        }

        Section {
            LabeledContent(tr("觸控板滑動速度", "Trackpad Scroll Speed")) {
                HStack(spacing: 8) {
                    Text(tr("慢", "Slow")).foregroundStyle(.secondary)
                    Slider(value: $preferences.clipboardWheelSpeed, in: WheelTracker.speedRange, step: 0.05)
                        .frame(width: 160)
                    Text(tr("快", "Fast")).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(tr("滾輪", "Wheel"))
        } footer: {
            SettingsFooter(tr("展開剪貼簿時也可以用 ↑ ↓ 選擇、Return 複製、Esc 收合。滑鼠滾輪固定一格跳一筆。", "With the clipboard expanded you can also press ↑ ↓ to choose, Return to copy and Esc to collapse. Each click of a mouse wheel moves one entry."))
        }
        .disabled(!preferences.clipboardEnabled)

        Section {
            LabeledContent(tr("目前的紀錄", "Entries"), value: tr("\(clipboard.items.count) 筆", "\(clipboard.items.count)"))
            SettingsNote(tr(
                "最多保留 \(ClipboardModel.maxItems) 筆，只存在記憶體裡，結束 App 就清掉。",
                "Keeps up to \(ClipboardModel.maxItems) entries, in memory only; they’re cleared when the app quits."
            )) {
                Button(tr("清除紀錄", "Clear History")) { clipboard.removeAll() }
                    .disabled(clipboard.items.isEmpty)
            }
        } header: {
            Text(tr("紀錄", "History"))
        } footer: {
            SettingsFooter(tr("密碼管理器標示為隱藏的內容不會記錄。", "Content that password managers mark as concealed is never recorded."))
        }
        .disabled(!preferences.clipboardEnabled)
    }
}

struct ClockSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Toggle(tr("計時器與番茄鐘", "Timer and Pomodoro"), isOn: $preferences.timerEnabled)
        }

        Section(tr("番茄鐘", "Pomodoro")) {
            Stepper(tr("專注 \(preferences.focusMinutes) 分鐘", "Focus: \(preferences.focusMinutes) min"), value: $preferences.focusMinutes, in: 5...120, step: 5)
            Stepper(tr("短休息 \(preferences.shortBreakMinutes) 分鐘", "Short break: \(preferences.shortBreakMinutes) min"), value: $preferences.shortBreakMinutes, in: 1...30)
            Stepper(tr("總共 \(preferences.pomodoroRounds) 輪專注", "Focus rounds: \(preferences.pomodoroRounds)"), value: $preferences.pomodoroRounds, in: 1...12)
            Stepper(tr("長休息 \(preferences.longBreakMinutes) 分鐘", "Long break: \(preferences.longBreakMinutes) min"), value: $preferences.longBreakMinutes, in: 5...60, step: 5)
            Stepper(tr("每 \(preferences.longBreakInterval) 次專注後長休息", "Long break every \(preferences.longBreakInterval) focus rounds"), value: $preferences.longBreakInterval, in: 2...8)
            Toggle(tr("自動開始下一段", "Start the Next Phase Automatically"), isOn: $preferences.pomodoroAutoStart)
        }
        .disabled(!preferences.timerEnabled)

        Section {
            HStack {
                Picker(tr("提示音", "Sound"), selection: $preferences.timerSound) {
                    ForEach(TimerAlert.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Button(tr("試聽", "Preview")) { TimerAlert.preview(preferences.timerSound) }
            }
            Toggle(tr("響的時候先暫停正在播的音樂，響完再繼續", "Pause Music While the Sound Plays"), isOn: $preferences.timerPausesMusic)
        } header: {
            Text(tr("時間到的提示", "When Time’s Up"))
        } footer: {
            SettingsFooter(tr(
                "提示音會以最大音量響 \(TimerAlert.repeatCount) 次。macOS 沒有辦法只把其他 App 的聲音調小，所以用暫停再繼續的方式。",
                "The sound plays \(TimerAlert.repeatCount) times at full volume. macOS can’t turn down only other apps’ audio, so music is paused and resumed instead."
            ))
        }
        .disabled(!preferences.timerEnabled)
    }
}

struct AboutSettings: View {
    var body: some View {
        Section {
            LabeledContent(tr("版本", "Version"), value: Self.version)
        }

        Section(tr("第三方元件", "Third-Party Components")) {
            Text(tr("全系統「正在播放」使用 mediaremote-adapter（BSD-3-Clause，© Jonas van den Berg 與貢獻者），授權條款在 App 的 Resources 資料夾內。", "System-wide Now Playing uses mediaremote-adapter (BSD-3-Clause, © Jonas van den Berg and contributors). Its license is in the app’s Resources folder."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? tr("開發版", "Development")
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return tr("\(short)（\(build)）", "\(short) (\(build))")
    }
}
