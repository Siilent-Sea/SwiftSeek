import AppKit
import Foundation
import SwiftSeekCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: SettingsWindowController?
    private var searchWindowController: SearchWindowController?
    private var hotkey: GlobalHotkey?
    private var rebuildCoordinator: RebuildCoordinator?
    private var statusItem: NSStatusItem?
    private var statusIndexingItem: NSMenuItem?
    private(set) var database: Database?

    private let hotkeyAlertedKey = "SwiftSeek.hotkey_fail_alerted_v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // K1: log build identity FIRST so stale-bundle / wrong-binary
        // bug reports always include version, commit, and the actual
        // executable / bundle path. Users pasting the first ~5 lines
        // of Console output is enough to triage "is this the right
        // build?" without further questions.
        NSLog("SwiftSeek: \(BuildInfo.summary)")
        NSLog("SwiftSeek: bundle=\(BuildInfo.bundlePath)")
        NSLog("SwiftSeek: binary=\(BuildInfo.executablePath)")

        NSApp.mainMenu = MainMenu.build(target: self)
        NSApp.activate(ignoringOtherApps: true)

        do {
            let paths = try AppPaths.ensureSupportDirectory()
            let db = try Database.open(at: paths.databaseURL)
            try db.migrate()
            self.database = db
            NSLog("SwiftSeek: database ready at \(paths.databaseURL.path) schema=\(db.schemaVersion)")
        } catch {
            NSLog("SwiftSeek: database init failed: \(error)")
            presentFatal(error: error)
            return
        }

        if let db = database {
            let coord = RebuildCoordinator(database: db)
            coord.onStateChange = { [weak self] state in
                DispatchQueue.main.async { self?.reflectRebuildState(state) }
            }
            self.rebuildCoordinator = coord
        }
        installStatusItem()
        installSearchWindow()
        installGlobalHotkey()
        showSettings(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// J1: Dock reopen (click Dock icon with no visible windows).
    /// `hasVisibleWindows == true` → AppKit handles it; we return
    /// true so the default behaviour kicks in. `false` → we're in
    /// the state the J1 bug report describes: user closed settings,
    /// there are no visible windows, and the only way back used to
    /// be "Dock right-click Quit + relaunch". Show settings as the
    /// predictable primary entry (search window is opt-in via
    /// ⌥Space / menu and hides on resign-key, so settings is the
    /// better "something visible" default).
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showSettings(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        database?.close()
    }

    @objc func showSettings(_ sender: Any?) {
        // J1: activate BEFORE showWindow. On macOS 14+, calling
        // `NSApp.activate` after `makeKeyAndOrderFront` from an
        // inactive process state can leave the new key window
        // behind the previously-active app's foreground chrome.
        // Activating first puts the app in the foreground first,
        // then the window order is honored.
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            guard let db = database, let rc = rebuildCoordinator else { return }
            settingsWindowController = SettingsWindowController(
                database: db,
                rebuildCoordinator: rc,
                hotkeyReinstallHandler: { [weak self] in self?.reinstallHotkey() ?? false }
            )
        }
        // Defensive: if the controller exists but its window was
        // somehow released (should not happen — we set
        // isReleasedWhenClosed=false AND keep a NSWindowDelegate
        // hide-only policy), rebuild the controller.
        if settingsWindowController?.window == nil {
            NSLog("SwiftSeek: settings window unexpectedly nil; rebuilding controller")
            settingsWindowController = nil
            showSettings(sender)
            return
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleSearchWindow(_ sender: Any?) {
        searchWindowController?.toggle()
    }

    private func installSearchWindow() {
        guard let db = database else { return }
        searchWindowController = SearchWindowController(database: db)
    }

    private func installGlobalHotkey() {
        let (keyCode, modifiers) = readPersistedHotkey()
        let hk = GlobalHotkey()
        let ok = hk.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.searchWindowController?.toggle()
        }
        if !ok {
            NSLog("SwiftSeek: global hotkey registration failed — fallback to menu item 搜索…")
            maybeAlertHotkeyFailure()
        }
        self.hotkey = hk
    }

    /// E5 re-register the global hotkey after the user picks a new
    /// preset in Settings. Returns true on success so the Settings UI
    /// can revert to the previous selection on failure.
    @discardableResult
    func reinstallHotkey() -> Bool {
        let (keyCode, modifiers) = readPersistedHotkey()
        let hk = self.hotkey ?? GlobalHotkey()
        let ok = hk.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.searchWindowController?.toggle()
        }
        self.hotkey = hk
        if !ok {
            NSLog("SwiftSeek: hotkey re-registration failed at (\(keyCode), \(modifiers))")
        }
        return ok
    }

    private func readPersistedHotkey() -> (keyCode: UInt32, modifiers: UInt32) {
        guard let db = database else {
            return (GlobalHotkey.defaultKeyCode, GlobalHotkey.defaultModifiers)
        }
        do {
            return try db.getHotkey()
        } catch {
            NSLog("SwiftSeek: readPersistedHotkey failed: \(error)")
            return (GlobalHotkey.defaultKeyCode, GlobalHotkey.defaultModifiers)
        }
    }

    private func maybeAlertHotkeyFailure() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hotkeyAlertedKey) { return }
        defaults.set(true, forKey: hotkeyAlertedKey)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "⌥Space 快捷键不可用"
            alert.informativeText = "该快捷键被其他应用占用（常见：Spotlight / 输入法切换）。可随时从菜单「SwiftSeek → 搜索…」或菜单栏图标呼出搜索窗。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    // MARK: - NSStatusItem (menu bar)

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "magnifyingglass",
                                 accessibilityDescription: "SwiftSeek") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "⌕"
            }
            button.toolTip = "SwiftSeek 搜索"
        }

        let menu = NSMenu()

        let searchItem = NSMenuItem(title: "搜索…",
                                    action: #selector(toggleSearchWindow(_:)),
                                    keyEquivalent: " ")
        searchItem.keyEquivalentModifierMask = [.option]
        searchItem.target = self
        menu.addItem(searchItem)

        let settingsItem = NSMenuItem(title: "设置…",
                                      action: #selector(showSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let indexingItem = NSMenuItem(title: "索引：空闲", action: nil, keyEquivalent: "")
        indexingItem.isEnabled = false
        menu.addItem(indexingItem)
        self.statusIndexingItem = indexingItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 SwiftSeek",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    private func reflectRebuildState(_ state: RebuildCoordinator.State) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle:
            statusIndexingItem?.title = "索引：空闲"
            if let img = NSImage(systemSymbolName: "magnifyingglass",
                                 accessibilityDescription: nil) {
                img.isTemplate = true
                button.image = img
            }
            button.title = ""
            button.imagePosition = .imageOnly
        case let .rebuilding(_, processed, total):
            let totalText = total > 0 ? "\(processed)/\(total) roots" : "启动…"
            statusIndexingItem?.title = "索引中 · \(totalText)"
            if let img = NSImage(systemSymbolName: "magnifyingglass.circle",
                                 accessibilityDescription: nil) {
                img.isTemplate = true
                button.image = img
            }
            button.title = " 索引中…"
            button.imagePosition = .imageLeft
        }
    }

    private func presentFatal(error: Error) {
        let alert = NSAlert()
        alert.messageText = "SwiftSeek 启动失败"
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
