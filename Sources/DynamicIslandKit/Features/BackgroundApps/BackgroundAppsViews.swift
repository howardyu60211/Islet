import SwiftUI
import UniformTypeIdentifiers

/// 展開後頂部條右側的背景程式：執行中的是彩色的，沒在執行的變灰。點一下打開，右鍵有更多選項。
struct BackgroundAppsTray: View {
    let island: IslandViewModel
    /// 頂部條放得下的數量；超過的收進最後的「…」選單。
    let maxVisible: Int

    var body: some View {
        let model = island.backgroundApps
        let apps = model.apps
        let visible = apps.count > maxVisible ? Array(apps.prefix(maxVisible - 1)) : apps
        let overflow = Array(apps.dropFirst(visible.count))
        HStack(spacing: 6) {
            ForEach(visible) { app in
                BackgroundAppButton(island: island, app: app)
            }
            if !overflow.isEmpty {
                Menu {
                    ForEach(overflow) { app in
                        Menu(app.name) {
                            BackgroundAppMenuItems(island: island, app: app)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("其他背景程式", "More apps"))
            }
        }
    }
}

private struct BackgroundAppButton: View {
    let island: IslandViewModel
    let app: BackgroundAppsModel.App

    @ViewState private var isHovering = false

    var body: some View {
        let model = island.backgroundApps
        let running = model.isRunning(app)
        let status = running ? tr("\(app.name)（執行中）", "\(app.name) (running)") : tr("\(app.name)（未執行）", "\(app.name) (not running)")
        Button {
            island.collapse()
            model.open(app)
        } label: {
            Image(nsImage: model.icon(for: app))
                .resizable()
                .frame(width: 18, height: 18)
                .saturation(running ? 1 : 0)
                .opacity(running ? 1 : 0.4)
                .scaleEffect(isHovering ? 1.12 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.15), value: isHovering)
        .help(status)
        .accessibilityLabel(status)
        .contextMenu {
            BackgroundAppMenuItems(island: island, app: app)
        }
    }
}

/// 頂部條圖示的右鍵選單（「…」選單裡的子選單也用這個）。
private struct BackgroundAppMenuItems: View {
    let island: IslandViewModel
    let app: BackgroundAppsModel.App

    var body: some View {
        let model = island.backgroundApps
        if model.isRunning(app) {
            Button(tr("打開設定", "Open Settings")) { open() }
            Button(tr("結束", "Quit")) { model.quit(app) }
        } else {
            Button(tr("啟動", "Launch")) { open() }
        }
        Divider()
        Button(tr("在 Finder 中顯示", "Show in Finder")) { model.revealInFinder(app) }
        Button(tr("從背景程式移除", "Remove from App Tray")) { model.remove(app) }
    }

    private func open() {
        island.collapse()
        island.backgroundApps.open(app)
    }
}

/// 設定裡的「背景程式」頁。
struct BackgroundAppsSettings: View {
    let model: BackgroundAppsModel

    var body: some View {
        Section {
            if model.apps.isEmpty {
                Text(tr("還沒有加入任何 App。", "No apps added yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: model.icon(for: app))
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(app.name)
                    Spacer()
                    Text(model.isRunning(app) ? tr("執行中", "Running") : tr("未執行", "Not Running"))
                        .font(.caption)
                        .foregroundStyle(model.isRunning(app) ? .green : .secondary)
                    Button {
                        model.remove(app)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(tr("移除", "Remove"))
                }
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            HStack {
                Spacer()
                addMenu
            }
        } header: {
            Text(tr("App", "Apps"))
        } footer: {
            SettingsFooter(tr(
                "先在各 App 自己的設定裡關掉選單列圖示（例如 LinearMouse、DockDoor），再加到這裡。點頂部條上的圖示會重新打開該 App，大多會顯示它的設定視窗；右鍵可以結束或移除。可以拖曳調整順序。加入 App 後，頂部條就不再顯示電量。",
                "First turn off the menu bar icon in each app’s own settings (for example LinearMouse or DockDoor), then add it here. Clicking its icon in the top bar reopens the app, which usually shows its settings window; right-click to quit or remove it. Drag to reorder. Once you add an app, the top bar no longer shows the battery level."
            ))
        }
    }

    private var addMenu: some View {
        Menu(tr("加入 App…", "Add App…")) {
            let candidates = model.runningMenuBarApps()
            if !candidates.isEmpty {
                Section(tr("正在執行的選單列 App", "Running Menu Bar Apps")) {
                    ForEach(candidates, id: \.self) { url in
                        Button {
                            model.add(url)
                        } label: {
                            Label {
                                Text(BackgroundAppsModel.displayName(of: url))
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            }
                        }
                    }
                }
            }
            Button(tr("選擇其他 App…", "Choose Another App…")) { chooseApps() }
        }
        .fixedSize()
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = tr("加入", "Add")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { model.add($0) }
    }
}
