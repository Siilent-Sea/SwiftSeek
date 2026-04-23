import AppKit

enum MainMenu {
    static func build(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "关于 SwiftSeek",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let searchItem = NSMenuItem(title: "搜索…",
                                    action: #selector(AppDelegate.toggleSearchWindow(_:)),
                                    keyEquivalent: " ")
        searchItem.keyEquivalentModifierMask = [.option]
        searchItem.target = target
        appMenu.addItem(searchItem)

        let settingsItem = NSMenuItem(title: "设置…",
                                      action: #selector(AppDelegate.showSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.target = target
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 SwiftSeek",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 SwiftSeek",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // Edit menu — required so ⌘X/C/V/A work in NSTextField (search box,
        // settings inputs). NSApplication wires these selectors up to the
        // first responder automatically when the menu items exist.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "撤销",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做",
                              action: Selector(("redo:")),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")

        return mainMenu
    }
}
