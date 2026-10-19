import Foundation
import Testing
@testable import IsletKit

struct FocusMonitorTests {
    // 這裡檢查的是中文字串，不管跑測試的電腦是什麼語言。
    init() { AppLanguage.current = .traditionalChinese }

    private let assertions = Data("""
    {"data":[{"storeAssertionRecords":[
      {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"},"assertionStartDateTimestamp":100},
      {"assertionDetails":{"assertionDetailsModeIdentifier":"custom-mode-id"},"assertionStartDateTimestamp":200}
    ]}],"header":{"timestamp":1}}
    """.utf8)

    private let configurations = Data("""
    {"data":[{"modeConfigurations":{
      "custom-mode-id":{"mode":{"modeIdentifier":"custom-mode-id","name":"寫程式","symbolImageName":"laptopcomputer","tintColorName":"systemTealColor"}}
    }}]}
    """.utf8)

    @Test func picksTheMostRecentlyStartedMode() {
        #expect(FocusMonitor.activeModeIdentifier(inAssertions: assertions) == "custom-mode-id")
    }

    @Test func noAssertionsMeansNoFocus() {
        #expect(FocusMonitor.activeModeIdentifier(inAssertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)) == nil)
    }

    @Test func customModesUseTheirConfiguredNameAndSymbol() {
        let mode = FocusMonitor.mode(identifier: "custom-mode-id", configurations: configurations)
        #expect(mode.name == "寫程式")
        #expect(mode.symbolName == "laptopcomputer")
        #expect(mode.tintName == "systemTealColor")
    }

    @Test func builtInModesUseChineseNames() {
        let mode = FocusMonitor.mode(identifier: "com.apple.donotdisturb.mode.default", configurations: nil)
        #expect(mode.name == "勿擾模式")
        #expect(mode.symbolName == "moon.fill")
    }

    @Test func readsTheDatabaseFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try assertions.write(to: folder.appendingPathComponent("Assertions.json"))
        try configurations.write(to: folder.appendingPathComponent("ModeConfigurations.json"))
        let monitor = FocusMonitor(folder: folder)
        monitor.start()
        defer { monitor.stop() }
        #expect(monitor.current?.name == "寫程式")
        #expect(!monitor.needsFullDiskAccess)
    }
}
