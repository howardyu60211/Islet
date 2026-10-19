import AppKit
import Observation
import QuickLookThumbnailing

/// 檔案暫存架：記住拖進來的檔案路徑（不複製檔案），重開 App 後還在。
@Observable
final class ShelfModel {
    struct Item: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    static let defaultsKey = "shelfItems"
    static let maxItems = 30

    private(set) var items: [Item] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths.map { Item(url: URL(fileURLWithPath: $0)) }
        pruneMissing()
        items.forEach(loadThumbnail)
    }

    /// 加入檔案（重複的移到最後面），回傳實際加入的數量。
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let fileURLs = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !fileURLs.isEmpty else { return 0 }
        items.removeAll { item in fileURLs.contains(item.url) }
        items.append(contentsOf: fileURLs.map { Item(url: $0) })
        if items.count > Self.maxItems {
            items.removeFirst(items.count - Self.maxItems)
        }
        save()
        fileURLs.map { Item(url: $0) }.forEach(loadThumbnail)
        return fileURLs.count
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        thumbnails[item.url] = nil
        save()
    }

    func removeAll() {
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    /// 檔案被移走或刪掉的項目就拿掉。
    func pruneMissing() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard existing != items else { return }
        items = existing
        save()
    }

    // MARK: - 動作

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// 用 AirDrop 傳送；回傳是否有可用的 AirDrop 服務。
    @discardableResult
    func airDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            return false
        }
        // App 沒有在前景時，AirDrop 視窗可能跑到後面
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }

    // MARK: - 內部

    private func save() {
        defaults.set(items.map(\.url.path), forKey: Self.defaultsKey)
    }

    private func loadThumbnail(for item: Item) {
        guard thumbnails[item.url] == nil else { return }
        let url = item.url
        // 先放 Finder 圖示，QuickLook 縮圖好了再換掉
        thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path).bitmapCopy(pointSize: 48)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.items.contains(where: { $0.url == url }) else { return }
                    self.thumbnails[url] = NSImage(cgImage: cgImage, size: .zero)
                }
            }
        }
    }
}
