import AppKit
import Observation
import Sparkle

/// 用 Sparkle 自動更新。更新清單（appcast.xml）放在 GitHub Releases，網址與公鑰寫在 Info.plist。
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    /// 沒有組成 .app（swift run、快照模式）時沒有 Info.plist，就不啟用。
    /// Debug 建置也不啟用，不然會檢查到正式版、提示把開發中的 App 換掉。
    var isAvailable: Bool { controller != nil }

    #if DEBUG
    static let isEnabledByDefault = false
    #else
    static let isEnabledByDefault = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    #endif

    /// 設定裡的「自動檢查更新」。Sparkle 自己存在 UserDefaults，這裡只是讓 SwiftUI 看得到變更。
    var automaticallyChecksForUpdates: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init(enabled: Bool = Updater.isEnabledByDefault) {
        controller = enabled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    /// 選單與設定裡的「檢查更新…」；已經在檢查或下載時，Sparkle 會把那個視窗帶到前面。
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
