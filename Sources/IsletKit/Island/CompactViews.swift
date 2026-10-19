import SwiftUI

/// 收合狀態：內容放在實體瀏海的左右兩側。
struct CompactView: View {
    let island: IslandViewModel
    let activity: CompactActivity

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: activity.sideWidth, alignment: .leading)
                .padding(.leading, 4)
            Spacer(minLength: 0)
            trailing
                .frame(width: activity.sideWidth, alignment: .trailing)
                .padding(.trailing, 4)
        }
        .frame(height: island.notchSize.height)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .charging:
            Label {
                Text(tr("充電中", "Charging"))
            } icon: {
                Image(systemName: "bolt.fill")
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(.green)
        case .unplugged:
            Label {
                Text(tr("使用電池", "On Battery"))
            } icon: {
                Image(systemName: "powerplug.portrait")
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(.white.opacity(0.85))
        case .nowPlaying:
            NowPlayingCompactLeading(model: island.nowPlaying)
                // 收合時只有封面跟著滑，音波和島的形狀不動
                .offset(x: island.swipeOffset * 0.12)
                .opacity(island.swipeOpacity)
        case .timer:
            TimerCompactLeading(model: island.timer)
        case .volume(let level, let muted):
            Image(systemName: VolumeGlyph.symbol(level: level, muted: muted))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        case .focus(let mode, let active):
            Label {
                Text(mode.name)
            } icon: {
                Image(systemName: mode.symbolName)
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(active ? mode.tint : .white.opacity(0.6))
        case .sensor(let sensor, _, let active):
            Label {
                Text(sensor.compactTitle)
            } icon: {
                Image(systemName: sensor.symbol)
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(active ? sensor.tint : .white.opacity(0.6))
        case .clipboard:
            ClipboardCompactLeading()
        case .pair(let activity, _):
            LiveActivitySide(island: island, activity: activity, edge: .leading)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity {
        case .charging(let level):
            HStack(spacing: 4) {
                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.green)
                BatteryGlyph(level: level, isCharging: true, tint: .green)
            }
        case .unplugged(let level):
            HStack(spacing: 4) {
                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level <= 20 ? .red : .white)
                BatteryGlyph(level: level, isCharging: false, tint: level <= 20 ? .red : .white)
            }
        case .nowPlaying:
            NowPlayingCompactTrailing(model: island.nowPlaying)
        case .timer:
            TimerCompactTrailing(model: island.timer)
        case .volume(let level, let muted):
            HStack(spacing: 6) {
                VolumeGlyph(level: level, muted: muted)
                Text(muted ? tr("靜音", "Muted") : "\(level)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(muted ? .white.opacity(0.6) : .white)
                    .contentTransition(.numericText(value: Double(level)))
                    .frame(width: 34, alignment: .trailing)
            }
        case .focus(let mode, let active):
            Text(active ? tr("開啟", "On") : tr("關閉", "Off"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? mode.tint : .white.opacity(0.6))
        case .sensor(let sensor, let app, let active):
            HStack(spacing: 5) {
                if active, let icon = app?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .help(app?.name ?? "")
                }
                Text(active ? tr("使用中", "In Use") : tr("已停止", "Stopped"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? sensor.tint : .white.opacity(0.6))
            }
        case .clipboard(let summary):
            ClipboardCompactTrailing(summary: summary)
        case .pair(_, let activity):
            LiveActivitySide(island: island, activity: activity, edge: .trailing)
        }
    }
}

/// 兩個活動並排時，其中一個活動擠在瀏海的一側：內容從瀏海往外排，靠瀏海的那一側對齊。
private struct LiveActivitySide: View {
    let island: IslandViewModel
    let activity: LiveActivity
    let edge: HorizontalEdge

    var body: some View {
        HStack(spacing: 6) {
            switch activity {
            case .nowPlaying:
                NowPlayingCompactLeading(model: island.nowPlaying)
                    .offset(x: island.swipeOffset * 0.12)
                    .opacity(island.swipeOpacity)
                NowPlayingCompactTrailing(model: island.nowPlaying)
                    .scaleEffect(0.85)
            case .timer:
                TimerCompactLeading(model: island.timer)
                // 超過一小時（1:59:59）時縮小一點，不要壓到瀏海底下
                TimerCompactTrailing(model: island.timer)
                    .minimumScaleFactor(0.7)
            case .sensors(let sensors):
                ForEach(sensors, id: \.self) { sensor in
                    Image(systemName: sensor.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(sensor.tint)
                        .help(tr("\(sensor.title)使用中", "\(sensor.title) in use"))
                }
                if sensors.contains(.microphone), let app = island.microphone.apps.first, let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .help(app.name)
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
        // CompactView 外側的 4pt 邊距會把這一側往瀏海推，靠瀏海那邊要留空
        .padding(edge == .leading ? .trailing : .leading, 6)
    }
}

/// 拷貝／剪下時左側的圖示：出現後彈一下（只播一次，不會持續重畫）。
private struct ClipboardCompactLeading: View {
    @ViewState private var bounce = false

    var body: some View {
        Label {
            Text(tr("剪貼簿", "Copied"))
        } icon: {
            Image(systemName: "doc.on.clipboard.fill")
                .symbolEffect(.bounce.up, value: bounce)
        }
        .labelStyle(CompactLabelStyle())
        .foregroundStyle(.cyan)
        .task {
            // 等島長出來、內容淡入後再彈
            try? await Task.sleep(for: .milliseconds(180))
            bounce.toggle()
        }
    }
}

/// 拷貝／剪下時右側的內容預覽：圖片縮圖、檔案數量或文字開頭，從下面滑上來。
private struct ClipboardCompactTrailing: View {
    let summary: ClipboardSummary

    @ViewState private var isShown = RenderingContext.isSnapshot

    var body: some View {
        preview
            .offset(y: isShown ? 0 : 10)
            .opacity(isShown ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(duration: 0.4, bounce: 0.35)) { isShown = true }
            }
    }

    @ViewBuilder
    private var preview: some View {
        switch summary.kind {
        case .image:
            if let image = summary.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            }
        case .files(let count):
            Label {
                Text(count > 1 ? tr("\(count) 個檔案", "\(count) files") : summary.excerpt)
            } icon: {
                Image(systemName: "doc.fill")
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(.white.opacity(0.85))
        case .link:
            Label {
                Text(summary.excerpt)
            } icon: {
                Image(systemName: "link")
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(.blue)
        case .text:
            Text(summary.excerpt.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// 收合時的音量條。
struct VolumeGlyph: View {
    let level: Int
    let muted: Bool

    static func symbol(level: Int, muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 34 { return "speaker.wave.1.fill" }
        if level < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        let fraction = muted ? 0 : CGFloat(min(max(level, 0), 100)) / 100
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.2))
            Capsule()
                .fill(.white)
                .frame(width: 36 * fraction)
        }
        .frame(width: 36, height: 6)
        .accessibilityLabel(muted ? tr("靜音", "Muted") : tr("音量 \(level)%", "Volume \(level)%"))
    }
}

extension Sensor {
    /// 跟系統選單列的指示燈同色：麥克風橘色、螢幕錄影紫色。
    var tint: Color {
        switch self {
        case .microphone: .orange
        case .screenRecording: .purple
        }
    }
}

extension FocusMode {
    var tint: Color {
        switch tintName?.replacingOccurrences(of: "system", with: "").replacingOccurrences(of: "Color", with: "").lowercased() {
        case "purple": .purple
        case "orange": .orange
        case "teal": .teal
        case "mint": .mint
        case "green": .green
        case "blue": .blue
        case "red": .red
        case "yellow": .yellow
        case "pink": .pink
        case "cyan": .cyan
        case "brown": .brown
        case "gray", "grey": .gray
        default: .indigo
        }
    }
}

/// 收合狀態裡「圖示＋短文字」的樣式。
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 11, weight: .bold))
            configuration.title
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 往下長高的短暫通知。
struct BannerView: View {
    let island: IslandViewModel
    let event: IslandEvent

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: island.notchSize.height)
            HStack(spacing: 12) {
                icon
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                accessory
            }
            .padding(.horizontal, 16)
            .frame(height: IslandMetrics.bannerContentHeight)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var icon: some View {
        switch event.kind {
        case .charging, .fullyCharged:
            Image(systemName: "battery.100percent.bolt").foregroundStyle(.green)
        case .lowBattery:
            Image(systemName: "battery.25percent").foregroundStyle(.red)
        case .unplugged:
            Image(systemName: "powerplug.portrait").foregroundStyle(.white)
        case .bluetooth(let device, let connected):
            Image(systemName: device.symbolName)
                .foregroundStyle(connected ? .white : .white.opacity(0.5))
        case .timerFinished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
        case .volume(let level, let muted):
            Image(systemName: VolumeGlyph.symbol(level: level, muted: muted))
        case .focus(let mode, _):
            Image(systemName: mode.symbolName).foregroundStyle(mode.tint)
        case .sensor(let sensor, _, _):
            Image(systemName: sensor.symbol).foregroundStyle(sensor.tint)
        case .clipboard:
            Image(systemName: "doc.on.clipboard.fill").foregroundStyle(.cyan)
        }
    }

    private var title: String {
        switch event.kind {
        case .charging: tr("充電中", "Charging")
        case .fullyCharged: tr("已充飽電", "Fully Charged")
        case .unplugged: tr("使用電池", "On Battery")
        case .lowBattery: tr("電量不足", "Low Battery")
        case .bluetooth(let device, _): device.name
        case .timerFinished(let title, _): title
        case .volume: tr("音量", "Volume")
        case .focus(let mode, _): mode.name
        case .sensor(let sensor, _, _): sensor.title
        case .clipboard: tr("剪貼簿", "Clipboard")
        }
    }

    private var subtitle: String? {
        switch event.kind {
        case .charging: nil
        case .unplugged: tr("已拔除電源", "Unplugged")
        case .fullyCharged: tr("可以拔掉電源了", "You can unplug now")
        case .lowBattery(let level): tr("剩下 \(level)%，請接上電源", "\(level)% left — plug in soon")
        case .bluetooth(_, let connected): connected ? tr("已連線", "Connected") : tr("已中斷連線", "Disconnected")
        case .timerFinished(_, let subtitle): subtitle
        case .volume(let level, let muted): muted ? tr("靜音", "Muted") : "\(level)%"
        case .focus(_, let active): active ? tr("開啟", "On") : tr("關閉", "Off")
        case .sensor(_, let app, let active):
            active
                ? tr("\(app?.name ?? "有 App") 正在使用", "In use by \(app?.name ?? "an app")")
                : tr("已停止使用", "No longer in use")
        case .clipboard(let summary): summary.excerpt
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch event.kind {
        case .charging(let level):
            BatteryReadout(level: level, isCharging: true, tint: .green)
        case .fullyCharged:
            BatteryReadout(level: 100, isCharging: true, tint: .green)
        case .lowBattery(let level):
            BatteryReadout(level: level, isCharging: false, tint: .red)
        case .unplugged(let level):
            BatteryReadout(level: level, isCharging: false, tint: .white)
        case .bluetooth(let device, let connected):
            if connected, let battery = device.battery, !battery.isEmpty {
                HeadphoneBatteryView(battery: battery)
            }
        case .timerFinished, .volume, .focus, .sensor, .clipboard:
            EmptyView()
        }
    }
}

/// 「85% ▭」這種電量文字＋電池圖。
struct BatteryReadout: View {
    let level: Int
    let isCharging: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(level)%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
            BatteryGlyph(level: level, isCharging: isCharging, tint: tint)
        }
    }
}

/// 自己畫的電池圖示，填滿比例跟著電量走。
struct BatteryGlyph: View {
    let level: Int
    var isCharging = false
    var tint: Color = .white

    var body: some View {
        let fraction = CGFloat(min(max(level, 0), 100)) / 100
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: max(2, 19 * fraction))
                    .padding(2)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 25, height: 12)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.45))
                .frame(width: 1.5, height: 4)
        }
        .accessibilityLabel(tr("電量 \(level)%", "Battery \(level)%"))
    }
}

/// AirPods 左右耳與充電盒的電量。
struct HeadphoneBatteryView: View {
    let battery: HeadphoneBattery

    var body: some View {
        HStack(spacing: 10) {
            if let main = battery.main {
                item(label: nil, level: main)
            }
            if let left = battery.left {
                item(label: "L", level: left)
            }
            if let right = battery.right {
                item(label: "R", level: right)
            }
            if let caseLevel = battery.caseLevel {
                item(label: tr("盒", "C"), level: caseLevel)
            }
        }
    }

    private func item(label: String?, level: Int) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(level <= 20 ? Color.red : Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let label {
                    Text(label).font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: 20, height: 20)
            Text("\(level)%")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
