import AppKit
import Observation

/// 背景程式：把選單列圖示關掉的 App（DockDoor、LinearMouse…）收在展開後頂部條的右側，
/// 看得到有沒有在執行，點一下重新打開它（這類 App 大多會顯示設定視窗）。
/// 只記 bundle ID，App 搬家或更新後還找得到。
@Observable
final class BackgroundAppsModel {
    struct App: Identifiable, Equatable {
        let bundleIdentifier: String
        let url: URL
        let name: String
        var id: String { bundleIdentifier }

        init(bundleIdentifier: String, url: URL) {
            self.bundleIdentifier = bundleIdentifier
            self.url = url
            name = BackgroundAppsModel.displayName(of: url)
        }
    }

    static func displayName(of url: URL) -> String {
        let bundle = Bundle(url: url)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    static let defaultsKey = "backgroundApps"

    private(set) var apps: [App] = []
    private(set) var runningIdentifiers: Set<String> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let resolveURL: (String) -> URL?
    @ObservationIgnored private let runningBundleIdentifiers: () -> Set<String>
    @ObservationIgnored private var runningObservation: NSKeyValueObservation?
    @ObservationIgnored private var icons: [URL: NSImage] = [:]

    init(
        defaults: UserDefaults = .standard,
        resolveURL: @escaping (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        runningBundleIdentifiers: @escaping () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
    ) {
        self.defaults = defaults
        self.resolveURL = resolveURL
        self.runningBundleIdentifiers = runningBundleIdentifiers
        // 找不到的 App（被刪掉、暫時沒掛上的磁碟）先不顯示，但留在設定裡
        apps = (defaults.stringArray(forKey: Self.defaultsKey) ?? []).compactMap { id in
            resolveURL(id).map { App(bundleIdentifier: id, url: $0) }
        }
        refreshRunning()
    }

    /// 開始跟著 App 啟動／結束更新執行狀態。
    /// NSWorkspace 的啟動／結束通知不會送給沒有 Dock 圖示的 App（選單列 App 幾乎都是），所以用 KVO 觀察 runningApplications。
    func start() {
        guard runningObservation == nil else { return }
        runningObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refreshRunning() }
        }
        refreshRunning()
    }

    func stop() {
        runningObservation?.invalidate()
        runningObservation = nil
    }

    func isRunning(_ app: App) -> Bool {
        runningIdentifiers.contains(app.bundleIdentifier)
    }

    func refreshRunning() {
        let running = runningBundleIdentifiers()
        if running != runningIdentifiers { runningIdentifiers = running }
    }

    // MARK: - 編輯

    /// 加入一個 .app；不是 App、是動態島自己或已經在清單裡時回傳 false。
    @discardableResult
    func add(_ url: URL) -> Bool {
        guard let id = Bundle(url: url)?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              !apps.contains(where: { $0.bundleIdentifier == id })
        else { return false }
        apps.append(App(bundleIdentifier: id, url: url))
        save()
        return true
    }

    func remove(_ app: App) {
        apps.removeAll { $0 == app }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        // 保留暫時找不到的 App，放在最後面
        let shown = apps.map(\.bundleIdentifier)
        let hidden = (defaults.stringArray(forKey: Self.defaultsKey) ?? []).filter { id in
            !shown.contains(id) && resolveURL(id) == nil
        }
        defaults.set(shown + hidden, forKey: Self.defaultsKey)
    }

    // MARK: - 動作

    /// 打開 App；已經在執行的話系統會送「重新打開」給它，選單列圖示關掉的 App 大多會顯示設定視窗。
    func open(_ app: App) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
    }

    func quit(_ app: App) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).forEach { $0.terminate() }
    }

    func revealInFinder(_ app: App) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func icon(for app: App) -> NSImage {
        Self.icon(of: app.url, cache: &icons)
    }

    /// App 圖示畫成 64×64 的 sRGB 點陣圖再用（並快取）。直接用 NSWorkspace 的圖示，
    /// 快照（ImageRenderer）整張會被改用別的色彩空間合成而變暗。
    static func icon(of url: URL, cache: inout [URL: NSImage]) -> NSImage {
        if let cached = cache[url] { return cached }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let pixels = 64
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.retagging(with: .sRGB) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(bitmap)
        cache[url] = image
        return image
    }

    /// 設定裡「加入」選單的候選：正在執行、沒有 Dock 圖示的第三方 App（選單列 App 大多是這種）。
    func runningMenuBarApps() -> [URL] {
        NSWorkspace.shared.runningApplications
            .filter { running in
                guard running.activationPolicy == .accessory,
                      let id = running.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !apps.contains(where: { $0.bundleIdentifier == id }),
                      let url = running.bundleURL, url.pathExtension == "app"
                else { return false }
                return !url.path.hasPrefix("/System/") && !url.path.hasPrefix("/Library/Apple/")
            }
            .compactMap(\.bundleURL)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
