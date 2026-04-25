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

        // L1 + L2: pick activation policy BEFORE any window or
        // main-menu installation. L1 introduced `.accessory` as the
        // hard-coded default (menubar-agent / no Dock). L2 makes this
        // user-controllable via a persisted "dock_icon_visible" setting.
        //
        // Order:
        //   1. Apply the L1 default (`.accessory`) up front so a DB
        //      open failure or a brand-new install still leaves us in
        //      menubar-agent mode rather than briefly flashing a Dock
        //      icon during init.
        //   2. After the DB is open below, read the user's persisted
        //      preference. If they have opted into a visible Dock, lift
        //      activation policy to `.regular`. If reading fails, stay
        //      with `.accessory` — the L1 default is the conservative
        //      fallback.
        //
        // Why .accessory at runtime instead of `LSUIElement=true` in
        // Info.plist:
        //   - L2 needs the runtime lever; a baked-in LSUIElement key
        //     would force users to repackage to flip Dock visibility.
        //   - `swift run SwiftSeek` (dev path) inherits the same
        //     behaviour with no plist edits — fewer dev/release drift
        //     traps.
        //   - ad-hoc / unsigned bundles see inconsistent LaunchServices
        //     caching behaviour around `LSUIElement` across macOS
        //     versions; the public AppKit API is the more predictable
        //     path. Info.plist stays at `LSUIElement=false`; runtime
        //     owns the actual policy.
        //
        // Why L2 applies the user preference at launch (not live):
        //   - Live `.regular` ↔ `.accessory` transitions on unsigned
        //     bundles can leave the main menu, Dock icon, and key
        //     window in inconsistent states. Persisting intent + taking
        //     effect on next launch is the honest contract; the
        //     Settings UI tells the user to relaunch.
        NSApp.setActivationPolicy(.accessory)

        NSApp.mainMenu = MainMenu.build(target: self)

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

        // L2: lift to `.regular` only if the user has opted in. Errors
        // are swallowed (logged) rather than fatal — the L1 default is
        // already in effect, so a settings read failure leaves
        // SwiftSeek as a menubar agent rather than crashing the app.
        if let db = database {
            do {
                let dockVisible = try db.getDockIconVisible()
                if dockVisible {
                    NSApp.setActivationPolicy(.regular)
                    NSLog("SwiftSeek: Dock icon visible (user preference); activation policy = .regular")
                } else {
                    NSLog("SwiftSeek: Dock icon hidden (L1 default); activation policy = .accessory")
                }
            } catch {
                NSLog("SwiftSeek: getDockIconVisible failed, keeping L1 .accessory default: \(error)")
            }
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

        // L1: deliberately do NOT auto-show the settings window on
        // launch. The menubar status item is the primary entry point
        // for a menubar-agent app; auto-popping settings every launch
        // would defeat the agent form factor. Users open settings via
        // the status menu's "设置…" item, and the J1 reopen path
        // (applicationShouldHandleReopen) still surfaces settings as a
        // fallback if the user double-clicks the bundle a second time.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// J1 + L1: reopen handler. In Dock-app mode this fires when the
    /// user clicks the Dock icon with no visible windows. In L1's
    /// `.accessory` (menubar-agent) mode the Dock icon is hidden, but
    /// the callback still fires when the user runs `open` against the
    /// bundle a second time (e.g. double-clicking SwiftSeek.app from
    /// Finder while the agent is already running).
    ///
    /// `hasVisibleWindows == true` → AppKit handles it; return true so
    /// the default behaviour kicks in. `false` → there are no visible
    /// windows; show settings as the predictable fallback so the user
    /// always has a visible UI surface to find their way back to the
    /// menubar entry. Search window is intentionally not the fallback
    /// since it hides on resign-key and would feel like the relaunch
    /// "did nothing".
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
