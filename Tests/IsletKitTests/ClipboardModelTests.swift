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

    @Test func keepsAtMostMaxItems() {
        let model = ClipboardModel(pasteboard: pasteboard)
        for index in 0..<(ClipboardModel.maxItems + 5) {
            copy("item \(index)")
            model.checkForChanges()
        }
        #expect(model.items.count == ClipboardModel.maxItems)
        #expect(model.items.first?.signature == "text:item \(ClipboardModel.maxItems + 4)")
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
}
