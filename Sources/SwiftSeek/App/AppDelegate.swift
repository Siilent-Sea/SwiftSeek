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
    // L3: status-only menu rows for build identity, index mode, root
    // summary, and DB size. Refreshed in `menuNeedsUpdate(_:)` so the
    // user sees current state every time they pop the menu.
    private var statusBuildItem: NSMenuItem?
    private var statusModeItem: NSMenuItem?
    private var statusRootsItem: NSMenuItem?
    private var statusDBItem: NSMenuItem?
    private(set) var database: Database?

    private let hotkeyAlertedKey = "SwiftSeek.hotkey_fail_alerted_v1"

    /// L3: cache the most recent indexing description string so
    /// `MenubarStatus.snapshot` can include it without poking
    /// RebuildCoordinator from the formatter (Core stays AppKit-free).
    private var lastIndexingDescription: String = "空闲"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // K1: log build identity FIRST so stale-bundle / wrong-binary
        // bug reports always include version, commit, and the actual
        // executable / bundle path. Users pasting the first ~5 lines
        // of Console output is enough to triage "is this the right
        // build?" without further questions.
        NSLog("SwiftSeek: \(BuildInfo.summary)")
        NSLog("SwiftSeek: bundle=\(BuildInfo.bundlePath)")
        NSLog("SwiftSeek: binary=\(BuildInfo.executablePath)")

        // L4: single-instance defense. Run BEFORE we install any UI,
        // open the DB, or register the global hotkey so a duplicate
        // launch does not flicker a second menubar icon, fight over
        // the hotkey, or (most importantly) write to the same DB
        // concurrently and trip SQLite "database is locked".
        //
        // Defense scope: same `CFBundleIdentifier`. This catches:
        //   - Repeated `open` of the same `dist/SwiftSeek.app`.
        //   - `dist/SwiftSeek.app` AND `/Applications/SwiftSeek.app`
        //     running together (both ship the default
        //     `com.local.swiftseek` id from package-app.sh).
        //   - Launch at Login firing while the user double-clicks the
        //     bundle manually.
        // Out of scope: instances with different bundle ids (custom
        // `SWIFTSEEK_BUNDLE_ID=...` repackages). Those are
        // intentionally treated as different apps by macOS.
        if maybeDeferToExistingInstance() {
            return  // we are exiting; nothing else to do
        }
        installShowSettingsObserver()

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
        //
        // N1 (everything-dockless-hardening): regardless of the user
        // setting, log a unified Dock-state line so a Console paste
        // immediately reveals which input is responsible — Info.plist
        // `LSUIElement`, persisted `dock_icon_visible`, or the
        // resulting activation policy. When the setting is true we
        // also emit a second line explaining that Dock visibility is
        // a user-driven choice (not a packaging regression) so a bug
        // report doesn't blame the packager.
        let plistLSUIElementForLog = AppDelegate.lsUIElementValueLabel()
        if let db = database {
            do {
                let dockVisible = try db.getDockIconVisible()
                if dockVisible {
                    NSApp.setActivationPolicy(.regular)
                    NSLog("SwiftSeek: Dock — Info.plist LSUIElement=\(plistLSUIElementForLog); persisted dock_icon_visible=1; chosen activation policy=.regular")
                    NSLog("SwiftSeek: Dock visible because user setting dock_icon_visible=1; toggle off in Settings → 常规 → 在 Dock 显示 SwiftSeek 图标 → 退出 → 重新打开 to hide on next launch.")
                } else {
                    NSLog("SwiftSeek: Dock — Info.plist LSUIElement=\(plistLSUIElementForLog); persisted dock_icon_visible=0; chosen activation policy=.accessory")
                }
            } catch {
                NSLog("SwiftSeek: Dock — Info.plist LSUIElement=\(plistLSUIElementForLog); persisted dock_icon_visible=<read failed: \(error)>; chosen activation policy=.accessory (L1 default)")
            }
        } else {
            NSLog("SwiftSeek: Dock — Info.plist LSUIElement=\(plistLSUIElementForLog); persisted dock_icon_visible=<no DB>; chosen activation policy=.accessory (L1 default)")
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

    /// L4: scan the running-application table for siblings with the
    /// same bundle id, log any conflict honestly, ask the survivor
    /// to surface settings, and exit ourselves. Returns true when we
    /// are deferring (the caller should `return` immediately and let
    /// the runloop tear us down); false when we are the first
    /// instance and should proceed with normal startup.
    private func maybeDeferToExistingInstance() -> Bool {
        // Bundle id resolution: prefer the actually-loaded
        // Info.plist value because tests / repackages can override
        // it. If the bundle isn't published (raw `swift run` from
        // the repo without an .app wrapper), `Bundle.main.bundleIdentifier`
        // is nil — in that path single-instance is best-effort and
        // we fall back to "no defense" rather than guessing.
        guard let bundleId = Bundle.main.bundleIdentifier else {
            NSLog("SwiftSeek: single-instance check skipped (Bundle.main.bundleIdentifier is nil; likely raw swift run)")
            return false
        }
        let myPid = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let candidates: [SingleInstance.Sibling] = running.map { app in
            SingleInstance.Sibling(pid: app.processIdentifier,
                                   bundlePath: app.bundleURL?.path,
                                   executablePath: app.executableURL?.path)
        }
        guard let sibling = SingleInstance.chooseSibling(myPid: myPid, candidates: candidates) else {
            return false  // we are the first / only instance
        }

        // Log honestly so a user staring at the multi-bundle case
        // can see exactly which two paths are involved before we
        // exit.
        NSLog(SingleInstance.conflictLogLine(
            ourPid: myPid,
            ourBundlePath: BuildInfo.bundlePath,
            ourExecutablePath: BuildInfo.executablePath,
            sibling: sibling
        ))

        // Best-effort: ask the older instance to surface its
        // settings window so the user gets visible feedback that
        // "the app is already running, here it is" instead of a
        // silent no-op. We try two activation paths:
        //   1. Direct NSRunningApplication.activate — most reliable
        //      when both processes are in the same user session.
        //   2. DistributedNotification — fallback for rare cases
        //      where direct activate doesn't surface the window
        //      (the older instance handles the notification by
        //      calling showSettings(_:)).
        if let older = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first(where: { $0.processIdentifier == sibling.pid }) {
            older.activate(options: [.activateAllWindows])
        }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(SingleInstance.showSettingsNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        // Exit on the next runloop tick so the post above has time
        // to flush. `NSApp.terminate(nil)` is the polite path; the
        // older instance survives.
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        return true
    }

    /// L4: as the surviving instance, listen for "show settings"
    /// requests from a later launching instance that detected us
    /// and is exiting. When a notification arrives, surface the
    /// settings window so the user sees something happen.
    private func installShowSettingsObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(SingleInstance.showSettingsNotificationName),
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            // Routes through our existing showSettings path so it
            // honors J1's "activate before makeKeyAndOrderFront"
            // ordering and J6's tab-state restoration.
            self?.showSettings(nil)
        }
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
        // L3: NSMenuDelegate so we can refresh status rows when the
        // user pops the menu (instead of trying to push every state
        // change into the menu, which would require listening on
        // settings/db churn that L3 explicitly avoids).
        menu.delegate = self

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

        // L3: read-only status rows. Disabled (non-clickable) so they
        // visually read as state, not actions. Wording is filled in
        // by `refreshMenubarStatus()` on every menu open and again
        // when rebuild state changes.
        let buildItem = NSMenuItem(title: BuildInfo.summary, action: nil, keyEquivalent: "")
        buildItem.isEnabled = false
        menu.addItem(buildItem)
        self.statusBuildItem = buildItem

        let modeItem = NSMenuItem(title: "模式：—", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)
        self.statusModeItem = modeItem

        let rootsItem = NSMenuItem(title: "roots：—", action: nil, keyEquivalent: "")
        rootsItem.isEnabled = false
        menu.addItem(rootsItem)
        self.statusRootsItem = rootsItem

        let dbItem = NSMenuItem(title: "DB 大小：—", action: nil, keyEquivalent: "")
        dbItem.isEnabled = false
        menu.addItem(dbItem)
        self.statusDBItem = dbItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 SwiftSeek",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item

        // Initial population so first hover (before menu open) and
        // tooltip already reflect real state. This pays a one-shot
        // sync cost on app launch (≤ a few hundred ms even on 3.4 GB
        // DB) so the very first menu open shows real numbers; later
        // refreshes run async to keep the menu instant.
        refreshMenubarStatus(synchronous: true)
    }

    /// L3: pull fresh state from Core's MenubarStatus formatter and
    /// shove it into the status-only menu items + button tooltip.
    ///
    /// N4 hotfix: `MenubarStatus.snapshot` calls `computeStats` (which
    /// does `COUNT(*) FROM files` etc.) and `computeRootHealthReport`
    /// per root. On a 3.4 GB DB the COUNT can take several seconds,
    /// and running it on the main thread inside
    /// `menuNeedsUpdate(_:)` blocks AppKit's menu render → the user
    /// experiences a ~10s freeze every time they click the menubar
    /// icon. Move the heavy snapshot to a background queue; the menu
    /// opens instantly with the previous (cached) labels and the new
    /// values land on the next refresh tick.
    ///
    /// `synchronous=true` is for the very first call (installStatusItem)
    /// where we want real values before the menu can possibly be
    /// opened — that's a one-shot startup cost.
    fileprivate func refreshMenubarStatus(synchronous: Bool = false) {
        guard let db = database else {
            // Pre-DB state: leave the seeded "—" placeholders. Better
            // than crashing or pretending we have stats.
            statusItem?.button?.toolTip = "SwiftSeek 搜索"
            return
        }
        let indexing = lastIndexingDescription
        let work: () -> Void = { [weak self] in
            let snapshot = MenubarStatus.snapshot(database: db,
                                                  indexingDescription: indexing)
            let apply: () -> Void = {
                guard let self = self else { return }
                self.statusBuildItem?.title = snapshot.buildSummary
                self.statusIndexingItem?.title = "索引：\(snapshot.indexingDescription)"
                self.statusModeItem?.title = "模式：\(snapshot.indexModeLabel)"
                self.statusRootsItem?.title = "roots：\(snapshot.rootsLabel)"
                self.statusDBItem?.title = snapshot.dbSizeLabel
                self.statusItem?.button?.toolTip = MenubarStatus.tooltipText(snapshot: snapshot)
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
        if synchronous {
            work()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    }

    private func reflectRebuildState(_ state: RebuildCoordinator.State) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle:
            statusIndexingItem?.title = "索引：空闲"
            lastIndexingDescription = "空闲"
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
            lastIndexingDescription = "索引中 · \(totalText)"
            if let img = NSImage(systemSymbolName: "magnifyingglass.circle",
                                 accessibilityDescription: nil) {
                img.isTemplate = true
                button.image = img
            }
            button.title = " 索引中…"
            button.imagePosition = .imageLeft
        }
        // L3: refresh tooltip + status rows so the menubar's quick
        // glance always reflects the current indexing state, even
        // when the user hasn't popped the menu yet.
        refreshMenubarStatus()
    }

    /// N1: read the Info.plist `LSUIElement` value and return a
    /// log-friendly string. AppKit-side because `Bundle.main` is the
    /// authoritative source and we don't want Core to depend on
    /// AppKit. Returns "true" / "false" / "<absent>" / "<not Bool>".
    static func lsUIElementValueLabel() -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") else {
            return "<absent>"
        }
        if let b = raw as? Bool { return b ? "true" : "false" }
        // Some plists store the value as NSNumber 0/1 instead of bool.
        if let n = raw as? NSNumber { return n.boolValue ? "true" : "false" }
        return "<not Bool>"
    }

    /// N1: optional `LSUIElement` as Bool? for `Diagnostics.snapshot`'s
    /// `DockStatusProbe`. nil when the key is absent or non-Bool.
    static func lsUIElementBool() -> Bool? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") else { return nil }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }

    /// N1: human-readable label for `NSApp.activationPolicy()`.
    static func activationPolicyLabel() -> String {
        switch NSApp.activationPolicy() {
        case .regular: return "regular"
        case .accessory: return "accessory"
        case .prohibited: return "prohibited"
        @unknown default: return "unknown"
        }
    }

    /// N1: convenience builder for the AppKit-bound Dock probe
    /// consumed by `Diagnostics.snapshot`. AboutPane uses this.
    static func currentDockStatusReport() -> Diagnostics.DockStatusReport {
        return Diagnostics.DockStatusReport(activationPolicyLabel: activationPolicyLabel(),
                                lsUIElement: lsUIElementBool())
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

// MARK: - L3 NSMenuDelegate

/// L3: refresh the status menu's read-only state rows whenever the
/// user pops the menu. Keeps DB / settings reads out of every state
/// change path; we only pay the cost when the menu is actually
/// being viewed.
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Only one menu uses this delegate (the status item's menu),
        // so no menu === statusItem?.menu identity check needed; if
        // we add more delegate-using menus later, gate here.
        refreshMenubarStatus()
    }
}
