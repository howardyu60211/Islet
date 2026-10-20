#if DEBUG
import AppKit
import SwiftUI

/// Debug 用：`Islet --snapshots <資料夾>` 把每一種狀態畫成 PNG，不用螢幕錄製權限也能檢查外觀。
/// 紅框是實體瀏海的位置，用來對齊；加 `--no-guides` 就不畫（給 README 用的截圖）。
enum SnapshotRenderer {
    struct Scenario {
        let name: String
        let configure: (IslandViewModel) -> Void
    }

    static func renderAll(to directory: URL, showsNotchGuide: Bool = true, extraScenarios: [Scenario] = []) {
        RenderingContext.isSnapshot = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "com.howardyu.Islet.snapshots") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.hapticFeedback = false

        let battery = BatteryMonitor()
        battery.apply(BatteryState(level: 76, isCharging: false, isPluggedIn: false, isCharged: false))

        for scenario in baseScenarios + extraScenarios {
            let nowPlaying = NowPlayingModel()
            nowPlaying.apply(.debugSample)
            let timer = TimerModel(preferences: preferences)
            let shelf = ShelfModel(defaults: defaults)
            shelf.removeAll()
            let clipboard = ClipboardModel(pasteboard: NSPasteboard(name: NSPasteboard.Name("com.howardyu.Islet.snapshots")))
            let island = IslandViewModel(
                preferences: preferences,
                battery: battery,
                nowPlaying: nowPlaying,
                timer: timer,
                shelf: shelf,
                clipboard: clipboard,
                backgroundApps: sampleBackgroundApps(defaults: defaults, filled: false)
            )
            island.geometry = NotchGeometry(
                notchSize: CGSize(width: 179, height: 32),
                screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                centerX: 735,
                hasPhysicalNotch: true
            )
            scenario.configure(island)
            let renderer = ImageRenderer(content: SnapshotBackdrop(island: island, showsNotchGuide: showsNotchGuide))
            renderer.scale = 2
            guard let png = renderer.nsImage?.pngData() else {
                print("✗ \(scenario.name)")
                continue
            }
            let url = directory.appendingPathComponent("\(scenario.name).png")
            try? png.write(to: url)
            print("✓ \(url.path)")
        }
    }

    /// 設定視窗的每一頁。Form 和 List 是 AppKit 畫的，ImageRenderer 畫不出來，所以放進螢幕外的視窗再擷取。
    static func renderSettings(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "com.howardyu.Islet.snapshots") ?? .standard
        let preferences = Preferences(defaults: defaults)
        let clipboard = ClipboardModel(pasteboard: NSPasteboard(name: NSPasteboard.Name("com.howardyu.Islet.snapshots")))
        for pane in SettingsPane.allCases {
            let view = SettingsView(
                preferences: preferences,
                nowPlaying: NowPlayingModel(),
                focus: FocusMonitor(),
                shelf: ShelfModel(defaults: defaults),
                clipboard: clipboard,
                backgroundApps: sampleBackgroundApps(defaults: defaults, filled: true),
                initialPane: pane
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFront(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            guard let content = window.contentView,
                  let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
            else { continue }
            content.cacheDisplay(in: content.bounds, to: rep)
            let url = directory.appendingPathComponent("settings-\(pane.rawValue).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("✓ \(url.path)")
            window.orderOut(nil)
        }
    }

    private static var baseScenarios: [Scenario] {
        let airPods = BluetoothDeviceSnapshot(
            name: "AirPods Pro",
            address: "00:00:00:00:00:01",
            symbolName: "airpods.pro",
            battery: HeadphoneBattery(left: 82, right: 79, caseLevel: 45)
        )
        return [
            Scenario(name: "01-idle") { $0.nowPlaying.apply(nil) },
            Scenario(name: "02-compact-charging") { $0.post(IslandEvent(kind: .charging(level: 76))) },
            Scenario(name: "02b-compact-unplugged") { $0.post(IslandEvent(kind: .unplugged(level: 76))) },
            Scenario(name: "03-banner-bluetooth") { $0.post(IslandEvent(kind: .bluetooth(device: airPods, connected: true))) },
            Scenario(name: "04-banner-low-battery") { $0.post(IslandEvent(kind: .lowBattery(level: 10))) },
            Scenario(name: "05-banner-timer") {
                $0.post(IslandEvent(kind: .timerFinished(
                    title: tr("專注時間結束", "Focus time's over"),
                    subtitle: tr("短休息 5 分鐘吧", "Time for a 5-minute short break")
                )))
            },
            Scenario(name: "06-expanded-media") { $0.expand(tab: .media) },
            Scenario(name: "06b-expanded-media-shuffle-repeat") { island in
                var info = NowPlayingInfo.debugSample
                info.shuffleMode = 3
                info.repeatMode = 2
                island.nowPlaying.apply(info)
                island.expand(tab: .media)
            },
            Scenario(name: "07-expanded-shelf") { island in
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                island.shelf.add([
                    root.appendingPathComponent("SnapshotRenderer.swift"),
                    URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                    URL(fileURLWithPath: "/System/Library/Desktop Pictures"),
                ])
                island.expand(tab: .shelf)
            },
            Scenario(name: "07b-expanded-shelf-empty") { $0.expand(tab: .shelf) },
            Scenario(name: "07c-shelf-drop-zones") { $0.debugShowDropZones() },
            Scenario(name: "08-expanded-timer") { island in
                island.timer.setMode(.pomodoro)
                island.timer.finish()
                island.timer.finish()
                island.timer.start()
                island.expand(tab: .timer)
            },
            Scenario(name: "08b-expanded-countdown") { $0.expand(tab: .timer) },
            Scenario(name: "09-compact-now-playing") { _ in },
            Scenario(name: "10-compact-timer") { island in
                island.nowPlaying.apply(nil)
                island.timer.setCountdown(minutes: 25)
                island.timer.start()
            },
            Scenario(name: "11-compact-volume") { $0.post(IslandEvent(kind: .volume(level: 60, muted: false))) },
            Scenario(name: "11b-compact-volume-muted") { $0.post(IslandEvent(kind: .volume(level: 60, muted: true))) },
            Scenario(name: "12-compact-focus-on") { $0.post(IslandEvent(kind: .focus(.debugSample, active: true))) },
            Scenario(name: "12b-compact-focus-off") { $0.post(IslandEvent(kind: .focus(.debugSample, active: false))) },
            Scenario(name: "13-compact-microphone") {
                $0.post(IslandEvent(kind: .sensor(.microphone, app: .debugSample, active: true)))
            },
            Scenario(name: "13b-compact-screen-recording") {
                $0.post(IslandEvent(kind: .sensor(.screenRecording, app: nil, active: true)))
            },
            Scenario(name: "13c-compact-microphone-stopped") {
                $0.post(IslandEvent(kind: .sensor(.microphone, app: .debugSample, active: false)))
            },
            Scenario(name: "14-expanded-clipboard") { island in
                fillClipboard(island)
                island.expand(tab: .clipboard)
            },
            Scenario(name: "14c-expanded-clipboard-wheel") { island in
                fillClipboard(island)
                island.expand(tab: .clipboard)
                island.selectClipboardItem(at: 2)
            },
            Scenario(name: "14b-expanded-clipboard-empty") { $0.expand(tab: .clipboard) },
            Scenario(name: "15-compact-clipboard-text") {
                $0.post(IslandEvent(kind: .clipboard(ClipboardSummary(id: UUID(), kind: .text, excerpt: tr("會議改到週四下午三點", "Meeting moved to Thursday 3 PM"), image: nil))))
            },
            Scenario(name: "15b-compact-clipboard-image") { island in
                let image = DebugArtwork.pngData.flatMap(NSImage.init(data:))?.thumbnail(maxSide: 160)
                island.post(IslandEvent(kind: .clipboard(ClipboardSummary(id: UUID(), kind: .image, excerpt: "", image: image))))
            },
            Scenario(name: "15c-compact-clipboard-files") {
                $0.post(IslandEvent(kind: .clipboard(ClipboardSummary(id: UUID(), kind: .files(count: 3), excerpt: tr("報告.pdf", "Report.pdf"), image: nil))))
            },
            Scenario(name: "16-compact-pair-music-timer") { island in
                island.timer.setCountdown(minutes: 25)
                island.timer.start()
            },
            Scenario(name: "16b-compact-pair-music-microphone") { island in
                island.microphone.debugSetActive(true, apps: [.debugSample])
            },
            Scenario(name: "17-expanded-background-apps") { island in
                fillBackgroundApps(island.backgroundApps)
                island.expand(tab: .media)
            },
            Scenario(name: "16c-compact-pair-timer-microphone") { island in
                island.nowPlaying.apply(nil)
                island.microphone.debugSetActive(true, apps: [.debugSample])
                island.timer.setCountdown(minutes: 120)
                island.timer.start()
            },
        ]
    }
}

extension SnapshotRenderer {
    /// 背景程式快照用系統內建的 App 當範例；Calculator 與 Stickies 假裝在執行。
    static func sampleBackgroundApps(defaults: UserDefaults, filled: Bool) -> BackgroundAppsModel {
        defaults.removeObject(forKey: BackgroundAppsModel.defaultsKey)
        let model = BackgroundAppsModel(defaults: defaults, runningBundleIdentifiers: { ["com.apple.calculator", "com.apple.Stickies"] })
        if filled { fillBackgroundApps(model) }
        return model
    }

    static func fillBackgroundApps(_ model: BackgroundAppsModel) {
        for name in ["Calculator", "Stickies", "Chess"] {
            model.add(URL(fileURLWithPath: "/System/Applications/\(name).app"))
        }
    }

    /// 剪貼簿快照用的假紀錄（最新的在前面）。
    static func fillClipboard(_ island: IslandViewModel) {
        let samples: [(String, String?, String?)] = [
            (tr("報告初稿第三版", "Report draft v3"), "Pages", "com.apple.iWork.Pages"),
            ("brew install --cask iina", "Terminal", "com.apple.Terminal"),
            ("let island = IslandViewModel(preferences: preferences)", "Xcode", "com.apple.dt.Xcode"),
            ("https://developer.apple.com/documentation/swiftui", "Safari", "com.apple.Safari"),
            (tr("會議改到週四下午三點，地點在 7 樓大會議室。記得帶上次的簡報。", "Meeting moved to Thursday 3 PM in the big room on 7F. Bring last week's slides."), "Messages", "com.apple.MobileSMS"),
            (tr("台北市信義區市府路 1 號", "1 Apple Park Way, Cupertino"), "Maps", "com.apple.Maps"),
        ]
        for (value, app, bundleID) in samples.reversed() {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("snapshot-\(UUID().uuidString)"))
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            if let item = ClipboardModel.capture(pasteboard, sourceApp: app, sourceBundleIdentifier: bundleID) {
                island.clipboard.insert(item)
            }
            pasteboard.releaseGlobally()
        }
    }
}

/// 假的桌布＋選單列，再把島和瀏海位置疊上去。
private struct SnapshotBackdrop: View {
    let island: IslandViewModel
    let showsNotchGuide: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.45, blue: 0.75), Color(red: 0.6, green: 0.4, blue: 0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: island.notchSize.height)
            IslandRootView(island: island)
            if showsNotchGuide {
                Rectangle()
                    .stroke(.red.opacity(0.8), lineWidth: 0.5)
                    .frame(width: island.notchSize.width, height: island.notchSize.height)
            }
        }
        .frame(width: NotchWindowController.panelSize.width, height: NotchWindowController.panelSize.height)
    }
}
#endif
