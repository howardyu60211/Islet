import SwiftUI

/// 在這版 SDK 裡 `@State` 是一個 macro，它的實作（SwiftUIMacros plugin）只跟著 Xcode 發佈，
/// Command Line Tools 沒有，所以直接用 `State` 這個 property wrapper 型別本身。
/// 用法跟 `@State` 一樣：`@ViewState private var isHovering = false`。
typealias ViewState<Value> = SwiftUI.State<Value>
