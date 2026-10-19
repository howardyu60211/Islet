import SwiftUI

// 設定視窗每一頁的內容。每一頁都是幾個 Section，由 SettingsView 放進同一個 Form 裡。

struct GeneralSettings: View {
    @Bindable var preferences: Preferences

    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var launchAtLoginError: String?

    var body: some View {
        Section("啟動") {
            Toggle("登入時自動開啟", isOn: launchAtLoginBinding)
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if LaunchAtLogin.requiresApproval {
                SettingsNote("需要在系統設定的「登入項目」中允許。") {
                    Button("打開系統設定") { LaunchAtLogin.openSystemSettings() }
                }
            }
        }

        Section("展開") {
            Picker("展開方式", selection: $preferences.expandMode) {
                ForEach(ExpandMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if preferences.expandMode == .hover {
                LabeledContent("停留多久才展開") {
                    HStack {
                        Slider(value: $preferences.hoverDelay, in: 0...1, step: 0.05)
                            .frame(width: 160)
                        Text(String(format: "%.2f 秒", preferences.hoverDelay))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
            Toggle("展開時觸控板輕震", isOn: $preferences.hapticFeedback)
        }

        Section {
            Toggle("同時顯示兩個活動", isOn: $preferences.pairActivities)
        } header: {
            Text("收合時")
        } footer: {
            Text("例如音樂播放時又開始計時，或正在使用麥克風、螢幕錄影：瀏海左右兩側各顯示一個。關掉的話只顯示優先的那一個（計時器 > 音樂）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("隱藏動態島", isOn: $preferences.islandHidden)
        } header: {
            Text("顯示")
        } footer: {
            Text("隱藏後也可以從選單列的膠囊圖示再打開。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                launchAtLoginError = "無法變更：\(error.localizedDescription)"
            }
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

struct NotificationSettings: View {
    @Bindable var preferences: Preferences
    let focus: FocusMonitor

    var body: some View {
        Section("系統狀態") {
            Toggle("插上電源、低電量與充飽電", isOn: $preferences.batteryAlertsEnabled)
            Toggle("藍牙耳機連線與中斷", isOn: $preferences.bluetoothAlertsEnabled)
            Toggle("調整音量與靜音", isOn: $preferences.volumeAlertsEnabled)
            Toggle("專注模式開啟與關閉", isOn: $preferences.focusAlertsEnabled)
            if preferences.focusAlertsEnabled, focus.needsFullDiskAccess {
                SettingsNote("macOS 沒有公開專注模式的狀態，需要在「完整磁碟取用權限」中允許動態島。") {
                    Button("打開系統設定") { Self.openFullDiskAccessSettings() }
                }
            }
        }

        Section {
            Toggle("麥克風使用中", isOn: $preferences.microphoneIndicatorEnabled)
            Toggle("螢幕錄影或分享中", isOn: $preferences.screenRecordingIndicatorEnabled)
                .disabled(!ScreenRecordingMonitor.isSupported)
        } header: {
            Text("隱私指示")
        } footer: {
            Text("開始和停止使用時各提示一次；使用中時展開的頂部條會顯示橘色（麥克風）或紫色（螢幕錄影）的圖示，正在播音樂或計時的話，瀏海右側也會一直顯示。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Toggle("顯示正在播放", isOn: $preferences.musicEnabled)
        }

        Section("收合時") {
            Toggle("在瀏海兩側顯示封面與音波", isOn: $preferences.musicCompactEnabled)
        }
        .disabled(!preferences.musicEnabled)

        Section {
            LabeledContent("資料來源", value: nowPlaying.backend.title)
        } footer: {
            Text("全系統模式支援任何 App（包含瀏覽器裡的影片）；如果 macOS 擋掉這個做法，會改用只支援 Music 與 Spotify 的模式。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShelfSettings: View {
    @Bindable var preferences: Preferences
    let shelf: ShelfModel

    var body: some View {
        Section {
            Toggle("啟用檔案櫃", isOn: $preferences.shelfEnabled)
        } footer: {
            Text("把檔案拖到瀏海就會展開，可以放進檔案櫃或直接 AirDrop。項目可以拖出、雙擊開啟，右鍵有更多選項。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("內容") {
            LabeledContent("目前的檔案", value: "\(shelf.items.count) 個")
            SettingsNote("最多 \(ShelfModel.maxItems) 個；只記住檔案的位置，不會複製檔案本身。") {
                Button("清空檔案櫃") { shelf.removeAll() }
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
            Toggle("剪貼簿紀錄", isOn: $preferences.clipboardEnabled)
            Toggle("拷貝或剪下時在瀏海顯示動畫", isOn: $preferences.clipboardAlertsEnabled)
                .disabled(!preferences.clipboardEnabled)
        }

        Section {
            LabeledContent("觸控板滑動速度") {
                HStack(spacing: 8) {
                    Text("慢").foregroundStyle(.secondary)
                    Slider(value: $preferences.clipboardWheelSpeed, in: WheelTracker.speedRange, step: 0.05)
                        .frame(width: 160)
                    Text("快").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("滾輪")
        } footer: {
            Text("展開剪貼簿時也可以用 ↑ ↓ 選擇、Return 複製、Esc 收合。滑鼠滾輪固定一格跳一筆。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!preferences.clipboardEnabled)

        Section {
            LabeledContent("目前的紀錄", value: "\(clipboard.items.count) 筆")
            SettingsNote("最多保留 \(ClipboardModel.maxItems) 筆，只存在記憶體裡，結束 App 就清掉。") {
                Button("清除紀錄") { clipboard.removeAll() }
                    .disabled(clipboard.items.isEmpty)
            }
        } header: {
            Text("紀錄")
        } footer: {
            Text("密碼管理器標示為隱藏的內容不會記錄。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!preferences.clipboardEnabled)
    }
}

struct ClockSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Section {
            Toggle("計時器與番茄鐘", isOn: $preferences.timerEnabled)
        }

        Section("番茄鐘") {
            Stepper("專注 \(preferences.focusMinutes) 分鐘", value: $preferences.focusMinutes, in: 5...120, step: 5)
            Stepper("短休息 \(preferences.shortBreakMinutes) 分鐘", value: $preferences.shortBreakMinutes, in: 1...30)
            Stepper("總共 \(preferences.pomodoroRounds) 輪專注", value: $preferences.pomodoroRounds, in: 1...12)
            Stepper("長休息 \(preferences.longBreakMinutes) 分鐘", value: $preferences.longBreakMinutes, in: 5...60, step: 5)
            Stepper("每 \(preferences.longBreakInterval) 次專注後長休息", value: $preferences.longBreakInterval, in: 2...8)
            Toggle("自動開始下一段", isOn: $preferences.pomodoroAutoStart)
        }
        .disabled(!preferences.timerEnabled)

        Section {
            HStack {
                Picker("提示音", selection: $preferences.timerSound) {
                    ForEach(TimerAlert.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Button("試聽") { TimerAlert.preview(preferences.timerSound) }
            }
            Toggle("響的時候先暫停正在播的音樂，響完再繼續", isOn: $preferences.timerPausesMusic)
        } header: {
            Text("時間到的提示")
        } footer: {
            Text("提示音會以最大音量響 \(TimerAlert.repeatCount) 次。macOS 沒有辦法只把其他 App 的聲音調小，所以用暫停再繼續的方式。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!preferences.timerEnabled)
    }
}

struct AboutSettings: View {
    var body: some View {
        Section {
            LabeledContent("版本", value: Self.version)
        }

        Section("第三方元件") {
            Text("全系統「正在播放」使用 mediaremote-adapter（BSD-3-Clause，© Jonas van den Berg 與貢獻者），授權條款在 App 的 Resources 資料夾內。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "開發版"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(short)（\(build)）"
    }
}
