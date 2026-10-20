import AppKit
import Testing
@testable import IsletKit

struct ClipboardModelTests {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("IsletClipboardTests-\(UUID().uuidString)"))

    private func copy(_ string: String, extraType: String? = nil) {
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.string]
        if let extraType { types.append(NSPasteboard.PasteboardType(extraType)) }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(string, forType: .string)
        if let extraType { pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(extraType)) }
    }

    @Test func recordsNewestFirstAndSkipsUnchangedPasteboard() {
        let model = ClipboardModel(pasteboard: pasteboard)
        copy("first")
        model.checkForChanges()
        model.checkForChanges()
        copy("second")
        model.checkForChanges()
        #expect(model.items.map(\.signature) == ["text:second", "text:first"])
    }

    @Test func copyingTheSameTextAgainMovesItToTheFront() {
        let model = ClipboardModel(pasteboard: pasteboard)
        for text in ["a", "b", "a"] {
            copy(text)
            model.checkForChanges()
        }
        #expect(model.items.map(\.signature) == ["text:a", "text:b"])
    }

    @Test func ignoresConcealedContentFromPasswordManagers() {
        let model = ClipboardModel(pasteboard: pasteboard)
        copy("hunter2", extraType: "org.nspasteboard.ConcealedType")
        model.checkForChanges()
        #expect(model.items.isEmpty)
    }

    @Test func detectsLinks() {
        let model = ClipboardModel(pasteboard: pasteboard)
        copy("  https://example.com/page  ")
        model.checkForChanges()
        guard case .link(let url) = model.items.first?.preview else {
            Issue.record("不是連結")
            return
        }
        #expect(url.host == "example.com")
    }

    @Test func copyingBackRestoresContentWithoutRecordingItTwice() {
        let model = ClipboardModel(pasteboard: pasteboard)
        copy("old")
        model.checkForChanges()
        copy("new")
        model.checkForChanges()
        let old = model.items[1]
        model.copy(old)
        model.checkForChanges()
        #expect(pasteboard.string(forType: .string) == "old")
        #expect(model.items.count == 2)
        #expect(model.items.first?.id == old.id)
        #expect(model.recentlyCopiedID == old.id)
    }

    @Test func keepsAtMostTheHistoryLimit() {
        let model = ClipboardModel(pasteboard: pasteboard)
        model.historyLimit = 30
        for index in 0..<35 {
            copy("item \(index)")
            model.checkForChanges()
        }
        #expect(model.items.count == 30)
        #expect(model.items.first?.signature == "text:item 34")

        model.historyLimit = 10
        #expect(model.items.count == 10)
        #expect(model.items.last?.signature == "text:item 25")
    }

    // MARK: - 釘選

    private func record(_ texts: [String], in model: ClipboardModel) {
        for text in texts {
            copy(text)
            model.checkForChanges()
        }
    }

    @Test func pinnedItemsStayOnTopAndOutsideTheLimit() {
        let model = ClipboardModel(pasteboard: pasteboard)
        model.historyLimit = 3
        record(["keep", "a", "b"], in: model)
        model.togglePin(model.items[2])
        #expect(model.pinnedCount == 1)
        #expect(model.items.map(\.signature) == ["text:keep", "text:b", "text:a"])

        record(["c", "d", "e"], in: model)
        #expect(model.items.map(\.signature) == ["text:keep", "text:e", "text:d", "text:c"])

        // 從紀錄拷貝回去：一般的移到最新那筆的位置，釘選的不動
        model.copy(model.items[3])
        #expect(model.items.map(\.signature) == ["text:keep", "text:c", "text:e", "text:d"])
        model.copy(model.items[0])
        #expect(model.items.first?.signature == "text:keep")
    }

    @Test func copyingPinnedContentAgainDoesNotDuplicateIt() {
        let model = ClipboardModel(pasteboard: pasteboard)
        record(["keep", "other"], in: model)
        model.togglePin(model.items[1])
        record(["keep"], in: model)
        #expect(model.items.map(\.signature) == ["text:keep", "text:other"])
        #expect(model.items[0].isPinned)
    }

    @Test func unpinningMovesBackToTheNewestHistory() {
        let model = ClipboardModel(pasteboard: pasteboard)
        record(["one", "two", "three"], in: model)
        model.togglePin(model.items[2])
        model.togglePin(model.items[2])
        #expect(model.items.map(\.signature) == ["text:one", "text:two", "text:three"])
        #expect(model.items.map(\.isPinned) == [true, true, false])
        model.togglePin(model.items[0])
        #expect(model.items.map(\.signature) == ["text:two", "text:one", "text:three"])
        #expect(model.pinnedCount == 1)
    }

    @Test func clearingKeepsPinnedUnlessAskedToClearEverything() {
        let model = ClipboardModel(pasteboard: pasteboard)
        record(["keep", "a", "b"], in: model)
        model.togglePin(model.items[2])
        model.removeAll()
        #expect(model.items.map(\.signature) == ["text:keep"])
        model.removeAll(includingPinned: true)
        #expect(model.items.isEmpty)
    }

    @Test func notifiesNewCopiesButNotWhatWasAlreadyThereAtStart() {
        copy("already there")
        let model = ClipboardModel(pasteboard: pasteboard)
        var captured: [String] = []
        model.onCapture = { captured.append($0.signature) }
        model.start()
        defer { model.stop() }
        copy("new")
        model.checkForChanges()
        #expect(captured == ["text:new"])
        #expect(model.items.count == 2)
    }

    @Test func dropsOldestItemsWhenOverTheMemoryBudget() {
        let model = ClipboardModel(pasteboard: pasteboard)
        let chunk = ClipboardModel.maxTotalBytes / 4
        for index in 0..<5 {
            pasteboard.clearContents()
            pasteboard.setString("big \(index)", forType: .string)
            pasteboard.setData(Data(count: chunk), forType: NSPasteboard.PasteboardType("com.example.big"))
            model.checkForChanges()
        }
        #expect(model.items.reduce(0) { $0 + $1.byteCount } <= ClipboardModel.maxTotalBytes)
        #expect(model.items.first?.signature == "text:big 4")
        #expect(model.items.count < 5)
    }

    @Test func largePinnedItemsDoNotPushOutTheHistory() {
        let model = ClipboardModel(pasteboard: pasteboard)
        // 兩筆加起來超過上限，但每筆都沒超過單筆上限
        let chunk = ClipboardModel.maxTotalBytes / 2 + 1
        for index in 0..<2 {
            pasteboard.clearContents()
            pasteboard.setString("big \(index)", forType: .string)
            pasteboard.setData(Data(count: chunk), forType: NSPasteboard.PasteboardType("com.example.big"))
            model.checkForChanges()
            model.togglePin(model.items[model.pinnedCount])
        }
        #expect(model.pinnedCount == 2)

        record(["a", "b", "c"], in: model)
        #expect(model.items.map(\.signature) == ["text:big 0", "text:big 1", "text:c", "text:b", "text:a"])
    }

    // MARK: - 存到磁碟

    private func makeStore() -> ClipboardStore {
        ClipboardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("IsletClipboardStoreTests-\(UUID().uuidString)"))
    }

    @Test func historySurvivesRelaunchInTheSameOrder() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        for text in ["one", "https://example.com", "three"] {
            copy(text)
            model.checkForChanges()
        }
        model.copy(model.items[2])
        store.flush()

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store)
        #expect(relaunched.items.map(\.id) == model.items.map(\.id))
        #expect(relaunched.items.map(\.signature) == ["text:one", "text:three", "text:https://example.com"])
        guard case .link(let url) = relaunched.items.last?.preview else {
            Issue.record("不是連結")
            return
        }
        #expect(url.host == "example.com")
    }

    @Test func stoppingSavesTheLatestCopyBeforeQuitting() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        copy("just copied")
        model.checkForChanges()
        model.stop()
        #expect(ClipboardStore(directory: store.directory).load().history.map(\.signature) == ["text:just copied"])
    }

    @Test func relaunchTrimsSavedHistoryToTheLimit() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        record(["one", "two", "three", "four"], in: model)
        store.flush()

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store, historyLimit: 2)
        #expect(relaunched.items.map(\.signature) == ["text:four", "text:three"])
        store.flush()
        // 多的也從磁碟上刪掉了
        #expect(ClipboardModel(pasteboard: pasteboard, store: store).items.map(\.signature) == ["text:four", "text:three"])
    }

    @Test func filesMissingFromTheOrderAreKeptAndTrimmed() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        record(["one", "two", "three"], in: model)
        store.flush()
        // 索引沒寫到（例如寫到一半當掉）：照時間排，超過上限的剪掉
        try FileManager.default.removeItem(at: store.indexURL)

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store, historyLimit: 2)
        #expect(relaunched.items.map(\.signature) == ["text:three", "text:two"])
    }

    @Test func removedItemsStayRemovedAfterRelaunch() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        for text in ["keep", "drop"] {
            copy(text)
            model.checkForChanges()
        }
        model.remove(model.items[0])
        store.flush()
        #expect(ClipboardModel(pasteboard: pasteboard, store: store).items.map(\.signature) == ["text:keep"])

        model.removeAll(includingPinned: true)
        store.flush()
        #expect(ClipboardModel(pasteboard: pasteboard, store: store).items.isEmpty)
    }

    @Test func imagesAndFilesSurviveRelaunch() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        model.checkForChanges()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/report.pdf") as NSURL])
        model.checkForChanges()
        store.flush()

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store)
        #expect(relaunched.items.count == 2)
        guard case .files(let urls) = relaunched.items[0].preview else {
            Issue.record("不是檔案")
            return
        }
        #expect(urls.map(\.path) == ["/tmp/report.pdf"])
        guard case .image(let thumbnail) = relaunched.items[1].preview else {
            Issue.record("不是圖片")
            return
        }
        #expect(thumbnail.size == NSSize(width: 40, height: 20))
        #expect(relaunched.items[1].signature == model.items[1].signature)
    }

    @Test func clipboardAtLaunchKeepsTheSavedSourceAndDate() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        copy("still on the clipboard")
        model.checkForChanges()
        store.flush()

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store)
        relaunched.start()
        defer { relaunched.stop() }
        #expect(relaunched.items.count == 1)
        #expect(relaunched.items.first?.date == model.items.first?.date)
    }

    @Test func relaunchedItemsLoadContentOnlyWhenCopied() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        record(["saved", "newer"], in: model)
        store.flush()

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store)
        #expect(relaunched.items.allSatisfy { $0.representations == nil })
        #expect(relaunched.items.map(\.byteCount) == model.items.map(\.byteCount))
        relaunched.copy(relaunched.items[1])
        #expect(pasteboard.string(forType: .string) == "saved")
        #expect(relaunched.items.first?.signature == "text:saved")
    }

    @Test func pinningOnlyRewritesTheIndex() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        record(["keep"], in: model)
        store.flush()
        let files = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != store.indexURL.lastPathComponent }
        #expect(Set(files.map(\.pathExtension)) == ["item", "data"])
        let modified = { try files.map { try FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date } }
        let before = try modified()

        model.togglePin(model.items[0])
        store.flush()
        #expect(try modified() == before)
        #expect(ClipboardModel(pasteboard: pasteboard, store: store).pinnedCount == 1)
    }

    @Test func missingPinnedFileDoesNotPinAnotherItem() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        record(["keep", "a"], in: model)
        model.togglePin(model.items[1])
        store.flush()
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent(model.items[0].id.uuidString).appendingPathExtension("item"))

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store)
        #expect(relaunched.items.map(\.signature) == ["text:a"])
        #expect(relaunched.pinnedCount == 0)
    }

    @Test func pinsSurviveRelaunch() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = ClipboardModel(pasteboard: pasteboard, store: store)
        record(["keep", "a"], in: model)
        model.togglePin(model.items[1])
        store.flush()

        let relaunched = ClipboardModel(pasteboard: pasteboard, store: store)
        #expect(relaunched.items.map(\.signature) == ["text:keep", "text:a"])
        #expect(relaunched.pinnedCount == 1)
    }
}
