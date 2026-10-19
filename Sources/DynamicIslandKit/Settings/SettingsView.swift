import SwiftUI

/// 設定視窗左側的大區塊，跟系統設定一樣一個區塊一頁。
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case notifications
    case music
    case shelf
    case clipboard
    case clock
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "一般"
        case .notifications: "通知"
        case .music: "音樂"
        case .shelf: "檔案櫃"
        case .clipboard: "剪貼簿"
        case .clock: "時鐘"
        case .about: "關於"
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
        case .about: .gray
        }
    }

    var summary: String {
        switch self {
        case .general: "啟動、展開方式與動態島的顯示。"
        case .notifications: "電源、耳機、音量等系統狀態改變時，在瀏海跳出提示。"
        case .music: "在動態島顯示任何 App 正在播放的音樂並控制播放。"
        case .shelf: "把檔案拖到瀏海暫放，之後再拖出、打開或用 AirDrop 傳送。"
        case .clipboard: "記錄最近拷貝的文字、連結、圖片與檔案，點一下就能再拷貝。"
        case .clock: "計時器與番茄鐘，時間到時在瀏海提示並播放提示音。"
        case .about: "版本與授權資訊。"
        }
    }
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let nowPlaying: NowPlayingModel
    let focus: FocusMonitor
    let shelf: ShelfModel
    let clipboard: ClipboardModel

    @ViewState private var selection: SettingsPane?

    init(preferences: Preferences, nowPlaying: NowPlayingModel, focus: FocusMonitor, shelf: ShelfModel, clipboard: ClipboardModel, initialPane: SettingsPane = .general) {
        self.preferences = preferences
        self.nowPlaying = nowPlaying
        self.focus = focus
        self.shelf = shelf
        self.clipboard = clipboard
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
