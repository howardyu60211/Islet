import AppKit
import SwiftUI
import os

/// 建立並擺放瀏海面板，並把游標事件轉給 IslandViewModel。
final class NotchWindowController {
    /// 固定的面板大小：要裝得下最大的展開狀態加上陰影與彈簧動畫的超出量。
    static let panelSize = CGSize(width: 720, height: 260)

    private let island: IslandViewModel
    private let preferences: Preferences
    private let mouseTracker = MouseTracker()
    private var panel: NotchPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var keyMonitor: Any?
    private let logger = Logger(subsystem: "com.howardyu.Islet", category: "Window")

    init(island: IslandViewModel, preferences: Preferences) {
        self.island = island
        self.preferences = preferences
    }

    func start() {
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification)
        mouseTracker.handler = { [weak self] kind, location in
            self?.handlePointer(kind, at: location)
        }
        mouseTracker.scrollHandler = { [weak self] sample, location in
            self?.island.handleScroll(sample, at: location)
        }
        mouseTracker.start()
        // 面板變成 key window 時才收得到；只在剪貼簿分頁展開時才會這樣（見 updateKeyboardFocus）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let key = IslandKey(keyCode: event.keyCode),
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  self.island.handleKey(key)
            else { return event }
            return nil
        }
        observeKeyboardFocus()
        updatePlacement()
    }

    func stop() {
        mouseTracker.stop()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    /// 找內建螢幕、重新計算瀏海位置並擺好面板；沒有內建螢幕或使用者隱藏時就收起面板。
    func updatePlacement() {
        guard !preferences.islandHidden, let screen = NSScreen.builtIn else {
            panel?.orderOut(nil)
            island.geometry = nil
            return
        }
        let geometry = NotchGeometry(screen: screen)
        island.geometry = geometry

        let size = Self.panelSize
        let frame = CGRect(
            x: (geometry.centerX - size.width / 2).rounded(),
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let panel = self.panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        logger.info("notch \(geometry.notchSize.width, privacy: .public)x\(geometry.notchSize.height, privacy: .public) physical=\(geometry.hasPhysicalNotch, privacy: .public) panel=\(NSStringFromRect(frame), privacy: .public)")
    }

    private func makePanel(frame: CGRect) -> NotchPanel {
        let panel = NotchPanel(contentRect: frame)
        let hostingView = IslandHostingView(rootView: IslandRootView(island: island))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func handlePointer(_ kind: MouseTracker.Kind, at location: CGPoint) {
        guard let panel, panel.isVisible else { return }
        // 只有游標在島上時面板才接收滑鼠事件，其他透明區域的點擊都穿透到底下的選單列或視窗。
        let accepts = island.acceptsMouse(at: location)
        if panel.ignoresMouseEvents == accepts {
            panel.ignoresMouseEvents = !accepts
        }
        island.handlePointer(kind, at: location)
    }

    // MARK: - 鍵盤

    /// island.wantsKeyboard 一變就重新決定面板要不要接收鍵盤。
    private func observeKeyboardFocus() {
        withObservationTracking {
            _ = island.wantsKeyboard
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateKeyboardFocus()
                self?.observeKeyboardFocus()
            }
        }
    }

    /// 面板是 nonactivating：變成 key window 也不會把 Islet 帶到前景，原本的 App 還是作用中。
    private func updateKeyboardFocus() {
        guard let panel, panel.isVisible else { return }
        if island.wantsKeyboard {
            if !panel.isKeyWindow { panel.makeKey() }
        } else if panel.isKeyWindow {
            // 把鍵盤還給原本的 App：先收起再馬上放回來（同一輪 run loop，畫面不會閃）
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlacement() }
        }
        observers.append((center, token))
    }
}
