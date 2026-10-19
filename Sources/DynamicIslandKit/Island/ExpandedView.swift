import SwiftUI

/// 展開後的完整面板：上方是跟瀏海同高的頂部條，下方是目前分頁的內容。
struct ExpandedView: View {
    let island: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeader(island: island)
                .frame(height: island.notchSize.height)
            tabContent
                // 滑動切歌時只有下面的內容滑動，頂部條固定不動
                .offset(x: island.swipeOffset)
                .opacity(island.swipeOpacity)
                .id(island.selectedTab)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if island.availableTabs.isEmpty {
            Text(tr("所有功能都已關閉，可以到設定裡打開。", "All features are turned off. You can turn them on in Settings."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            switch island.selectedTab {
            case .media:
                MediaPlayerView(model: island.nowPlaying)
            case .shelf:
                ShelfPanelView(island: island)
            case .clipboard:
                ClipboardPanelView(island: island)
            case .timer:
                TimerPanelView(model: island.timer, preferences: island.preferences)
            }
        }
    }
}

/// 頂部條：瀏海左邊是分頁，右邊是電量、設定與結束；中間留給實體瀏海。
private struct ExpandedHeader: View {
    let island: IslandViewModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(island.availableTabs) { tab in
                    TabButton(tab: tab, isSelected: island.selectedTab == tab) {
                        withAnimation(.smooth(duration: 0.2)) {
                            island.selectedTab = tab
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            Color.clear
                .frame(width: island.notchSize.width + 12)

            HStack(spacing: 10) {
                SensorIndicators(island: island)
                BatteryIndicator(battery: island.battery)
                HeaderIconButton(symbol: "gearshape.fill", label: tr("設定", "Settings")) {
                    island.openSettings()
                }
                HeaderIconButton(symbol: "power", label: tr("結束動態島", "Quit DynamicIsland")) {
                    NSApp.terminate(nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
        }
    }
}

/// 麥克風／螢幕錄影使用中的小圖示（和系統選單列的指示燈同色）。
private struct SensorIndicators: View {
    let island: IslandViewModel

    var body: some View {
        let sensors = island.activeSensors
        if !sensors.isEmpty {
            HStack(spacing: 4) {
                ForEach(sensors, id: \.self) { sensor in
                    Image(systemName: sensor.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(sensor.tint))
                        .help(help(for: sensor))
                        .accessibilityLabel(tr("\(sensor.title)使用中", "\(sensor.title) in use"))
                }
            }
        }
    }

    private func help(for sensor: Sensor) -> String {
        switch sensor {
        case .microphone:
            let names = island.microphone.apps.map(\.name)
            return names.isEmpty
                ? tr("麥克風使用中", "Microphone in use")
                : tr("麥克風使用中：\(names.joined(separator: "、"))", "Microphone in use: \(names.joined(separator: ", "))")
        case .screenRecording:
            return tr("螢幕正在被錄影或分享", "Screen is being recorded or shared")
        }
    }
}

private struct TabButton: View {
    let tab: IslandTab
    let isSelected: Bool
    let action: () -> Void

    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .frame(width: 32, height: 22)
                .background(
                    Capsule().fill(.white.opacity(isSelected ? 0.18 : (isHovering ? 0.08 : 0)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title)
    }
}

struct HeaderIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @ViewState private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.6))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
