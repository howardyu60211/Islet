import SwiftUI

/// 設定視窗左側的大區塊，跟系統設定一樣一個區塊一頁。
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case notifications
    case music
    case shelf
    case clipboard
    case clock
    case backgroundApps
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: tr("一般", "General")
        case .notifications: tr("通知", "Notifications")
        case .music: tr("音樂", "Music")
        case .shelf: tr("檔案櫃", "Shelf")
        case .clipboard: tr("剪貼簿", "Clipboard")
        case .clock: tr("時鐘", "Clock")
        case .backgroundApps: tr("背景程式", "App Tray")
        case .about: tr("關於", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .notifications: "bell.fill"
        case .music: "music.note"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .clock: "timer"
        case .backgroundApps: "menubar.rectangle"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .notifications: .red
        case .music: .pink
        case .shelf: .blue
        case .clipboard: .orange
        case .clock: .green
        case .backgroundApps: .indigo
        case .about: .gray
        }
    }

    var summary: String {
        switch self {
        case .general: tr("語言、啟動、展開方式與動態島的顯示。", "Language, startup, how the island expands, and whether it’s shown.")
        case .notifications: tr("電源、耳機、音量等系統狀態改變時，在瀏海跳出提示。", "Alerts in the notch when power, headphones, volume and other system states change.")
        case .music: tr("在動態島顯示任何 App 正在播放的音樂並控制播放。", "Shows what any app is playing on the island and lets you control it.")
        case .shelf: tr("把檔案拖到瀏海暫放，之後再拖出、打開或用 AirDrop 傳送。", "Drop files on the notch to hold them, then drag them out, open them or AirDrop them later.")
        case .clipboard: tr("記錄最近拷貝的文字、連結、圖片與檔案，點一下就能再拷貝。", "Keeps recently copied text, links, images and files; click one to copy it again.")
        case .clock: tr("計時器與番茄鐘，時間到時在瀏海提示並播放提示音。", "A timer and Pomodoro that alert you in the notch with a sound when time’s up.")
        case .backgroundApps: tr("把關掉選單列圖示的 App 收在展開後的頂部條，看得到有沒有在執行，點一下就能打開設定。", "Keeps apps whose menu bar icons you’ve turned off in the expanded top bar, so you can see they’re running and open their settings with a click.")
        case .about: tr("版本與授權資訊。", "Version and license information.")
        }
    }
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let nowPlaying: NowPlayingModel
    let focus: FocusMonitor
    let shelf: ShelfModel
    let clipboard: ClipboardModel
    let backgroundApps: BackgroundAppsModel

    @ViewState private var selection: SettingsPane?

    init(
        preferences: Preferences,
        nowPlaying: NowPlayingModel,
        focus: FocusMonitor,
        shelf: ShelfModel,
        clipboard: ClipboardModel,
        backgroundApps: BackgroundAppsModel,
        initialPane: SettingsPane = .general
    ) {
        self.preferences = preferences
        self.nowPlaying = nowPlaying
        self.focus = focus
        self.shelf = shelf
        self.clipboard = clipboard
        self.backgroundApps = backgroundApps
        _selection = ViewState(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(pane: pane, size: 20)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = selection ?? .general
            Form {
                SettingsHeader(pane: pane)
                content(for: pane)
            }
            .formStyle(.grouped)
            .id(pane)
        }
        .frame(width: 720, height: 560)
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettings(preferences: preferences)
        case .notifications: NotificationSettings(preferences: preferences, focus: focus)
        case .music: MusicSettings(preferences: preferences, nowPlaying: nowPlaying)
        case .shelf: ShelfSettings(preferences: preferences, shelf: shelf)
        case .clipboard: ClipboardSettings(preferences: preferences, clipboard: clipboard)
        case .clock: ClockSettings(preferences: preferences)
        case .backgroundApps: BackgroundAppsSettings(model: backgroundApps)
        case .about: AboutSettings()
        }
    }
}

/// 系統設定風格的彩色圓角方塊圖示。
struct SettingsIcon: View {
    let pane: SettingsPane
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(pane.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// 每一頁最上面的大圖示、標題與說明。
private struct SettingsHeader: View {
    let pane: SettingsPane

    var body: some View {
        Section {
            HStack(spacing: 14) {
                SettingsIcon(pane: pane, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title)
                        .font(.title2.bold())
                    Text(pane.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Section 下方的說明文字。Form 的 footer 預設靠右，換行後第二行會貼到右邊，所以固定靠左。
struct SettingsFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 跟 Section 標題與列內的文字對齊
            .padding(.horizontal, 10)
    }
}

/// 說明文字加一個小按鈕（打開系統設定、清除紀錄之類）。
struct SettingsNote<Accessory: View>: View {
    let text: String
    @ViewBuilder let accessory: Accessory

    init(_ text: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory
                .controlSize(.small)
        }
    }
}
