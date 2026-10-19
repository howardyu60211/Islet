import AppKit
import SwiftUI

/// 自己管理的設定視窗（App 沒有 Dock 圖示，打開時要主動把自己帶到前面）。
final class SettingsWindowController {
    private let preferences: Preferences
    private let nowPlaying: NowPlayingModel
    private let focus: FocusMonitor
    private let shelf: ShelfModel
    private let clipboard: ClipboardModel
    private var window: NSWindow?
    private var hairlineFix: HairlineBorderFix?

    init(preferences: Preferences, nowPlaying: NowPlayingModel, focus: FocusMonitor, shelf: ShelfModel, clipboard: ClipboardModel) {
        self.preferences = preferences
        self.nowPlaying = nowPlaying
        self.focus = focus
        self.shelf = shelf
        self.clipboard = clipboard
    }

    func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(preferences: preferences, nowPlaying: nowPlaying, focus: focus, shelf: shelf, clipboard: clipboard))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = tr("動態島設定", "DynamicIsland Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        hairlineFix = HairlineBorderFix(window: window)
        return window
    }
}
