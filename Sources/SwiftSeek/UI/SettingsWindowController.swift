import AppKit
import SwiftSeekCore

/// Settings window. Holds four tabs (常规 / 索引范围 / 维护 / 关于) each of
/// which writes straight through to the shared `Database` (for roots, excludes,
/// hidden files toggle) or to the shared `RebuildCoordinator`.
///
/// Owned by `AppDelegate`; torn down on app exit. Each tab is its own
/// `NSViewController` and reads from disk on `viewWillAppear` so switching back
/// to a tab always reflects external changes (e.g. the smoke CLI edited excludes).
final class SettingsWindowController: NSWindowController {
    private let database: Database
    private let rebuildCoordinator: RebuildCoordinator
    private let hotkeyReinstallHandler: (() -> Bool)?
    private let banner = NSTextField(wrappingLabelWithString: "")
    private let bannerContainer = NSView()
    private var bannerHeightConstraint: NSLayoutConstraint?

    init(database: Database,
         rebuildCoordinator: RebuildCoordinator,
         hotkeyReinstallHandler: (() -> Bool)? = nil) {
        self.database = database
        self.rebuildCoordinator = rebuildCoordinator
        self.hotkeyReinstallHandler = hotkeyReinstallHandler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftSeek 设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 380)

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar

        let generalPane = GeneralPane(database: database,
                                      rebuildCoordinator: rebuildCoordinator)
        generalPane.hotkeyReinstallHandler = hotkeyReinstallHandler
        let indexingPane = IndexingPane(database: database,
                                        rebuildCoordinator: rebuildCoordinator)
        let maintenancePane = MaintenancePane(database: database,
                                              rebuildCoordinator: rebuildCoordinator)
        let aboutPane = AboutPane(database: database)

        tabVC.addTabViewItem(Self.makeTab(label: "常规", identifier: "general", vc: generalPane))
        tabVC.addTabViewItem(Self.makeTab(label: "索引范围", identifier: "indexing", vc: indexingPane))
        tabVC.addTabViewItem(Self.makeTab(label: "维护", identifier: "maintenance", vc: maintenancePane))
        tabVC.addTabViewItem(Self.makeTab(label: "关于", identifier: "about", vc: aboutPane))

        let host = NSViewController()
        let hostView = NSView()
        hostView.translatesAutoresizingMaskIntoConstraints = false
        host.view = hostView

        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.wantsLayer = true
        bannerContainer.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        banner.stringValue = "👋 先在「索引范围」添加要搜索的目录，添加后会提示自动索引。之后按 ⌥Space 随时搜索。"
        bannerContainer.addSubview(banner)

        let tabContainer = tabVC.view
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(bannerContainer)
        hostView.addSubview(tabContainer)
        host.addChild(tabVC)

        let bh = bannerContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            bannerContainer.topAnchor.constraint(equalTo: hostView.topAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            bannerContainer.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            bh,

            banner.topAnchor.constraint(equalTo: bannerContainer.topAnchor, constant: 10),
            banner.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor, constant: -10),
            banner.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor, constant: -16),

            tabContainer.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            tabContainer.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            tabContainer.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            tabContainer.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])

        window.contentViewController = host
        super.init(window: window)
        self.bannerHeightConstraint = bh
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshBanner()
    }

    func refreshBanner() {
        let rootsEmpty: Bool
        do {
            rootsEmpty = try database.listRoots().isEmpty
        } catch {
            NSLog("SwiftSeek: SettingsWindow banner listRoots failed: \(error)")
            // On read failure surface guidance rather than silently hide the
            // banner — if the user really has roots, the next successful open
            // will refresh to accurate state.
            banner.stringValue = "⚠️ 读取索引目录失败：\(error)。请检查数据库或查看 Console.app"
            bannerContainer.isHidden = false
            bannerHeightConstraint?.isActive = false
            return
        }
        banner.stringValue = "👋 先在「索引范围」添加要搜索的目录，添加后会提示自动索引。之后按 ⌥Space 随时搜索。"
        bannerContainer.isHidden = !rootsEmpty
        bannerHeightConstraint?.isActive = !rootsEmpty
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private static func makeTab(label: String,
                                identifier: String,
                                vc: NSViewController) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: vc)
        item.label = label
        item.identifier = identifier
        return item
    }
}

// MARK: - 常规 Pane

private final class GeneralPane: NSViewController {
    private let database: Database
    private let rebuildCoordinator: RebuildCoordinator
    private let checkbox = NSButton(checkboxWithTitle: "索引隐藏文件（名字或路径包含 . 开头组件）",
                                    target: nil, action: nil)
    private let rebuildNowBtn = NSButton(title: "立即重建", target: nil, action: nil)
    private let note = NSTextField(wrappingLabelWithString: "")
    // E1: search result limit setting
    private let limitLabel = NSTextField(labelWithString: "搜索结果上限：")
    private let limitField = NSTextField()
    private let limitStepper = NSStepper()
    private let limitNote = NSTextField(wrappingLabelWithString: "")
    // E5: hotkey preset picker
    private let hotkeyLabel = NSTextField(labelWithString: "全局热键：")
    private let hotkeyPopup = NSPopUpButton()
    private let hotkeyNote = NSTextField(wrappingLabelWithString: "")
    // G4: index mode picker (compact vs fullpath).
    private let modeLabel = NSTextField(labelWithString: "索引模式：")
    private let modePopup = NSPopUpButton()
    private let modeNote = NSTextField(wrappingLabelWithString: "")
    /// Closure injected by AppDelegate so this pane can trigger
    /// re-registration of the Carbon hotkey without reaching through
    /// the view hierarchy. Returns true iff the new combo registered
    /// successfully.
    var hotkeyReinstallHandler: (() -> Bool)?

    init(database: Database, rebuildCoordinator: RebuildCoordinator) {
        self.database = database
        self.rebuildCoordinator = rebuildCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))

        let title = NSTextField(labelWithString: "常规")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.target = self
        checkbox.action = #selector(onToggle(_:))

        rebuildNowBtn.bezelStyle = .rounded
        rebuildNowBtn.target = self
        rebuildNowBtn.action = #selector(onRebuildNow)
        rebuildNowBtn.translatesAutoresizingMaskIntoConstraints = false

        note.translatesAutoresizingMaskIntoConstraints = false
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.stringValue = "关闭时，任意路径段以 . 开头的文件与目录（如 .git、.DS_Store、~/.ssh）都不会进入索引。切换后点「立即重建」立即生效。"

        let row = NSStackView(views: [checkbox, rebuildNowBtn])
        row.orientation = .horizontal
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        // E1 search-limit row: label + number field + stepper + note
        limitLabel.translatesAutoresizingMaskIntoConstraints = false
        limitField.translatesAutoresizingMaskIntoConstraints = false
        limitField.alignment = .right
        limitField.isBordered = true
        limitField.isEditable = true
        limitField.target = self
        limitField.action = #selector(onLimitFieldChanged)
        limitField.formatter = NumberFormatter()
        limitField.widthAnchor.constraint(equalToConstant: 72).isActive = true

        limitStepper.translatesAutoresizingMaskIntoConstraints = false
        limitStepper.minValue = Double(SearchLimitBounds.minimum)
        limitStepper.maxValue = Double(SearchLimitBounds.maximum)
        limitStepper.increment = 10
        limitStepper.valueWraps = false
        limitStepper.target = self
        limitStepper.action = #selector(onLimitStepperChanged)

        limitNote.translatesAutoresizingMaskIntoConstraints = false
        limitNote.font = NSFont.systemFont(ofSize: 11)
        limitNote.textColor = .secondaryLabelColor
        limitNote.stringValue = "搜索窗每次最多显示的结果数量，范围 \(SearchLimitBounds.minimum)–\(SearchLimitBounds.maximum)，默认 \(SearchLimitBounds.defaultValue)。修改后无需重启。"

        let limitRow = NSStackView(views: [limitLabel, limitField, limitStepper])
        limitRow.orientation = .horizontal
        limitRow.spacing = 8
        limitRow.alignment = .centerY
        limitRow.translatesAutoresizingMaskIntoConstraints = false

        // E5 hotkey row
        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        hotkeyPopup.translatesAutoresizingMaskIntoConstraints = false
        hotkeyPopup.removeAllItems()
        for preset in HotkeyPresets.all {
            hotkeyPopup.addItem(withTitle: preset.label)
        }
        hotkeyPopup.target = self
        hotkeyPopup.action = #selector(onHotkeyChanged)

        hotkeyNote.translatesAutoresizingMaskIntoConstraints = false
        hotkeyNote.font = NSFont.systemFont(ofSize: 11)
        hotkeyNote.textColor = .secondaryLabelColor
        hotkeyNote.stringValue = "全局热键呼出搜索窗。如果选择的组合被系统或其他应用占用，切换后会弹窗提示并恢复上一个有效值。"

        let hotkeyRow = NSStackView(views: [hotkeyLabel, hotkeyPopup])
        hotkeyRow.orientation = .horizontal
        hotkeyRow.spacing = 8
        hotkeyRow.alignment = .centerY
        hotkeyRow.translatesAutoresizingMaskIntoConstraints = false

        // G4 index mode picker
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        modePopup.removeAllItems()
        modePopup.addItem(withTitle: "Compact（推荐）")
        modePopup.item(at: 0)?.representedObject = IndexMode.compact.rawValue
        modePopup.addItem(withTitle: "Full path substring（高级，更大体积）")
        modePopup.item(at: 1)?.representedObject = IndexMode.fullpath.rawValue
        modePopup.target = self
        modePopup.action = #selector(onIndexModeChanged)

        modeNote.translatesAutoresizingMaskIntoConstraints = false
        modeNote.font = NSFont.systemFont(ofSize: 11)
        modeNote.textColor = .secondaryLabelColor
        modeNote.maximumNumberOfLines = 0
        modeNote.stringValue = """
        Compact（推荐）：只对文件名做 gram，路径按 segment 前缀匹配；500k 文件体积 ≈ 10× 更小。\
        plain query 只匹配文件名；路径 token 用 `path:<token>` 做 segment 前缀。
        Full path substring：对完整路径做 gram；任意路径子串均能命中，但体积显著更大。\
        切换后需要重建索引（compact）或回填（fullpath → compact 时启动后台 backfill）。
        """

        let modeRow = NSStackView(views: [modeLabel, modePopup])
        modeRow.orientation = .horizontal
        modeRow.spacing = 8
        modeRow.alignment = .centerY
        modeRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(title)
        root.addSubview(row)
        root.addSubview(note)
        root.addSubview(limitRow)
        root.addSubview(limitNote)
        root.addSubview(hotkeyRow)
        root.addSubview(hotkeyNote)
        root.addSubview(modeRow)
        root.addSubview(modeNote)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            row.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),

            note.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 6),
            note.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            note.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            limitRow.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 24),
            limitRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            limitNote.topAnchor.constraint(equalTo: limitRow.bottomAnchor, constant: 6),
            limitNote.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            limitNote.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            hotkeyRow.topAnchor.constraint(equalTo: limitNote.bottomAnchor, constant: 24),
            hotkeyRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            hotkeyNote.topAnchor.constraint(equalTo: hotkeyRow.bottomAnchor, constant: 6),
            hotkeyNote.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            hotkeyNote.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            modeRow.topAnchor.constraint(equalTo: hotkeyNote.bottomAnchor, constant: 24),
            modeRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            modeNote.topAnchor.constraint(equalTo: modeRow.bottomAnchor, constant: 6),
            modeNote.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            modeNote.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        do {
            checkbox.state = try database.getHiddenFilesEnabled() ? .on : .off
        } catch {
            NSLog("SwiftSeek: GeneralPane read hidden flag failed: \(error)")
            checkbox.state = .off
        }
        rebuildNowBtn.isEnabled = !rebuildCoordinator.isRebuilding

        // E1: surface the current persisted limit (or default).
        let current: Int
        do {
            current = try database.getSearchLimit()
        } catch {
            NSLog("SwiftSeek: GeneralPane read search limit failed: \(error)")
            current = SearchLimitBounds.defaultValue
        }
        limitField.integerValue = current
        limitStepper.integerValue = current

        // E5: reflect persisted hotkey selection in the popup.
        let (hkKey, hkMods): (UInt32, UInt32)
        do {
            (hkKey, hkMods) = try database.getHotkey()
        } catch {
            NSLog("SwiftSeek: GeneralPane read hotkey failed: \(error)")
            hkKey = HotkeyPresets.default.keyCode
            hkMods = HotkeyPresets.default.modifiers
        }
        let matching = HotkeyPresets.preset(keyCode: hkKey, modifiers: hkMods)
                    ?? HotkeyPresets.default
        hotkeyPopup.selectItem(withTitle: matching.label)

        // G4: reflect persisted index mode in the popup.
        let mode: IndexMode
        do {
            mode = try database.getIndexMode()
        } catch {
            NSLog("SwiftSeek: GeneralPane read index mode failed: \(error)")
            mode = .compact
        }
        let idx = (mode == .compact) ? 0 : 1
        modePopup.selectItem(at: idx)
    }

    @objc private func onToggle(_ sender: NSButton) {
        do {
            try database.setHiddenFilesEnabled(sender.state == .on)
        } catch {
            NSLog("SwiftSeek: failed to persist hidden-files toggle: \(error)")
            return
        }
        // E4: make the “takes effect on next rebuild” semantics explicit.
        // The note above the checkbox already says so, but a transient
        // confirmation after the toggle reduces the odds that a user
        // flips the switch, searches for a hidden file, sees nothing, and
        // concludes the feature is broken.
        let want = sender.state == .on
        let alert = NSAlert()
        alert.messageText = want ? "隐藏文件将进入索引" : "隐藏文件将从索引排除"
        alert.informativeText = "开关已保存，新扫描会按新规则生效。已有索引数据仍按旧规则保留；点击「立即重建」可立刻同步。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即重建")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            onRebuildNow()
        }
    }

    @objc private func onLimitStepperChanged() {
        let n = clampSearchLimit(limitStepper.integerValue)
        limitField.integerValue = n
        persistLimit(n)
    }

    @objc private func onLimitFieldChanged() {
        let raw = limitField.integerValue
        let n = clampSearchLimit(raw == 0 ? SearchLimitBounds.defaultValue : raw)
        limitField.integerValue = n
        limitStepper.integerValue = n
        persistLimit(n)
    }

    private func persistLimit(_ n: Int) {
        do {
            try database.setSearchLimit(n)
        } catch {
            NSLog("SwiftSeek: failed to persist search limit: \(error)")
        }
    }

    @objc private func onIndexModeChanged() {
        guard let raw = modePopup.selectedItem?.representedObject as? String,
              let newMode = IndexMode(rawValue: raw) else { return }
        let previousMode: IndexMode
        do {
            previousMode = try database.getIndexMode()
        } catch {
            NSLog("SwiftSeek: onIndexModeChanged could not read current mode: \(error)")
            previousMode = .compact
        }
        if newMode == previousMode { return }

        // Confirm + persist + guide to the rebuild/backfill flow.
        let alert = NSAlert()
        let alertMsg: String
        let informative: String
        switch newMode {
        case .compact:
            alertMsg = "切换到 Compact 索引模式"
            informative = """
            新 plain query 只匹配文件名，路径 token 用 `path:<token>` 前缀匹配。
            已索引的 fullpath 数据保留在 v4 表中，但搜索将走 compact 路径。
            需要回填已索引文件到 compact 表才能搜出它们；点下方 "切换并开始 compact 回填"。
            """
        case .fullpath:
            alertMsg = "切换到 Full path substring 模式"
            informative = """
            plain query 将同时匹配文件名和路径任意子串。
            已有 compact 表保留但不再用于查询。
            如 v4 表已被清空（"清空 v4 索引" 按钮），需在维护 tab 触发全量重建。
            """
        }
        alert.messageText = alertMsg
        alert.informativeText = informative
        alert.alertStyle = .informational
        alert.addButton(withTitle: (newMode == .compact) ? "切换并开始 compact 回填" : "切换")
        alert.addButton(withTitle: "取消")
        let choice = alert.runModal()
        if choice != .alertFirstButtonReturn {
            // Roll back UI selection to previous mode
            modePopup.selectItem(at: (previousMode == .compact) ? 0 : 1)
            return
        }
        do {
            try database.setIndexMode(newMode)
        } catch {
            NSLog("SwiftSeek: setIndexMode failed: \(error)")
            modePopup.selectItem(at: (previousMode == .compact) ? 0 : 1)
            return
        }
        // If switching to compact, kick a backfill on a background
        // coordinator. We don't block the UI; a status toast lets the
        // user know it's running. Maintenance tab shows progress.
        if newMode == .compact {
            let coord = MigrationCoordinator(database: database)
            _ = coord.backfillCompact(onFinish: { summary in
                if let err = summary.error {
                    NSLog("SwiftSeek: compact backfill finished with error: \(err)")
                }
            })
        }
    }

    @objc private func onHotkeyChanged() {
        // Remember the previous persisted combo so we can roll back if
        // the new one fails to register (e.g. taken by Spotlight).
        let previous: (UInt32, UInt32)
        do {
            previous = try database.getHotkey()
        } catch {
            previous = (HotkeyPresets.default.keyCode, HotkeyPresets.default.modifiers)
        }
        guard let title = hotkeyPopup.titleOfSelectedItem,
              let preset = HotkeyPresets.all.first(where: { $0.label == title }) else {
            return
        }
        do {
            try database.setHotkey(keyCode: preset.keyCode, modifiers: preset.modifiers)
        } catch {
            NSLog("SwiftSeek: failed to persist hotkey: \(error)")
            return
        }
        let ok = hotkeyReinstallHandler?() ?? false
        if !ok {
            // Roll back: restore previous combo both in DB and in the popup.
            do {
                try database.setHotkey(keyCode: previous.0, modifiers: previous.1)
            } catch {
                NSLog("SwiftSeek: failed to roll back hotkey: \(error)")
            }
            _ = hotkeyReinstallHandler?()
            if let old = HotkeyPresets.preset(keyCode: previous.0, modifiers: previous.1) {
                hotkeyPopup.selectItem(withTitle: old.label)
            }
            let alert = NSAlert()
            alert.messageText = "无法注册该热键"
            alert.informativeText = "\(preset.label) 可能被系统或其他应用占用。已恢复为上一个有效组合。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func onRebuildNow() {
        rebuildNowBtn.isEnabled = false
        let ok = rebuildCoordinator.rebuild(
            onFinish: { [weak self] _ in
                DispatchQueue.main.async { self?.rebuildNowBtn.isEnabled = true }
            }
        )
        if !ok { rebuildNowBtn.isEnabled = true }
    }
}

// MARK: - 索引范围 Pane (roots + excludes)

private final class IndexingPane: NSViewController {
    private let database: Database
    private let rebuildCoordinator: RebuildCoordinator
    private let rootsTable = NSTableView()
    private let excludesTable = NSTableView()
    private let rootsStatus = NSTextField(labelWithString: "")
    private let excludesStatus = NSTextField(labelWithString: "")

    private var roots: [RootRow] = []
    private var excludes: [ExcludeRow] = []

    init(database: Database, rebuildCoordinator: RebuildCoordinator) {
        self.database = database
        self.rebuildCoordinator = rebuildCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))

        // Roots header
        let rootsTitle = NSTextField(labelWithString: "索引目录（roots）")
        rootsTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        rootsTitle.translatesAutoresizingMaskIntoConstraints = false

        rootsStatus.font = NSFont.systemFont(ofSize: 11)
        rootsStatus.textColor = .secondaryLabelColor
        rootsStatus.translatesAutoresizingMaskIntoConstraints = false

        // Roots table + scroll
        let rootsScroll = NSScrollView()
        rootsScroll.translatesAutoresizingMaskIntoConstraints = false
        rootsScroll.hasVerticalScroller = true
        rootsScroll.borderType = .bezelBorder
        rootsTable.headerView = nil
        rootsTable.style = .fullWidth
        rootsTable.allowsMultipleSelection = false
        let rootsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("roots"))
        rootsCol.resizingMask = .autoresizingMask
        rootsTable.addTableColumn(rootsCol)
        rootsTable.dataSource = self
        rootsTable.delegate = self
        rootsTable.target = self
        rootsTable.registerForDraggedTypes([.fileURL])
        rootsScroll.documentView = rootsTable

        // Roots buttons
        let addRootBtn = NSButton(title: "新增目录…", target: self, action: #selector(onAddRoot))
        let removeRootBtn = NSButton(title: "移除所选", target: self, action: #selector(onRemoveRoot))
        let toggleRootBtn = NSButton(title: "启用/停用所选", target: self, action: #selector(onToggleRoot))
        let rootsBar = NSStackView(views: [addRootBtn, removeRootBtn, toggleRootBtn])
        rootsBar.orientation = .horizontal
        rootsBar.spacing = 8
        rootsBar.translatesAutoresizingMaskIntoConstraints = false

        // Excludes header
        let excludesTitle = NSTextField(labelWithString: "排除目录（excludes）")
        excludesTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        excludesTitle.translatesAutoresizingMaskIntoConstraints = false

        excludesStatus.font = NSFont.systemFont(ofSize: 11)
        excludesStatus.textColor = .secondaryLabelColor
        excludesStatus.translatesAutoresizingMaskIntoConstraints = false

        // Excludes table + scroll
        let excludesScroll = NSScrollView()
        excludesScroll.translatesAutoresizingMaskIntoConstraints = false
        excludesScroll.hasVerticalScroller = true
        excludesScroll.borderType = .bezelBorder
        excludesTable.headerView = nil
        excludesTable.style = .fullWidth
        excludesTable.allowsMultipleSelection = false
        let exCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("excludes"))
        exCol.resizingMask = .autoresizingMask
        excludesTable.addTableColumn(exCol)
        excludesTable.dataSource = self
        excludesTable.delegate = self
        excludesScroll.documentView = excludesTable

        let addExBtn = NSButton(title: "新增排除目录…", target: self, action: #selector(onAddExclude))
        let removeExBtn = NSButton(title: "移除所选", target: self, action: #selector(onRemoveExclude))
        let excludesBar = NSStackView(views: [addExBtn, removeExBtn])
        excludesBar.orientation = .horizontal
        excludesBar.spacing = 8
        excludesBar.translatesAutoresizingMaskIntoConstraints = false

        [rootsTitle, rootsStatus, rootsScroll, rootsBar,
         excludesTitle, excludesStatus, excludesScroll, excludesBar].forEach { root.addSubview($0) }

        NSLayoutConstraint.activate([
            rootsTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            rootsTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            rootsStatus.centerYAnchor.constraint(equalTo: rootsTitle.centerYAnchor),
            rootsStatus.leadingAnchor.constraint(equalTo: rootsTitle.trailingAnchor, constant: 16),
            rootsStatus.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            rootsScroll.topAnchor.constraint(equalTo: rootsTitle.bottomAnchor, constant: 8),
            rootsScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            rootsScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            rootsScroll.heightAnchor.constraint(equalToConstant: 140),

            rootsBar.topAnchor.constraint(equalTo: rootsScroll.bottomAnchor, constant: 8),
            rootsBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            rootsBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            excludesTitle.topAnchor.constraint(equalTo: rootsBar.bottomAnchor, constant: 24),
            excludesTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            excludesStatus.centerYAnchor.constraint(equalTo: excludesTitle.centerYAnchor),
            excludesStatus.leadingAnchor.constraint(equalTo: excludesTitle.trailingAnchor, constant: 16),

            excludesScroll.topAnchor.constraint(equalTo: excludesTitle.bottomAnchor, constant: 8),
            excludesScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            excludesScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            excludesScroll.heightAnchor.constraint(equalToConstant: 110),

            excludesBar.topAnchor.constraint(equalTo: excludesScroll.bottomAnchor, constant: 8),
            excludesBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            excludesBar.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
        ])
        self.view = root
    }

    // E4: subscribe to rebuild state transitions while this pane is on
    // screen so the roots health column refreshes live as indexing
    // progresses. We chain the previous observer (typically AppDelegate's
    // menu-bar updater) so menu-bar state continues to work.
    private var previousStateObserver: ((RebuildCoordinator.State) -> Void)?

    override func viewWillAppear() {
        super.viewWillAppear()
        previousStateObserver = rebuildCoordinator.onStateChange
        let chained = previousStateObserver
        rebuildCoordinator.onStateChange = { [weak self] state in
            chained?(state)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reload()
                // E4 round 2: when the coordinator returns to idle, drain
                // any pending auto-index work that was deferred because
                // another rebuild was in flight.
                if case .idle = state {
                    self.drainAutoIndexQueue()
                }
            }
        }
        reload()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        rebuildCoordinator.onStateChange = previousStateObserver
        previousStateObserver = nil
    }

    private func reload() {
        do {
            roots = try database.listRoots()
        } catch {
            NSLog("SwiftSeek: IndexingPane listRoots failed: \(error)")
            roots = []
            rootsStatus.stringValue = "读取 roots 失败：\(error)"
        }
        do {
            excludes = try database.listExcludes()
        } catch {
            NSLog("SwiftSeek: IndexingPane listExcludes failed: \(error)")
            excludes = []
            excludesStatus.stringValue = "读取 excludes 失败：\(error)"
        }
        let enabledCount = roots.filter { $0.enabled }.count
        if !rootsStatus.stringValue.hasPrefix("读取") {
            // E4: note the new state vocabulary. 状态标签包含就绪/索引中/停用/未挂载/不可访问，
            // 便于用户自解释“这个 root 为什么没结果”。
            rootsStatus.stringValue = "共 \(roots.count) 项，启用 \(enabledCount) · 新增目录后自动后台索引；状态列展示 就绪 / 索引中 / 停用 / 未挂载 / 不可访问"
        }
        if !excludesStatus.stringValue.hasPrefix("读取") {
            excludesStatus.stringValue = "共 \(excludes.count) 项 · 新增立即清理已索引子树（无需重建）"
        }
        rootsTable.reloadData()
        excludesTable.reloadData()
    }

    @objc private func onAddRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要纳入索引的目录"
        panel.prompt = "加入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addRoot(path: url.path)
    }

    private func addRoot(path: String) {
        let canonical = Indexer.canonicalize(path: path)
        do {
            _ = try database.registerRoot(path: canonical)
            reload()
            if let wc = view.window?.windowController as? SettingsWindowController {
                wc.refreshBanner()
            }
            // E4: no more confirmation dialog — just kick the background
            // indexer. UI surfaces status via the root row's health badge
            // and the menu bar status item, so asking the user "do you
            // want to index?" is redundant.
            autoIndexAfterAdd(path: canonical)
        } catch {
            presentError(error, message: "新增 root 失败")
        }
    }

    // E4 round 2 fix: drag-adding N directories used to only auto-index
    // the last one because we called indexOneRoot exactly once at the
    // tail of the drop handler. Now we maintain a FIFO of pending paths
    // and kick them serially: indexOneRoot for the first, then each
    // onFinish pops the next until the queue drains. This covers both
    // the single-add path (queue of length 1) and the multi-drop path.
    private var pendingAutoIndex: [String] = []

    private func autoIndexAfterAdd(path: String) {
        pendingAutoIndex.append(path)
        reload() // reflect 索引中 badge as soon as possible
        if !rebuildCoordinator.isRebuilding {
            drainAutoIndexQueue()
        }
    }

    private func drainAutoIndexQueue() {
        guard !pendingAutoIndex.isEmpty else { return }
        let next = pendingAutoIndex.removeFirst()
        let ok = rebuildCoordinator.indexOneRoot(
            path: next,
            onFinish: { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.reload()
                    self.drainAutoIndexQueue()
                }
            }
        )
        if !ok {
            // Another rebuild is in flight: re-queue at the head and
            // wait for it to land. drainAutoIndexQueue will be re-kicked
            // by the IndexingPane's chained onStateChange observer when
            // the coordinator returns to .idle.
            pendingAutoIndex.insert(next, at: 0)
            NSLog("SwiftSeek: auto-index deferred for \(next) (another rebuild in flight)")
        }
    }

    @objc private func onRemoveRoot() {
        let row = rootsTable.selectedRow
        guard row >= 0 && row < roots.count else { return }
        let r = roots[row]
        let alert = NSAlert()
        alert.messageText = "移除 root：\(r.path)？"
        alert.informativeText = "该 root 下已索引的文件记录也会一并清理。可随时重新新增。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try database.removeRoot(id: r.id)
                reload()
            } catch {
                presentError(error, message: "移除 root 失败")
            }
        }
    }

    @objc private func onToggleRoot() {
        let row = rootsTable.selectedRow
        guard row >= 0 && row < roots.count else { return }
        let r = roots[row]
        do {
            try database.setRootEnabled(id: r.id, enabled: !r.enabled)
            reload()
        } catch {
            presentError(error, message: "切换 root 状态失败")
        }
    }


    @objc private func onAddExclude() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要排除的目录（其自身和所有后代都不会被索引）"
        panel.prompt = "排除"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let canonical = Indexer.canonicalize(path: url.path)
        do {
            _ = try database.addExclude(pattern: canonical)
            // Eagerly purge any rows already indexed under this path so the
            // searcher hides them immediately (keeps UI/indexer in sync).
            _ = try database.deleteFilesMatchingExclude(canonical)
            reload()
        } catch {
            presentError(error, message: "新增 exclude 失败")
        }
    }

    @objc private func onRemoveExclude() {
        let row = excludesTable.selectedRow
        guard row >= 0 && row < excludes.count else { return }
        let e = excludes[row]
        do {
            try database.removeExclude(id: e.id)
            reload()
        } catch {
            presentError(error, message: "移除 exclude 失败")
        }
    }

    private func presentError(_ error: Error, message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

extension IndexingPane: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return tableView === rootsTable ? roots.count : excludes.count
    }
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let label: String
        if tableView === rootsTable {
            let r = roots[row]
            // E4: replace raw enabled flag with a computed health badge so
            // the user can tell paused vs offline vs unavailable apart.
            let health = database.computeRootHealth(
                for: r,
                currentlyIndexingPath: rebuildCoordinator.currentlyIndexingPath
            )
            label = "\(health.uiLabel)  \(r.path)"
        } else {
            label = "🚫 " + excludes[row].pattern
        }
        let text = NSTextField(labelWithString: label)
        text.lineBreakMode = .byTruncatingMiddle
        text.usesSingleLineMode = true
        return text
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === rootsTable else { return [] }
        let urls = draggedDirectoryURLs(from: info)
        return urls.isEmpty ? [] : .copy
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === rootsTable else { return false }
        let urls = draggedDirectoryURLs(from: info)
        guard !urls.isEmpty else { return false }
        var addedPaths: [String] = []
        for url in urls {
            let canonical = Indexer.canonicalize(path: url.path)
            do {
                _ = try database.registerRoot(path: canonical)
                addedPaths.append(canonical)
            } catch {
                NSLog("SwiftSeek: drag-add root failed for \(url.path): \(error)")
            }
        }
        if !addedPaths.isEmpty {
            reload()
            if let wc = view.window?.windowController as? SettingsWindowController {
                wc.refreshBanner()
            }
            // E4 round 2: queue every newly-added root for auto-index,
            // not just the last one.
            for p in addedPaths {
                autoIndexAfterAdd(path: p)
            }
        }
        return !addedPaths.isEmpty
    }

    private func draggedDirectoryURLs(from info: NSDraggingInfo) -> [URL] {
        let pb = info.draggingPasteboard
        let urls = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}

// MARK: - 维护 Pane

private final class MaintenancePane: NSViewController {
    private let database: Database
    private let rebuildCoordinator: RebuildCoordinator

    private let rebuildButton = NSButton(title: "重建索引", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    // G1: DB footprint stats block.
    private let statsTitle = NSTextField(labelWithString: "DB 体积")
    private let statsLabel = NSTextField(wrappingLabelWithString: "")
    private let statsRefreshBtn = NSButton(title: "刷新", target: nil, action: nil)
    private let checkpointBtn = NSButton(title: "WAL checkpoint", target: nil, action: nil)
    private let optimizeBtn   = NSButton(title: "Optimize", target: nil, action: nil)
    private let vacuumBtn     = NSButton(title: "VACUUM…", target: nil, action: nil)
    private let maintStatus   = NSTextField(wrappingLabelWithString: "")

    init(database: Database, rebuildCoordinator: RebuildCoordinator) {
        self.database = database
        self.rebuildCoordinator = rebuildCoordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 560))

        let title = NSTextField(labelWithString: "维护")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(wrappingLabelWithString: "重建会清空 `files` 表下属于所有 enabled roots 的行，按当前排除目录与隐藏文件开关重新全量索引。过程中可以继续使用搜索窗口（结果会逐步刷新）。")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false

        rebuildButton.bezelStyle = .rounded
        rebuildButton.target = self
        rebuildButton.action = #selector(onRebuild)
        rebuildButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false

        // G1 stats block
        statsTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        statsTitle.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.stringValue = "—"
        statsRefreshBtn.bezelStyle = .rounded
        statsRefreshBtn.controlSize = .small
        statsRefreshBtn.target = self
        statsRefreshBtn.action = #selector(onRefreshStats)
        statsRefreshBtn.translatesAutoresizingMaskIntoConstraints = false
        checkpointBtn.bezelStyle = .rounded
        checkpointBtn.controlSize = .small
        checkpointBtn.target = self
        checkpointBtn.action = #selector(onCheckpoint)
        checkpointBtn.translatesAutoresizingMaskIntoConstraints = false
        optimizeBtn.bezelStyle = .rounded
        optimizeBtn.controlSize = .small
        optimizeBtn.target = self
        optimizeBtn.action = #selector(onOptimize)
        optimizeBtn.translatesAutoresizingMaskIntoConstraints = false
        vacuumBtn.bezelStyle = .rounded
        vacuumBtn.controlSize = .small
        vacuumBtn.target = self
        vacuumBtn.action = #selector(onVacuum)
        vacuumBtn.translatesAutoresizingMaskIntoConstraints = false
        maintStatus.font = NSFont.systemFont(ofSize: 11)
        maintStatus.textColor = .secondaryLabelColor
        maintStatus.translatesAutoresizingMaskIntoConstraints = false

        let maintRow = NSStackView(views: [statsRefreshBtn, checkpointBtn, optimizeBtn, vacuumBtn])
        maintRow.orientation = .horizontal
        maintRow.spacing = 8
        maintRow.translatesAutoresizingMaskIntoConstraints = false

        [title, note, rebuildButton, progressIndicator, statusLabel,
         statsTitle, statsLabel, maintRow, maintStatus].forEach { root.addSubview($0) }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            note.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            note.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            rebuildButton.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 20),
            rebuildButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            progressIndicator.leadingAnchor.constraint(equalTo: rebuildButton.trailingAnchor, constant: 16),
            progressIndicator.centerYAnchor.constraint(equalTo: rebuildButton.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 200),

            statusLabel.topAnchor.constraint(equalTo: rebuildButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            // stats block below the rebuild area
            statsTitle.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 28),
            statsTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            statsLabel.topAnchor.constraint(equalTo: statsTitle.bottomAnchor, constant: 6),
            statsLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            statsLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            maintRow.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 10),
            maintRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            maintStatus.topAnchor.constraint(equalTo: maintRow.bottomAnchor, constant: 8),
            maintStatus.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            maintStatus.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            maintStatus.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reflectLastResult()
        reflectRunning()
        refreshStatsLabel()
    }

    // MARK: - G1 stats + maintenance

    @objc private func onRefreshStats() { refreshStatsLabel() }

    private func refreshStatsLabel() {
        let s = database.computeStats()
        var lines: [String] = []
        lines.append("main : \(DatabaseStats.humanBytes(s.mainFileBytes))   wal : \(DatabaseStats.humanBytes(s.walFileBytes))   shm : \(DatabaseStats.humanBytes(s.shmFileBytes))")
        lines.append("pages: count=\(DatabaseStats.humanCount(s.pageCount)) size=\(DatabaseStats.humanBytes(s.pageSize))")
        lines.append("files=\(DatabaseStats.humanCount(s.filesRowCount))   grams=\(DatabaseStats.humanCount(s.fileGramsRowCount))   bigrams=\(DatabaseStats.humanCount(s.fileBigramsRowCount))")
        lines.append("avg grams/file=\(DatabaseStats.humanAvg(s.avgGramsPerFile))   avg bigrams/file=\(DatabaseStats.humanAvg(s.avgBigramsPerFile))")
        if let per = s.perTable, !per.isEmpty {
            lines.append("per-table:")
            for row in per.prefix(6) {
                lines.append("  \(row.name): \(DatabaseStats.humanBytes(row.approxBytes))  pages=\(DatabaseStats.humanCount(row.pageCount))")
            }
            if per.count > 6 { lines.append("  … (+\(per.count - 6) more)") }
        }
        statsLabel.stringValue = lines.joined(separator: "\n")
    }

    @objc private func onCheckpoint() {
        runMaintenanceOffMain(.checkpoint, label: "WAL checkpoint")
    }

    @objc private func onOptimize() {
        runMaintenanceOffMain(.optimize, label: "Optimize")
    }

    @objc private func onVacuum() {
        // G1 requires an explicit confirmation banner before VACUUM.
        let s = database.computeStats()
        let alert = NSAlert()
        alert.messageText = "确认执行 VACUUM？"
        alert.informativeText = """
        这是耗时操作，可能花几分钟到几十分钟（取决于库大小）。

        开始前请确认：
          • 已退出其他正在使用该 DB 的 SwiftSeek GUI / CLI
          • 磁盘剩余空间至少 \(DatabaseStats.humanBytes(s.mainFileBytes))（VACUUM 需要先写一份完整重排副本再替换原文件）
          • 期间 App 主界面会短暂不响应搜索（维护在后台线程，但 DB 锁住）

        VACUUM 只能临时压实当前库，不能根治 full-path gram 索引膨胀问题。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "开始 VACUUM")
        if alert.runModal() == .alertSecondButtonReturn {
            runMaintenanceOffMain(.vacuum, label: "VACUUM")
        }
    }

    private func runMaintenanceOffMain(_ kind: MaintenanceKind, label: String) {
        maintStatus.stringValue = "\(label) 中…"
        [statsRefreshBtn, checkpointBtn, optimizeBtn, vacuumBtn].forEach { $0.isEnabled = false }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.database.runMaintenance(kind)
            DispatchQueue.main.async {
                [self.statsRefreshBtn, self.checkpointBtn, self.optimizeBtn, self.vacuumBtn].forEach { $0.isEnabled = true }
                if let err = result.error {
                    self.maintStatus.stringValue = "\(label) 失败（\(String(format: "%.2fs", result.durationSeconds))）：\(err)"
                } else {
                    self.maintStatus.stringValue = "\(label) 完成，用时 \(String(format: "%.2fs", result.durationSeconds))"
                }
                self.refreshStatsLabel()
            }
        }
    }

    private func reflectLastResult() {
        let at: String
        let result: String
        let stats: String
        do {
            at = (try database.getSetting(SettingsKey.lastRebuildAt)) ?? "—"
            result = (try database.getSetting(SettingsKey.lastRebuildResult)) ?? "—"
            stats = (try database.getSetting(SettingsKey.lastRebuildStats)) ?? "—"
        } catch {
            NSLog("SwiftSeek: MaintenancePane read last_rebuild_* failed: \(error)")
            statusLabel.stringValue = "读取上次重建信息失败：\(error)"
            return
        }
        statusLabel.stringValue = "上次重建：\(at) · \(result)\n\(stats)"
    }

    private func reflectRunning() {
        let running = rebuildCoordinator.isRebuilding
        rebuildButton.isEnabled = !running
        if running {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    @objc private func onRebuild() {
        rebuildButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "重建中…"
        let ok = rebuildCoordinator.rebuild(
            onProgress: { [weak self] p in
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = "重建中 · root \(p.rootIndex)/\(p.rootCount) · scanned=\(p.indexProgress.scanned)"
                }
            },
            onFinish: { [weak self] summary in
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(nil)
                    self?.rebuildButton.isEnabled = true
                    self?.reflectLastResult()
                }
            }
        )
        if !ok {
            progressIndicator.stopAnimation(nil)
            rebuildButton.isEnabled = true
            statusLabel.stringValue = "已有重建在进行中，忽略此次触发。"
        }
    }
}

// MARK: - 关于 / Diagnostics Pane

private final class AboutPane: NSViewController {
    private let database: Database
    private let titleLabel = NSTextField(labelWithString: "SwiftSeek")
    private let versionLabel = NSTextField(labelWithString: "v1 开发中")
    private let diagnosticsLabel = NSTextField(wrappingLabelWithString: "")
    private let refreshButton = NSButton(title: "刷新诊断", target: nil, action: nil)

    init(database: Database) {
        self.database = database
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))

        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        diagnosticsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.target = self
        refreshButton.action = #selector(onRefresh)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, versionLabel, diagnosticsLabel, refreshButton].forEach { root.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            versionLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),

            diagnosticsLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 20),
            diagnosticsLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            diagnosticsLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            refreshButton.topAnchor.constraint(equalTo: diagnosticsLabel.bottomAnchor, constant: 16),
            refreshButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    @objc private func onRefresh() { reload() }

    private func reload() {
        diagnosticsLabel.stringValue = buildDiagnostics()
    }

    private func buildDiagnostics() -> String {
        let dbPath = database.url.path
        let schema = database.schemaVersion
        // Each query catches+logs independently so one failing sub-query does
        // not blank the whole diagnostics panel; user still sees the rest.
        var errors: [String] = []
        func safe<T>(_ label: String, default defaultValue: T, _ fn: () throws -> T) -> T {
            do { return try fn() } catch {
                NSLog("SwiftSeek: AboutPane \(label) failed: \(error)")
                errors.append("\(label): \(error)")
                return defaultValue
            }
        }
        let rootsAll = safe("listRoots", default: []) { try database.listRoots() }
        let rootsEnabled = rootsAll.filter { $0.enabled }.count
        let excludesCount = safe("listExcludes", default: 0) { try database.listExcludes().count }
        let filesCount = safe("countRows(files)", default: Int64(-1)) { try database.countRows(in: "files") }
        let hidden = safe("getHiddenFilesEnabled", default: false) { try database.getHiddenFilesEnabled() }
        let lastAt = safe("getSetting(lastRebuildAt)", default: "—") { (try database.getSetting(SettingsKey.lastRebuildAt)) ?? "—" }
        let lastResult = safe("getSetting(lastRebuildResult)", default: "—") { (try database.getSetting(SettingsKey.lastRebuildResult)) ?? "—" }
        let lastStats = safe("getSetting(lastRebuildStats)", default: "—") { (try database.getSetting(SettingsKey.lastRebuildStats)) ?? "—" }
        var out = """
数据库：\(dbPath)
schema 版本：\(schema)
roots：总 \(rootsAll.count)，启用 \(rootsEnabled)
excludes：\(excludesCount)
files 行数：\(filesCount)
隐藏文件纳入索引：\(hidden ? "是" : "否")
上次重建时间：\(lastAt)
上次重建结果：\(lastResult)
上次重建摘要：\(lastStats)
"""
        if !errors.isEmpty {
            out += "\n\n诊断读取错误：\n" + errors.joined(separator: "\n")
        }
        return out
    }
}
