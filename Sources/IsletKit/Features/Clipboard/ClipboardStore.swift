import AppKit

/// 把剪貼簿紀錄存在磁碟上，結束 App、更新或重新開機後都還在。
/// 每筆分成兩個檔案：.item 是顯示用的小檔（預覽、來源、時間），.data 是原始內容（可能很大）。
/// 啟動時只讀 .item，原始內容等到要再拷貝時才讀，啟動快、也不佔記憶體。
/// 順序和釘選記在一個小的索引檔，釘選或移動時只要改它。寫入和刪除在背景依序進行，不卡主執行緒。
nonisolated final class ClipboardStore: Sendable {
    /// 存到磁碟的一筆紀錄（不含原始內容）。
    struct Record: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case text, link, image, files
        }

        let id: UUID
        let kind: Kind
        /// 文字或連結。
        var text: String?
        /// 檔案路徑。
        var paths: [String]?
        /// 圖片縮圖（PNG）與它的大小（點）。
        var thumbnail: Data?
        var thumbnailWidth: Double?
        var thumbnailHeight: Double?
        let sourceApp: String?
        let sourceBundleIdentifier: String?
        let date: Date
        let signature: String
        /// 原始內容的大小，修剪紀錄時用（不用讀 .data）。
        let byteCount: Int
    }

    /// 讀出來的紀錄：釘選的（照釘選的先後）與一般紀錄（最新的在前面）。
    struct Snapshot {
        var pinned: [Record]
        var history: [Record]
    }

    /// 全部紀錄的順序，前 pinnedCount 筆是釘選的。
    private struct Index: Codable {
        var order: [UUID]
        var pinnedCount: Int
    }

    let directory: URL
    private let queue = DispatchQueue(label: "com.howardyu.Islet.clipboard-store", qos: .utility)

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Islet/Clipboard", isDirectory: true)
    }

    init(directory: URL = ClipboardStore.defaultDirectory) {
        self.directory = directory
    }

    var indexURL: URL { directory.appendingPathComponent("index.plist") }

    private func recordURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("item")
    }

    private func dataURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("data")
    }

    /// 讀出所有紀錄；讀不到或缺原始內容的檔案順便清掉。
    /// 沒有列在索引裡的紀錄一定是最後一次寫索引之後才新增的（同一個佇列依序寫），所以保留、照時間排在後面，超過上限的由 ClipboardModel 修剪。
    func load() -> Snapshot {
        let fileManager = FileManager.default
        let decoder = PropertyListDecoder()
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var records: [UUID: Record] = [:]
        for file in files where file.pathExtension == "item" {
            if let data = try? Data(contentsOf: file), let record = try? decoder.decode(Record.self, from: data),
               fileManager.fileExists(atPath: dataURL(for: record.id).path) {
                records[record.id] = record
            } else {
                try? fileManager.removeItem(at: file)
            }
        }
        let index = (try? Data(contentsOf: indexURL)).flatMap { try? decoder.decode(Index.self, from: $0) }
        let order = index?.order ?? []
        let pinnedCount = min(max(index?.pinnedCount ?? 0, 0), order.count)
        let pinned = order.prefix(pinnedCount).compactMap { records.removeValue(forKey: $0) }
        var history = order.dropFirst(pinnedCount).compactMap { records.removeValue(forKey: $0) }
        history += records.values.sorted { $0.date > $1.date }
        return Snapshot(pinned: pinned, history: history)
    }

    /// 原始內容；要再拷貝時才讀。
    func representations(for id: UUID) -> [[NSPasteboard.PasteboardType: Data]]? {
        guard let data = try? Data(contentsOf: dataURL(for: id)),
              let stored = try? PropertyListDecoder().decode([[String: Data]].self, from: data) else { return nil }
        return stored.map { representation in
            Dictionary(uniqueKeysWithValues: representation.map { (NSPasteboard.PasteboardType($0.key), $0.value) })
        }
    }

    /// 先寫原始內容再寫 .item，有 .item 就一定有 .data。
    func save(_ record: Record, representations: [[NSPasteboard.PasteboardType: Data]]) {
        let recordURL = recordURL(for: record.id)
        let dataURL = dataURL(for: record.id)
        // 格式名稱存成字串
        let representations = representations.map { representation in
            Dictionary(uniqueKeysWithValues: representation.map { ($0.key.rawValue, $0.value) })
        }
        write { encoder in
            try encoder.encode(representations).write(to: dataURL, options: .atomic)
            try encoder.encode(record).write(to: recordURL, options: .atomic)
        }
    }

    func saveIndex(order: [UUID], pinnedCount: Int) {
        let url = indexURL
        write { encoder in try encoder.encode(Index(order: order, pinnedCount: pinnedCount)).write(to: url, options: .atomic) }
    }

    func delete(_ id: UUID) {
        let urls = [recordURL(for: id), dataURL(for: id)]
        queue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    /// 等排隊中的寫入都做完（結束 App 前，以及測試用）。
    func flush() {
        queue.sync {}
    }

    private func write(_ body: @escaping @Sendable (PropertyListEncoder) throws -> Void) {
        let directory = directory
        queue.async {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try body(encoder)
            } catch {
                NSLog("Islet: failed to save clipboard history: \(error)")
            }
        }
    }
}

extension ClipboardModel.Item {
    /// 從磁碟讀回來的紀錄：原始內容留在磁碟上，要拷貝時才讀。
    init?(record: ClipboardStore.Record, isPinned: Bool) {
        switch record.kind {
        case .text:
            guard let text = record.text else { return nil }
            preview = .text(text)
        case .link:
            guard let text = record.text, let url = URL(string: text) else { return nil }
            preview = .link(url)
        case .image:
            guard let data = record.thumbnail, let image = NSImage(data: data) else { return nil }
            if let width = record.thumbnailWidth, let height = record.thumbnailHeight {
                image.size = NSSize(width: width, height: height)
            }
            preview = .image(image)
        case .files:
            guard let paths = record.paths, !paths.isEmpty else { return nil }
            preview = .files(paths.map { URL(fileURLWithPath: $0) })
        }
        id = record.id
        representations = nil
        byteCount = record.byteCount
        sourceApp = record.sourceApp
        sourceBundleIdentifier = record.sourceBundleIdentifier
        date = record.date
        signature = record.signature
        self.isPinned = isPinned
    }

    var record: ClipboardStore.Record? {
        let kind: ClipboardStore.Record.Kind
        var text: String?, paths: [String]?, thumbnail: Data?, thumbnailSize: NSSize?
        switch preview {
        case .text(let string):
            kind = .text
            text = string
        case .link(let url):
            kind = .link
            text = url.absoluteString
        case .image(let image):
            guard let png = image.pngData() else { return nil }
            kind = .image
            thumbnail = png
            thumbnailSize = image.size
        case .files(let urls):
            kind = .files
            paths = urls.map(\.path)
        }
        return ClipboardStore.Record(
            id: id,
            kind: kind,
            text: text,
            paths: paths,
            thumbnail: thumbnail,
            thumbnailWidth: thumbnailSize.map { $0.width },
            thumbnailHeight: thumbnailSize.map { $0.height },
            sourceApp: sourceApp,
            sourceBundleIdentifier: sourceBundleIdentifier,
            date: date,
            signature: signature,
            byteCount: byteCount
        )
    }
}
