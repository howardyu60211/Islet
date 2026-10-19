import AppKit

/// 會被系統標示「使用中」的感測器。
enum Sensor: String, Hashable {
    case microphone
    case screenRecording

    var title: String {
        switch self {
        case .microphone: tr("麥克風", "Microphone")
        case .screenRecording: tr("螢幕錄影", "Screen Recording")
        }
    }

    /// 收合時瀏海旁邊的短名稱。
    var compactTitle: String {
        switch self {
        case .microphone: tr("麥克風", "Microphone")
        case .screenRecording: tr("螢幕錄影", "Recording")
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .screenRecording: "record.circle"
        }
    }
}

/// 正在使用感測器的 App。
struct SensorApp: Equatable {
    let name: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t

    /// 收合時旁邊的小圖示。
    var icon: NSImage? {
        if let app = NSRunningApplication(processIdentifier: processIdentifier), let icon = app.icon {
            return icon.bitmapCopy(pointSize: 32)
        }
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path).bitmapCopy(pointSize: 32)
    }

    /// 把錄音的行程對應到使用者看得到的 App：瀏覽器的分頁、App 的 helper 都算在主程式頭上。
    static func resolve(processIdentifier pid: pid_t, bundleIdentifier: String?) -> SensorApp? {
        for candidate in [responsibleProcess(for: pid), pid] {
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy == .regular {
                return SensorApp(app)
            }
        }
        // 「com.google.Chrome.helper」→「com.google.Chrome」
        if let bundleIdentifier {
            var parts = bundleIdentifier.split(separator: ".")
            while parts.count > 2 {
                parts.removeLast()
                let parent = parts.joined(separator: ".")
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: parent).first(where: { $0.activationPolicy == .regular }) {
                    return SensorApp(app)
                }
            }
        }
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return SensorApp(name: name, bundleIdentifier: app.bundleIdentifier, processIdentifier: pid)
        }
        return nil
    }

    private init(_ app: NSRunningApplication) {
        self.init(name: app.localizedName ?? app.bundleIdentifier ?? "App", bundleIdentifier: app.bundleIdentifier, processIdentifier: app.processIdentifier)
    }

    init(name: String, bundleIdentifier: String?, processIdentifier: pid_t) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    /// 系統記錄的「負責」行程（XPC 服務、WebKit 的 GPU 行程會指到開啟它的 App）。私有函式，找不到就用原本的 pid。
    private static let responsibleFunction: ResponsibleFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    private static func responsibleProcess(for pid: pid_t) -> pid_t {
        guard let responsibleFunction else { return pid }
        let responsible = responsibleFunction(pid)
        return responsible > 0 ? responsible : pid
    }
}
