import Foundation
import Observation
import os

/// 一個專注模式（勿擾、睡眠、工作…）。
struct FocusMode: Equatable {
    let identifier: String
    let name: String
    let symbolName: String
    /// 系統顏色名稱，例如「systemIndigoColor」。
    let tintName: String?

    /// 系統內建的專注模式用介面語言的名稱與預設圖示；自訂的用使用者取的名字。
    init(identifier: String, configuredName: String?, symbolName: String?, tintName: String?) {
        let builtIn = Self.builtIn[identifier]
        self.identifier = identifier
        self.name = builtIn.map { tr($0.chinese, $0.english) }
            ?? configuredName.flatMap { $0.isEmpty ? nil : $0 }
            ?? tr("專注模式", "Focus")
        self.symbolName = symbolName.flatMap { $0.isEmpty ? nil : $0 } ?? builtIn?.symbol ?? "moon.fill"
        self.tintName = tintName
    }

    private static let builtIn: [String: (chinese: String, english: String, symbol: String)] = [
        "com.apple.donotdisturb.mode.default": ("勿擾模式", "Do Not Disturb", "moon.fill"),
        "com.apple.sleep.sleep-mode": ("睡眠", "Sleep", "bed.double.fill"),
        "com.apple.focus.work": ("工作", "Work", "person.lanyardcard.fill"),
        "com.apple.focus.personal-time": ("個人", "Personal", "person.fill"),
        "com.apple.donotdisturb.mode.driving": ("駕駛", "Driving", "car.fill"),
        "com.apple.focus.reading": ("閱讀", "Reading", "book.fill"),
        "com.apple.focus.gaming": ("遊戲", "Gaming", "gamecontroller.fill"),
        "com.apple.focus.fitness": ("健身", "Fitness", "figure.run"),
        "com.apple.focus.mindfulness": ("正念", "Mindfulness", "wind"),
        "com.apple.focus.reduce-interruptions": ("減少干擾", "Reduce Interruptions", "sparkles"),
    ]
}

/// 偵測專注模式開關。macOS 沒有公開 API，這裡讀系統的專注模式資料庫
/// （~/Library/DoNotDisturb/DB），所以需要「完整磁碟取用權限」。
/// 目前只認得手動開啟（含控制中心、捷徑）的專注模式；依時間表自動開啟的不會出現在資料庫裡。
@Observable
final class FocusMonitor {
    private(set) var current: FocusMode?
    /// 讀不到資料庫（沒有完整磁碟取用權限）。
    private(set) var needsFullDiskAccess = false

    @ObservationIgnored var onChange: (_ mode: FocusMode, _ active: Bool) -> Void = { _, _ in }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastModification: Date?
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let logger = Logger(subsystem: "com.howardyu.DynamicIsland", category: "Focus")

    private static let pollInterval: TimeInterval = 2

    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")) {
        self.folder = folder
    }

    func start() {
        guard timer == nil else { return }
        lastModification = nil
        // 啟動時已經開著的不提示
        current = readCurrent()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
    }

    private func poll() {
        // 檔案沒改就不重讀
        let modification = (try? assertionsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modification, modification == lastModification, !needsFullDiskAccess { return }
        let mode = readCurrent()
        guard mode != current else { return }
        let previous = current
        current = mode
        if let mode {
            logger.info("focus on: \(mode.identifier, privacy: .public)")
            onChange(mode, true)
        } else if let previous {
            logger.info("focus off")
            onChange(previous, false)
        }
    }

    private var assertionsURL: URL { folder.appendingPathComponent("Assertions.json") }
    private var configurationsURL: URL { folder.appendingPathComponent("ModeConfigurations.json") }

    private func readCurrent() -> FocusMode? {
        let data: Data
        do {
            lastModification = (try? assertionsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            data = try Data(contentsOf: assertionsURL)
            if needsFullDiskAccess { needsFullDiskAccess = false }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // 從來沒開過專注模式
            if needsFullDiskAccess { needsFullDiskAccess = false }
            return nil
        } catch {
            if !needsFullDiskAccess {
                needsFullDiskAccess = true
                logger.info("讀不到專注模式資料庫：\(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
        guard let identifier = Self.activeModeIdentifier(inAssertions: data) else { return nil }
        let configurations = try? Data(contentsOf: configurationsURL)
        return Self.mode(identifier: identifier, configurations: configurations)
    }

    // MARK: - 解析（格式沒有文件，所以用遞迴找鍵，不依賴完整結構）

    /// 最近開始的那個專注模式。
    static func activeModeIdentifier(inAssertions data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var best: (identifier: String, start: Double)?
        visit(root) { dictionary in
            guard let details = dictionary["assertionDetails"] as? [String: Any],
                  let identifier = details["assertionDetailsModeIdentifier"] as? String
            else { return }
            let start = dictionary["assertionStartDateTimestamp"] as? Double ?? 0
            if best == nil || start >= best!.start {
                best = (identifier, start)
            }
        }
        return best?.identifier
    }

    static func mode(identifier: String, configurations data: Data?) -> FocusMode {
        var name: String?
        var symbol: String?
        var tint: String?
        if let data, let root = try? JSONSerialization.jsonObject(with: data) {
            visit(root) { dictionary in
                guard name == nil, dictionary["modeIdentifier"] as? String == identifier else { return }
                name = dictionary["name"] as? String
                symbol = dictionary["symbolImageName"] as? String
                tint = dictionary["tintColorName"] as? String
            }
        }
        return FocusMode(identifier: identifier, configuredName: name, symbolName: symbol, tintName: tint)
    }

    private static func visit(_ node: Any, _ body: ([String: Any]) -> Void) {
        if let dictionary = node as? [String: Any] {
            body(dictionary)
            dictionary.values.forEach { visit($0, body) }
        } else if let array = node as? [Any] {
            array.forEach { visit($0, body) }
        }
    }
}
