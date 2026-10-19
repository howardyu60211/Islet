import AppKit

/// App 進入點：純 AppKit 啟動（選單列圖示 + 貼在瀏海上的面板），不出現在 Dock。
public enum IsletApplication {
    public static func run() {
        let app = NSApplication.shared
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(index + 1) {
            SnapshotRenderer.renderAll(
                to: URL(fileURLWithPath: arguments[index + 1]),
                showsNotchGuide: !arguments.contains("--no-guides")
            )
            return
        }
        if let index = arguments.firstIndex(of: "--settings-snapshots"), arguments.indices.contains(index + 1) {
            SnapshotRenderer.renderSettings(to: URL(fileURLWithPath: arguments[index + 1]))
            return
        }
        #endif
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // 收到 SIGTERM（例如 pkill、登出）時走正常的結束流程，才會順便結束 adapter 子程序
        signal(SIGTERM, SIG_IGN)
        let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSource.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        terminationSource.resume()
        withExtendedLifetime((delegate, terminationSource)) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = AppServices()
        services.start()
        self.services = services
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.stop()
    }

    /// 已經在執行時又從 Finder／Spotlight 打開：顯示設定（選單列圖示可能被隱藏了）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services?.showSettings()
        return false
    }
}
