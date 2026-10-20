import AppKit

/// 選單列圖示與選單。
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let services: AppServices

    init(services: AppServices) {
        self.services = services
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Islet")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = !services.preferences.menuBarIconHidden
    }

    /// 設定裡的「隱藏選單列圖示」。
    func setIconVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    // 每次打開選單時重建，標題（例如「隱藏／顯示」）才會是最新的。
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(tr("設定…", "Settings…"), key: ",") { [weak self] in
            self?.services.showSettings()
        })
        let hidden = services.preferences.islandHidden
        menu.addItem(item(hidden ? tr("顯示小島", "Show Island") : tr("隱藏小島", "Hide Island")) { [weak self] in
            self?.services.toggleIslandHidden()
        })
        // 選單是從圖示打開的，所以只會有「隱藏」；要再顯示得到設定裡打開
        menu.addItem(item(tr("隱藏選單列圖示", "Hide Menu Bar Icon")) { [weak self] in
            self?.services.preferences.menuBarIconHidden = true
        })
        if services.updater.isAvailable {
            menu.addItem(item(tr("檢查更新…", "Check for Updates…")) { [weak self] in
                self?.services.updater.checkForUpdates()
            })
        }
        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(makeDebugMenuItem())
        #endif
        menu.addItem(.separator())
        menu.addItem(item(tr("結束 Islet", "Quit Islet"), key: "q") {
            NSApp.terminate(nil)
        })
    }

    #if DEBUG
    private func makeDebugMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: tr("模擬事件", "Simulate Event"), action: nil, keyEquivalent: "")
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
