import Foundation
import Testing
@testable import DynamicIslandKit

struct ShelfModelTests {
    private let defaults = UserDefaults(suiteName: "DynamicIslandShelfTests-\(UUID().uuidString)")!

    private func makeFiles(_ count: Int) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try (0..<count).map { index in
            let url = folder.appendingPathComponent("file\(index).txt")
            try Data("\(index)".utf8).write(to: url)
            return url
        }
    }

    @Test func addingTheSameFileTwiceKeepsOneCopyAtTheEnd() throws {
        let files = try makeFiles(2)
        let shelf = ShelfModel(defaults: defaults)
        shelf.add(files)
        shelf.add([files[0]])
        #expect(shelf.items.map(\.url) == [files[1], files[0]].map(\.standardizedFileURL))
    }

    @Test func ignoresNonFileURLs() {
        let shelf = ShelfModel(defaults: defaults)
        let added = shelf.add([URL(string: "https://example.com")!])
        #expect(added == 0)
        #expect(shelf.items.isEmpty)
    }

    @Test func keepsAtMostTheNewestItems() throws {
        let files = try makeFiles(ShelfModel.maxItems + 3)
        let shelf = ShelfModel(defaults: defaults)
        shelf.add(files)
        #expect(shelf.items.count == ShelfModel.maxItems)
        #expect(shelf.items.last?.url == files.last?.standardizedFileURL)
    }

    @Test func itemsSurviveARelaunchAndMissingFilesArePruned() throws {
        let files = try makeFiles(2)
        ShelfModel(defaults: defaults).add(files)
        try FileManager.default.removeItem(at: files[0])

        let relaunched = ShelfModel(defaults: defaults)
        #expect(relaunched.items.map(\.url) == [files[1].standardizedFileURL])
    }
}
