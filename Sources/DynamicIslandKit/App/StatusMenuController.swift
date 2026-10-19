import AppKit

/// 選單列圖示與選單。
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let services: AppServices

    init(services: AppServices) {
        self.services = services
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "動態島")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // 每次打開選單時重建，標題（例如「隱藏／顯示」）才會是最新的。
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("設定…", key: ",") { [weak self] in
            self?.services.showSettings()
        })
        let hidden = services.preferences.islandHidden
        menu.addItem(item(hidden ? "顯示動態島" : "隱藏動態島") { [weak self] in
            self?.services.toggleIslandHidden()
        })
        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(makeDebugMenuItem())
        #endif
        menu.addItem(.separator())
        menu.addItem(item("結束動態島", key: "q") {
            NSApp.terminate(nil)
        })
    }

    #if DEBUG
    private func makeDebugMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "模擬事件", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for simulation in services.debugSimulations() {
            submenu.addItem(item(simulation.title, action: simulation.run))
        }
        parent.submenu = submenu
        return parent
    }
    #endif

    /// 建一個點擊時執行 closure 的選單項目。
    private func item(_ title: String, key: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = MenuAction(run: action)
        return item
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
    }
}

private final class MenuAction {
    let run: () -> Void

    init(run: @escaping () -> Void) {
        self.run = run
    }
}
