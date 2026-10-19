import Foundation
import Testing
@testable import IsletKit

struct BackgroundAppsModelTests {
    private let defaults = UserDefaults(suiteName: "IsletBackgroundAppsTests-\(UUID().uuidString)")!
    private let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    private let chess = URL(fileURLWithPath: "/System/Applications/Chess.app")

    /// 用固定的對照表代替 LaunchServices，測試不受這台電腦裝了什麼影響。
    private func makeModel(installed: [String: URL]? = nil, running: Set<String> = []) -> BackgroundAppsModel {
        let installed = installed ?? ["com.apple.calculator": calculator, "com.apple.Chess": chess]
        return BackgroundAppsModel(defaults: defaults, resolveURL: { installed[$0] }, runningBundleIdentifiers: { running })
    }

    @Test func addsAnAppOnceAndRemembersItAcrossLaunches() {
        let model = makeModel()
        #expect(model.add(calculator))
        #expect(!model.add(calculator))
        #expect(model.add(chess))
        #expect(model.apps.map(\.bundleIdentifier) == ["com.apple.calculator", "com.apple.Chess"])

        let reopened = makeModel()
        #expect(reopened.apps.map(\.bundleIdentifier) == ["com.apple.calculator", "com.apple.Chess"])
        // 名稱會依系統語言在地化（例如「計算機」），只確認有讀到
        #expect(reopened.apps.first?.name.isEmpty == false)
    }

    @Test func rejectsThingsThatAreNotApps() {
        let model = makeModel()
        #expect(!model.add(URL(fileURLWithPath: NSTemporaryDirectory())))
        #expect(model.apps.isEmpty)
    }

    @Test func showsWhichAppsAreRunning() {
        let model = makeModel(running: ["com.apple.Chess"])
        model.add(calculator)
        model.add(chess)
        #expect(!model.isRunning(model.apps[0]))
        #expect(model.isRunning(model.apps[1]))
    }

    @Test func keepsAppsThatAreTemporarilyMissing() {
        let model = makeModel()
        model.add(calculator)
        model.add(chess)

        // Chess 暫時找不到：不顯示，但移除別的 App 時不會把它從設定裡弄丟
        let withoutChess = makeModel(installed: ["com.apple.calculator": calculator])
        #expect(withoutChess.apps.map(\.bundleIdentifier) == ["com.apple.calculator"])
        withoutChess.remove(withoutChess.apps[0])

        let restored = makeModel()
        #expect(restored.apps.map(\.bundleIdentifier) == ["com.apple.Chess"])
    }

    @Test func stopsAtTheLimit() throws {
        let apps = try FileManager.default.contentsOfDirectory(atPath: "/System/Applications")
            .filter { $0.hasSuffix(".app") }
            .map { URL(fileURLWithPath: "/System/Applications/\($0)") }
        try #require(apps.count > BackgroundAppsModel.maxApps)
        let model = BackgroundAppsModel(defaults: defaults, runningBundleIdentifiers: { [] })
        let added = apps.filter { model.add($0) }
        #expect(added.count == BackgroundAppsModel.maxApps)
        #expect(model.isFull)

        model.remove(model.apps[0])
        #expect(!model.isFull)
    }

    @Test func reordersApps() {
        let model = makeModel()
        model.add(calculator)
        model.add(chess)
        model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(makeModel().apps.map(\.bundleIdentifier) == ["com.apple.Chess", "com.apple.calculator"])
    }
}
