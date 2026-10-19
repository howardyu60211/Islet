import Foundation

/// 介面語言。預設跟著系統的偏好語言（含「系統設定 › 一般 › 語言與地區」替個別 App 指定的語言）：
/// 清單裡先遇到中文就用繁體中文，先遇到英文或都沒有就用英文。也可以在設定裡指定，重新啟動後生效。
nonisolated enum AppLanguage: String, CaseIterable, Sendable {
    case traditionalChinese = "zh-Hant"
    case english = "en"

    /// 這次啟動使用的語言。只在啟動時決定（測試裡會直接指定）。
    nonisolated(unsafe) static var current = resolve(Locale.preferredLanguages)

    static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        for language in preferredLanguages {
            if language.hasPrefix("zh") { return .traditionalChinese }
            if language.hasPrefix("en") { return .english }
        }
        return .english
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// 這個語言自己的名稱（語言選單裡不翻譯）。
    var nativeName: String {
        switch self {
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }

    /// 不指定時會用的語言（系統的偏好語言）。
    static var system: AppLanguage {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return resolve(global ?? Locale.preferredLanguages)
    }

    /// 設定裡指定的語言，nil 是跟隨系統。存成 App 自己的 AppleLanguages，
    /// 這樣系統選單、權限對話框裡的 App 名稱（InfoPlist.strings）也會一起換。
    static var override: AppLanguage? {
        get {
            guard let bundleID = Bundle.main.bundleIdentifier,
                  let languages = UserDefaults.standard.persistentDomain(forName: bundleID)?["AppleLanguages"] as? [String],
                  let first = languages.first
            else { return nil }
            return resolve([first])
        }
        set {
            if let newValue {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }
    }
}

/// 依介面語言回傳中文或英文：`tr("充電中", "Charging")`。兩種語言寫在一起，句子裡的變數各自照文法擺。
nonisolated func tr(_ chinese: String, _ english: String) -> String {
    AppLanguage.current == .traditionalChinese ? chinese : english
}
