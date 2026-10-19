import Testing
@testable import IsletKit

struct LocalizationTests {
    @Test func picksTheFirstSupportedLanguageInThePreferredList() {
        #expect(AppLanguage.resolve(["zh-Hant-TW", "en-US"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(["en-US", "zh-Hant-TW"]) == .english)
        #expect(AppLanguage.resolve(["ja-JP", "zh-Hant-TW", "en-US"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(["zh-HK"]) == .traditionalChinese)
    }

    @Test func fallsBackToEnglish() {
        #expect(AppLanguage.resolve(["ja-JP", "fr-FR"]) == .english)
        #expect(AppLanguage.resolve([]) == .english)
    }
}
