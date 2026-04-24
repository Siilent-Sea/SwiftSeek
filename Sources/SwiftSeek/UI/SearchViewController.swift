import AppKit
import Foundation
import Quartz
import SwiftSeekCore
import UniformTypeIdentifiers

/// NSViewController that owns the search input, the results table, and the
/// action bar. All side effects (open/reveal/copy) go through
/// `ResultActionRunner`. Keyboard state is in `SwiftSeekCore.KeyboardSelection`
/// so it can be unit-tested in the smoke runner.
final class SearchViewController: NSViewController, NSTextFieldDelegate,
                                  NSTableViewDataSource, NSTableViewDelegate,
                                  QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let database: Database
    private let engine: SearchEngine
    private var results: [SearchResult] = []
    private var currentQuery: String = ""
    private var lastQueryLimit: Int = 20
    private var selection = KeyboardSelection()
    private var debounceTimer: DispatchSourceTimer?
    private let debounceInterval: DispatchTimeInterval = .milliseconds(60)
    private let searchQueue = DispatchQueue(label: "com.local.swiftseek.search", qos: .userInitiated)
    private var queryGeneration: Int = 0
    private var toastTimer: DispatchSourceTimer?

    private let inputField = NSTextField()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "")

    // E2: sort state. Default to the native ranking order returned by
    // SearchEngine.search. User clicking a column header cycles through
    // ascending / descending on that key; clicking the "score" column
    // (or the Reset action) returns to scoreDescending.
    // F3: sort order is persisted via Database.{get,set}ResultSortOrder,
    // and per-column widths are persisted on resize.
    private var sortOrder: SearchSortOrder = .scoreDescending
    private var rawResults: [SearchResult] = [] // unsorted from engine
    private static let col_name = NSUserInterfaceItemIdentifier("name")
    private static let col_path = NSUserInterfaceItemIdentifier("path")
    private static let col_mtime = NSUserInterfaceItemIdentifier("mtime")
    private static let col_size = NSUserInterfaceItemIdentifier("size")
    // H2 result columns
    private static let col_openCount = NSUserInterfaceItemIdentifier("openCount")
    private static let col_lastOpened = NSUserInterfaceItemIdentifier("lastOpenedAt")

    /// F3: observer token for NSTableViewColumnDidResize so we can drop
    /// it in deinit without leaking.
    private var columnResizeObserver: NSObjectProtocol?

    init(database: Database) {
        self.database = database
        self.engine = SearchEngine(database: database)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    deinit {
        if let token = columnResizeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 440))
        root.wantsLayer = true

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "搜索文件名或路径…"
        inputField.font = NSFont.systemFont(ofSize: 18)
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.isBordered = true
        inputField.isEditable = true
        inputField.isSelectable = true
        inputField.isAutomaticTextCompletionEnabled = false
        root.addSubview(inputField)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        // E2 introduced 4-column layout + click-to-sort. F3 round 2 tightens
        // it to a real "file-searcher" density:
        //   rowHeight 22 → 18  (one more visible row per ~80px vs E2)
        //   intercell vertical spacing 2 → 1 (kills dead pixels between rows)
        //   horizontal spacing stays 8 so columns don't visually touch
        //   alternating row shading stays on for left-to-right tracking
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 18
        tableView.intercellSpacing = NSSize(width: 8, height: 1)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = []
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.style = .fullWidth
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        tableView.allowsColumnSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.target = self
        tableView.doubleAction = #selector(onRowDoubleClick(_:))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = buildRowContextMenu()
        tableView.setDraggingSourceOperationMask([.copy, .link], forLocal: false)

        // F3: fall back to programmed defaults when no persisted width exists.
        addColumn(id: Self.col_name,   title: "名称", minWidth: 180,
                  width: persistedWidth(for: SettingsKey.resultColumnWidthName) ?? 260,
                  sortKey: "name")
        addColumn(id: Self.col_path,   title: "路径", minWidth: 180,
                  width: persistedWidth(for: SettingsKey.resultColumnWidthPath) ?? 320,
                  sortKey: "path")
        addColumn(id: Self.col_mtime,  title: "修改时间", minWidth: 100,
                  width: persistedWidth(for: SettingsKey.resultColumnWidthMtime) ?? 120,
                  sortKey: "mtime")
        addColumn(id: Self.col_size,   title: "大小", minWidth: 70,
                  width: persistedWidth(for: SettingsKey.resultColumnWidthSize) ?? 80,
                  sortKey: "size")
        // H2: Run Count / 最近打开. Prototype descriptor follows
        // AppKit default (ascending=true), same as the other columns.
        // Users can click the header twice for descending — kept
        // symmetric with name/path/mtime/size so there's no special
        // per-column surprise. Persisted via the same F3 sort keys,
        // mapped through sortDescriptorsDidChange.
        addColumn(id: Self.col_openCount, title: "打开次数", minWidth: 60,
                  width: persistedWidth(for: SettingsKey.resultColumnWidthOpenCount) ?? 80,
                  sortKey: "openCount",
                  headerToolTip: "通过 SwiftSeek 成功打开该文件的次数（Run Count）。不包含 Reveal in Finder / Copy Path，不代表 macOS 全局启动次数。")
        addColumn(id: Self.col_lastOpened, title: "最近打开", minWidth: 90,
                  width: persistedWidth(for: SettingsKey.resultColumnWidthLastOpened) ?? 120,
                  sortKey: "lastOpenedAt",
                  headerToolTip: "最近一次通过 SwiftSeek 成功打开该文件的时间。仅 SwiftSeek 内部 .open 历史，不读取系统最近项目。")

        // J2: give the header a right-click menu so users can
        // recover from a persisted column-width state that has
        // cropped "打开次数" / "最近打开" off-screen. Reset target
        // is this controller; live-refresh the widths after DB
        // reset without requiring a restart.
        if let header = tableView.headerView {
            header.menu = buildHeaderContextMenu()
        }

        // F3: listen for resize notifications on this specific table view.
        // The notification payload userInfo has `NSTableColumn` so we can
        // match it back to one of our column identifiers.
        columnResizeObserver = NotificationCenter.default.addObserver(
            forName: NSTableView.columnDidResizeNotification,
            object: tableView,
            queue: .main
        ) { [weak self] note in
            self?.persistColumnWidthIfNeeded(from: note)
        }

        // F3: restore persisted sort order so the window comes back the
        // way the user left it. We set both the AppKit sortDescriptor
        // (drives the header chevron) and our internal sortOrder so the
        // next results reflow lands in the right order.
        let restored: SearchSortOrder
        do {
            restored = try database.getResultSortOrder()
        } catch {
            NSLog("SwiftSeek: SearchViewController getResultSortOrder failed: \(error)")
            restored = .scoreDescending
        }
        sortOrder = restored
        if restored.key != .score {
            let desc = NSSortDescriptor(key: restored.key.rawValue,
                                        ascending: restored.ascending)
            tableView.sortDescriptors = [desc]
        }

        scroll.documentView = tableView
        root.addSubview(scroll)

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.font = NSFont.systemFont(ofSize: 13)
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.isHidden = false
        root.addSubview(emptyStateLabel)

        let openBtn = makeActionButton(title: "打开", keyEquivalent: "\r",
                                       keyModifierMask: [], action: #selector(openSelected))
        let revealBtn = makeActionButton(title: "在 Finder 中显示",
                                         keyEquivalent: "\r",
                                         keyModifierMask: [.command],
                                         action: #selector(revealSelected))
        let copyBtn = makeActionButton(title: "复制路径",
                                       keyEquivalent: "c",
                                       keyModifierMask: [.command, .shift],
                                       action: #selector(copyPathSelected))
        let previewBtn = makeActionButton(title: "预览",
                                          keyEquivalent: "y",
                                          keyModifierMask: [.command],
                                          action: #selector(togglePreviewPanel))

        // J4: recent queries / saved filters dropdown.
        let historyBtn = NSButton(title: "最近/收藏",
                                  target: self,
                                  action: #selector(showHistoryMenu(_:)))
        historyBtn.bezelStyle = .rounded
        historyBtn.toolTip = "最近查询、已保存的过滤器；保存当前查询；清空历史"
        let stack = NSStackView(views: [openBtn, revealBtn, copyBtn, previewBtn, historyBtn, NSView(), statusLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fill
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        root.addSubview(stack)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.stringValue = "↑↓ 移动 · ⏎ 打开 · ⌘⏎ Reveal · ⌘⇧C 复制 · ⌘Y 预览 · ESC 关闭"
        root.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            inputField.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            inputField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            inputField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            inputField.heightAnchor.constraint(equalToConstant: 32),

            scroll.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -12),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -24),

            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -8),
            stack.heightAnchor.constraint(equalToConstant: 28),

            hintLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            hintLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        self.view = root
        refreshEmptyState()
    }

    private func makeActionButton(title: String,
                                  keyEquivalent: String,
                                  keyModifierMask: NSEvent.ModifierFlags,
                                  action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.keyEquivalent = keyEquivalent
        b.keyEquivalentModifierMask = keyModifierMask
        return b
    }

    private func addColumn(id: NSUserInterfaceItemIdentifier,
                           title: String,
                           minWidth: CGFloat,
                           width: CGFloat,
                           sortKey: String,
                           headerToolTip: String? = nil) {
        let col = NSTableColumn(identifier: id)
        col.title = title
        col.minWidth = minWidth
        col.width = width
        col.resizingMask = .userResizingMask
        col.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
        if let tt = headerToolTip {
            col.headerToolTip = tt
        }
        tableView.addTableColumn(col)
    }

    /// J2: default widths for each column. Kept as a single
    /// source of truth so the "重置列宽" header menu can re-apply
    /// them live without re-instantiating the table view.
    private static let defaultColumnWidths: [(NSUserInterfaceItemIdentifier, CGFloat)] = [
        (col_name, 260),
        (col_path, 320),
        (col_mtime, 120),
        (col_size, 80),
        (col_openCount, 80),
        (col_lastOpened, 120),
    ]

    private func buildHeaderContextMenu() -> NSMenu {
        let m = NSMenu()
        let item = NSMenuItem(title: "重置列宽",
                              action: #selector(resetColumnWidths),
                              keyEquivalent: "")
        item.target = self
        item.toolTip = "清除持久化的结果表列宽，恢复程序默认值。用于恢复“打开次数 / 最近打开”等被历史宽度压掉的列。"
        m.addItem(item)
        return m
    }

    // MARK: - J4 recent / saved filters menu

    /// Show NSMenu anchored at the button with recent queries +
    /// saved filters + management entries. Built on demand so entries
    /// always reflect the current DB state.
    @objc private func showHistoryMenu(_ sender: Any?) {
        let menu = NSMenu()
        // Recent queries
        let recents = (try? database.listRecentQueries(limit: 10)) ?? []
        if recents.isEmpty {
            let empty = NSMenuItem(title: "（暂无最近查询）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for r in recents {
                // Truncate very long queries so the menu stays usable.
                let display = r.query.count > 50
                    ? String(r.query.prefix(48)) + "…"
                    : r.query
                let item = NSMenuItem(title: "🕒 \(display)",
                                      action: #selector(applyQueryMenuItem(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = r.query
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())
        // Saved filters
        let saved = (try? database.listSavedFilters()) ?? []
        if saved.isEmpty {
            let empty = NSMenuItem(title: "（暂无已保存过滤器）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for f in saved {
                let item = NSMenuItem(title: "★ \(f.name)",
                                      action: #selector(applyQueryMenuItem(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = f.query
                item.toolTip = f.query
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())
        // Management entries
        let saveItem = NSMenuItem(title: "保存当前查询…",
                                  action: #selector(saveCurrentAsFilter),
                                  keyEquivalent: "")
        saveItem.target = self
        saveItem.isEnabled = !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        menu.addItem(saveItem)
        let clearItem = NSMenuItem(title: "清空搜索历史…",
                                   action: #selector(clearSearchHistory),
                                   keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !recents.isEmpty
        menu.addItem(clearItem)

        // Pop up below the button itself.
        if let btn = sender as? NSButton {
            let p = NSPoint(x: 0, y: btn.bounds.maxY + 4)
            menu.popUp(positioning: nil, at: p, in: btn)
        } else {
            // Fallback — pop at mouse location.
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func applyQueryMenuItem(_ sender: NSMenuItem) {
        guard let q = sender.representedObject as? String else { return }
        inputField.stringValue = q
        currentQuery = q
        performSearchImmediate()
    }

    @objc private func saveCurrentAsFilter() {
        let q = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return }
        let alert = NSAlert()
        alert.messageText = "保存当前查询为过滤器"
        alert.informativeText = "为以下查询取一个易记的名字（仅保存在本地，不同步、不遥测）：\n\n\(q)"
        alert.alertStyle = .informational
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.placeholderString = "例：周报 / 项目 X / 本周未读"
        alert.accessoryView = nameField
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                showToast("未保存：名字不能为空")
                return
            }
            do {
                let ok = try database.saveFilter(name: name, query: q)
                if ok { showToast("✓ 已保存 “\(name)”") }
                else { showToast("未保存：名字或查询为空") }
            } catch {
                showToast("保存失败：\(error.localizedDescription)")
            }
        }
    }

    @objc private func clearSearchHistory() {
        let alert = NSAlert()
        alert.messageText = "清空搜索历史？"
        alert.informativeText = """
        将删除全部 `query_history` 记录。

        此操作不可撤销。已保存的过滤器不受影响。

        提示：不想今后记录搜索历史，可去设置 → 维护 tab 的"搜索历史"开关关闭记录；清空不改开关。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            let removed = try database.clearQueryHistory()
            showToast("✓ 已清空 \(removed) 条搜索历史")
        } catch {
            showToast("清空失败：\(error.localizedDescription)")
        }
    }

    /// Trigger a search for the current query. Reuses the same
    /// debounced `scheduleQuery` path the type-to-search field uses,
    /// so the semantics (including result ordering + selection
    /// preservation) match clicking through.
    private func performSearchImmediate() {
        scheduleQuery(currentQuery)
    }

    @objc private func resetColumnWidths() {
        // Clear persisted widths in DB.
        do {
            _ = try database.resetResultColumnWidths()
        } catch {
            NSLog("SwiftSeek: resetResultColumnWidths failed: \(error)")
            return
        }
        // Apply defaults to the live NSTableColumn instances — no
        // restart required. Look up each column by identifier so
        // the order in defaultColumnWidths doesn't need to match
        // the visible column order.
        for (id, width) in Self.defaultColumnWidths {
            if let col = tableView.tableColumn(withIdentifier: id) {
                col.width = width
            }
        }
        // If the panel itself is too narrow to show everything at
        // defaults, widen it too so the reset is actually visible.
        let defaultTotal = Self.defaultColumnWidths.reduce(into: 0) { $0 += $1.1 }
        if let win = view.window, win.frame.width < defaultTotal + 40 {
            var f = win.frame
            let newWidth = defaultTotal + 40
            f.origin.x -= (newWidth - f.width) / 2 // keep centered
            f.size.width = newWidth
            win.setFrame(f, display: true, animate: true)
        }
        showToast("✓ 已重置列宽")
    }

    /// F3: pull a persisted column width from DB, nil on miss / malformed.
    private func persistedWidth(for key: String) -> CGFloat? {
        do {
            if let d = try database.getResultColumnWidth(key: key) { return CGFloat(d) }
        } catch {
            NSLog("SwiftSeek: getResultColumnWidth(\(key)) failed: \(error)")
        }
        return nil
    }

    /// F3: map a resized column back to its settings key and save.
    private func persistColumnWidthIfNeeded(from note: Notification) {
        guard let col = note.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        let key: String?
        switch col.identifier {
        case Self.col_name:       key = SettingsKey.resultColumnWidthName
        case Self.col_path:       key = SettingsKey.resultColumnWidthPath
        case Self.col_mtime:      key = SettingsKey.resultColumnWidthMtime
        case Self.col_size:       key = SettingsKey.resultColumnWidthSize
        case Self.col_openCount:  key = SettingsKey.resultColumnWidthOpenCount
        case Self.col_lastOpened: key = SettingsKey.resultColumnWidthLastOpened
        default:                  key = nil
        }
        guard let k = key else { return }
        do {
            try database.setResultColumnWidth(key: k, width: Double(col.width))
        } catch {
            NSLog("SwiftSeek: setResultColumnWidth(\(k)) failed: \(error)")
        }
    }

    private func buildRowContextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "打开", action: #selector(openSelected), keyEquivalent: "")
        m.addItem(withTitle: "使用其他应用打开…",
                  action: #selector(openWithSelected),
                  keyEquivalent: "")
        m.addItem(withTitle: "在 Finder 中显示",
                  action: #selector(revealSelected),
                  keyEquivalent: "")
        m.addItem(NSMenuItem.separator())
        // J5: three explicit copy actions so users don't have to
        // guess what "复制" will actually paste. Renamed the old
        // "复制路径" to "复制完整路径" for symmetry.
        m.addItem(withTitle: "复制名称",
                  action: #selector(copyNameSelected),
                  keyEquivalent: "")
        m.addItem(withTitle: "复制完整路径",
                  action: #selector(copyPathSelected),
                  keyEquivalent: "")
        m.addItem(withTitle: "复制所在文件夹路径",
                  action: #selector(copyParentFolderSelected),
                  keyEquivalent: "")
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "移到废纸篓",
                  action: #selector(trashSelected),
                  keyEquivalent: "")
        for item in m.items { item.target = self }
        return m
    }

    func focusInput() {
        view.window?.makeFirstResponder(inputField)
    }

    // MARK: - Debounced query

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let tv = obj.userInfo?["NSFieldEditor"] as? NSTextView {
            tv.isContinuousSpellCheckingEnabled = false
            tv.isGrammarCheckingEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        scheduleQuery(inputField.stringValue)
    }

    private func scheduleQuery(_ raw: String) {
        debounceTimer?.cancel()
        queryGeneration &+= 1
        let gen = queryGeneration
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + debounceInterval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.searchQueue.async { self.runQuery(raw, generation: gen) }
        }
        t.resume()
        debounceTimer = t
    }

    private func runQuery(_ raw: String, generation: Int) {
        let start = Date()
        // E1: limit is now user-configurable. Read the persisted value on
        // every query so changes from the Settings window take effect without
        // a restart. Read failures NSLog + fall back to the default.
        let limit: Int
        do {
            limit = try database.getSearchLimit()
        } catch {
            NSLog("SwiftSeek: SearchViewController getSearchLimit failed, using default: \(error)")
            limit = SearchLimitBounds.defaultValue
        }
        let hits: [SearchResult]
        do {
            hits = try engine.search(raw, options: .init(limit: limit, candidateMultiplier: 4))
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.queryGeneration == generation else { return }
                self.statusLabel.stringValue = "查询失败：\(error)"
                self.rawResults = []
                self.results = []
                self.currentQuery = raw
                self.selection.setResultCount(0)
                self.tableView.reloadData()
                self.refreshEmptyState()
            }
            return
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.queryGeneration == generation else { return }
            // E2: keep the raw ranked list around so re-sort can switch back
            // to score order without re-querying the DB.
            self.rawResults = hits
            self.results = SearchEngine.sort(hits, by: self.sortOrder)
            self.currentQuery = raw
            self.lastQueryLimit = limit
            self.selection.setResultCount(self.results.count)
            self.tableView.reloadData()
            if self.selection.currentIndex >= 0 {
                self.tableView.selectRowIndexes(IndexSet(integer: self.selection.currentIndex),
                                               byExtendingSelection: false)
                self.tableView.scrollRowToVisible(self.selection.currentIndex)
            }
            if raw.isEmpty {
                self.statusLabel.stringValue = ""
            } else if hits.count >= limit {
                self.statusLabel.stringValue = "仅显示前 \(limit) 条 · \(ms)ms"
            } else {
                self.statusLabel.stringValue = "\(hits.count) 条 · \(ms)ms"
            }
            self.refreshEmptyState()
        }
    }

    private func refreshEmptyState() {
        if !results.isEmpty {
            emptyStateLabel.isHidden = true
            return
        }
        emptyStateLabel.isHidden = false
        let trimmed = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let rootsCount: Int
            do {
                rootsCount = try database.listRoots().filter { $0.enabled }.count
            } catch {
                NSLog("SwiftSeek: SearchViewController listRoots failed in empty state: \(error)")
                emptyStateLabel.stringValue = "读取索引目录失败：\(error)"
                return
            }
            if rootsCount == 0 {
                emptyStateLabel.stringValue = "还没有配置索引目录。\n打开菜单「SwiftSeek → 设置…」→「索引范围」添加。"
            } else {
                emptyStateLabel.stringValue = "输入关键字开始搜索"
            }
        } else {
            // F4: when a real query returns 0 hits, hint at any degraded
            // root so the user can tell "no match" from "can't match
            // because root is offline / unavailable". This is the search
            // side of pushing RootHealth beyond the settings-page badge.
            var base = "未找到匹配 “\(trimmed)”"
            if let degraded = degradedRootsHint() {
                base += "\n\(degraded)"
            }
            emptyStateLabel.stringValue = base
        }
    }

    /// F4: build a human-readable suffix enumerating roots that are
    /// currently in a "can't return results" state (offline /
    /// unavailable / paused). Returns nil when every root is ready so
    /// the empty state message stays tight in the common case.
    private func degradedRootsHint() -> String? {
        let roots: [RootRow]
        do {
            roots = try database.listRoots()
        } catch {
            NSLog("SwiftSeek: degradedRootsHint listRoots failed: \(error)")
            return nil
        }
        var offline: [String] = []
        var unavailable: [String] = []
        var paused: [String] = []
        for r in roots {
            let h = database.computeRootHealth(for: r)
            switch h {
            case .offline:     offline.append(r.path)
            case .unavailable: unavailable.append(r.path)
            case .paused:      paused.append(r.path)
            default: break
            }
        }
        if offline.isEmpty && unavailable.isEmpty && paused.isEmpty {
            return nil
        }
        var parts: [String] = []
        if !offline.isEmpty {
            parts.append("未挂载：\(offline.joined(separator: "、"))")
        }
        if !unavailable.isEmpty {
            parts.append("不可访问：\(unavailable.joined(separator: "、"))")
        }
        if !paused.isEmpty {
            parts.append("已停用：\(paused.joined(separator: "、"))")
        }
        return "（root 状态 · " + parts.joined(separator: " · ") + "）"
    }

    // MARK: - NSTextFieldDelegate command routing

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            selection.moveDown()
            reflectSelection()
            return true
        case #selector(NSResponder.moveUp(_:)):
            selection.moveUp()
            reflectSelection()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            } else {
                view.window?.orderOut(nil)
            }
            return true
        default:
            return false
        }
    }

    @objc func togglePreviewPanel() {
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    private func reflectSelection() {
        guard selection.currentIndex >= 0 else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: selection.currentIndex),
                                   byExtendingSelection: false)
        tableView.scrollRowToVisible(selection.currentIndex)
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    // MARK: - Action targets

    @objc func openSelected() {
        if let target = selectedTarget() {
            // H1: only bump Run Count after NSWorkspace reports success.
            // A failed `open` (missing handler, broken alias, unreachable
            // volume, etc.) must not increment open_count. recordOpen
            // itself tolerates "path not in index" by returning false +
            // NSLog; we intentionally do not swallow that signal silently.
            let opened = ResultActionRunner.perform(.open, target: target)
            if opened {
                do {
                    _ = try database.recordOpen(path: target.path)
                } catch {
                    NSLog("SwiftSeek: recordOpen failed for \(target.path): \(error)")
                }
                // J4: record the query that led to this action as
                // search history. We deliberately record on
                // user-commit (= .open), not on every keystroke, so
                // the history reflects intent rather than typos.
                // recordQueryHistory itself no-ops on empty string
                // OR when the history toggle is disabled.
                let q = currentQuery
                do {
                    _ = try database.recordQueryHistory(q)
                } catch {
                    NSLog("SwiftSeek: recordQueryHistory failed for `\(q)`: \(error)")
                }
            }
            view.window?.orderOut(nil)
        }
    }

    @objc func revealSelected() {
        if let target = selectedTarget() {
            ResultActionRunner.perform(.revealInFinder, target: target)
        }
    }

    @objc func copyPathSelected() {
        if let target = selectedTarget() {
            ResultActionRunner.perform(.copyPath, target: target)
            showToast("✓ 已复制完整路径")
        }
    }

    /// J5: copy just the file name (last path component). Does NOT
    /// increment Run Count — Copy actions are read-only intent.
    @objc func copyNameSelected() {
        guard let target = selectedTarget() else { return }
        let name = PathHelpers.fileName(of: target.path)
        if name.isEmpty {
            showToast("复制名称失败：路径无可识别的文件名")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(name, forType: .string)
        showToast("✓ 已复制名称")
    }

    /// J5: copy the parent directory path (everything except the
    /// final component). Useful for `cd "$(pbpaste)"` workflows.
    /// Does NOT increment Run Count.
    @objc func copyParentFolderSelected() {
        guard let target = selectedTarget() else { return }
        let parent = PathHelpers.parentFolder(of: target.path)
        if parent.isEmpty {
            showToast("复制文件夹失败：路径无父目录")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(parent, forType: .string)
        showToast("✓ 已复制所在文件夹路径")
    }

    /// J5: present NSOpenPanel for the user to pick an application,
    /// then hand the target to it via NSWorkspace public API. Does
    /// NOT count as Run Count (we only record .open via the default
    /// handler, matching H1's contract).
    @objc func openWithSelected() {
        guard let target = selectedTarget() else { return }
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.message = "选择要用来打开的应用"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let appsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.directoryURL = appsURL
        panel.allowedContentTypes = [.application]
        let fileURL = URL(fileURLWithPath: target.path)
        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([fileURL],
                                withApplicationAt: appURL,
                                configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showToast("打开失败：\(error.localizedDescription)")
                } else {
                    self?.showToast("✓ 已通过 \(appURL.lastPathComponent) 打开")
                }
            }
        }
    }

    @objc func trashSelected() {
        guard let target = selectedTarget() else { return }
        // J5: destructive operation — always confirm first. The
        // NSAlert describes exactly what's about to happen so a
        // stray keyboard shortcut can't accidentally delete the
        // user's currently-selected row.
        let name = PathHelpers.fileName(of: target.path)
        let alert = NSAlert()
        alert.messageText = "移到废纸篓？"
        alert.informativeText = "将把 “\(name)” 移到废纸篓。\n\n完整路径：\n\(target.path)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "移到废纸篓")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let url = URL(fileURLWithPath: target.path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            showToast("✓ 已移到废纸篓")
        } catch {
            showToast("移到废纸篓失败：\(error.localizedDescription)")
        }
    }

    @objc func onRowDoubleClick(_ sender: Any?) {
        openSelected()
    }

    private func selectedTarget() -> ResultTarget? {
        let idx = selection.currentIndex
        guard idx >= 0, idx < results.count else { return nil }
        let hit = results[idx]
        return ResultTarget(path: hit.path, isDirectory: hit.isDir)
    }

    private func showToast(_ text: String) {
        statusLabel.stringValue = text
        toastTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 2.0)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            // Don't overwrite if another status has since taken over.
            if self.statusLabel.stringValue == text {
                self.statusLabel.stringValue = self.defaultStatusText()
            }
        }
        t.resume()
        toastTimer = t
    }

    private func defaultStatusText() -> String {
        let trimmed = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if results.count >= lastQueryLimit {
            return "仅显示前 \(lastQueryLimit) 条"
        }
        return "\(results.count) 条"
    }

    // MARK: - Table data source / delegate

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < results.count, let col = tableColumn else { return nil }
        let hit = results[row]
        let q = SearchEngine.normalize(currentQuery)
        let tokens = SearchEngine.tokenize(currentQuery)
        switch col.identifier {
        case Self.col_name:
            let cell = reuseCell(id: Self.col_name) { NameColumnCell() }
            cell.configure(hit: hit, tokens: tokens)
            return cell
        case Self.col_path:
            let cell = reuseCell(id: Self.col_path) { PathColumnCell() }
            cell.configure(hit: hit, tokens: tokens, query: q)
            return cell
        case Self.col_mtime:
            let cell = reuseCell(id: Self.col_mtime) { PlainColumnCell(alignment: .right) }
            cell.configure(text: MtimeFormatter.relative(hit.mtime))
            return cell
        case Self.col_size:
            let cell = reuseCell(id: Self.col_size) { PlainColumnCell(alignment: .right) }
            cell.configure(text: SizeFormatter.formatted(hit: hit))
            return cell
        case Self.col_openCount:
            let cell = reuseCell(id: Self.col_openCount) { PlainColumnCell(alignment: .right) }
            // "—" for never-opened so the column reads cleanly and
            // matches the "no usage row yet" data model (openCount=0).
            let text = hit.openCount > 0 ? String(hit.openCount) : "—"
            cell.configure(text: text)
            return cell
        case Self.col_lastOpened:
            let cell = reuseCell(id: Self.col_lastOpened) { PlainColumnCell(alignment: .right) }
            // Reuse the relative mtime formatter; 0 -> "—" fallback.
            let text = hit.lastOpenedAt > 0
                ? MtimeFormatter.relative(hit.lastOpenedAt)
                : "—"
            cell.configure(text: text)
            return cell
        default:
            return nil
        }
    }

    private func reuseCell<T: NSView>(id: NSUserInterfaceItemIdentifier,
                                      _ make: () -> T) -> T {
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? T {
            return reused
        }
        let fresh = make()
        fresh.identifier = id
        return fresh
    }

    // E2: respond to header-click sort changes. We map the AppKit sort
    // descriptor back to our pure-Swift SearchSortOrder and re-sort the
    // already-ranked list; no DB round-trip. Empty descriptors (the
    // "no sort" state) fall back to the default score descending order.
    func tableView(_ tableView: NSTableView,
                   sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let newOrder: SearchSortOrder
        if let primary = tableView.sortDescriptors.first, let key = primary.key {
            let mapped: SearchSortKey?
            switch key {
            case "name":         mapped = .name
            case "path":         mapped = .path
            case "mtime":        mapped = .mtime
            case "size":         mapped = .size
            case "openCount":    mapped = .openCount
            case "lastOpenedAt": mapped = .lastOpenedAt
            default:             mapped = nil
            }
            if let m = mapped {
                newOrder = SearchSortOrder(key: m, ascending: primary.ascending)
            } else {
                newOrder = .scoreDescending
            }
        } else {
            newOrder = .scoreDescending
        }
        sortOrder = newOrder
        // F3: persist user's sort choice so the window restores it next launch.
        do {
            try database.setResultSortOrder(newOrder)
        } catch {
            NSLog("SwiftSeek: setResultSortOrder failed: \(error)")
        }
        // Preserve the currently selected result (if any) across re-sort.
        let previouslySelected: SearchResult? = {
            let i = selection.currentIndex
            return (i >= 0 && i < results.count) ? results[i] : nil
        }()
        results = SearchEngine.sort(rawResults, by: newOrder)
        selection.setResultCount(results.count)
        if let prev = previouslySelected,
           let newIdx = results.firstIndex(of: prev) {
            selection.setIndex(newIdx)
        }
        self.tableView.reloadData()
        if selection.currentIndex >= 0 {
            self.tableView.selectRowIndexes(IndexSet(integer: selection.currentIndex),
                                            byExtendingSelection: false)
            self.tableView.scrollRowToVisible(selection.currentIndex)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 { selection.setIndex(row) }
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    // MARK: - Drag out of table

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < results.count else { return nil }
        return NSURL(fileURLWithPath: results[row].path)
    }

    // MARK: - QLPreviewPanel

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.delegate = self
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.delegate = nil
        panel.dataSource = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return selection.currentIndex >= 0 ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let i = selection.currentIndex
        guard i >= 0, i < results.count else { return nil }
        return URL(fileURLWithPath: results[i].path) as NSURL
    }
}

// MARK: - E2 multi-column cells

/// Highlights every case-insensitive occurrence of each token in `segment`
/// with a translucent yellow background. Shared by name + path cells so
/// the highlight behaviour is identical in both columns.
private func highlightTokens(_ attr: NSMutableAttributedString,
                             segment: String,
                             start: Int,
                             tokens: [String]) {
    let lower = segment.lowercased()
    for token in tokens {
        guard !token.isEmpty else { continue }
        var searchFrom = lower.startIndex
        while searchFrom < lower.endIndex,
              let range = lower.range(of: token, options: [], range: searchFrom..<lower.endIndex) {
            let nsLoc = start + lower.distance(from: lower.startIndex, to: range.lowerBound)
            let nsLen = lower.distance(from: range.lowerBound, to: range.upperBound)
            attr.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ], range: NSRange(location: nsLoc, length: nsLen))
            searchFrom = range.upperBound
        }
    }
}

private final class NameColumnCell: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var iconLoadPath: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    func configure(hit: SearchResult, tokens: [String]) {
        // F3: bump the name to .medium weight so it reads as the primary
        // column at a glance; the path column below can stay at regular
        // secondary weight without competing for attention.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let attr = NSMutableAttributedString(string: hit.name, attributes: attrs)
        highlightTokens(attr, segment: hit.name, start: 0, tokens: tokens)
        label.attributedStringValue = attr

        // E2 preserves the E1 UX polish pattern: show a generic SF Symbol
        // immediately, kick off the real Finder icon fetch on a utility
        // queue so scroll + re-sort stay smooth even when results cross
        // onto slow volumes. F3: colour-tint the placeholder so dir vs
        // file is visible even before the real icon loads.
        let placeholder: NSImage?
        if hit.isDir {
            placeholder = NSImage(systemSymbolName: "folder.fill",
                                  accessibilityDescription: nil)
            placeholder?.isTemplate = false
        } else {
            placeholder = NSImage(systemSymbolName: "doc",
                                  accessibilityDescription: nil)
            placeholder?.isTemplate = true
        }
        iconView.image = placeholder
        iconView.contentTintColor = hit.isDir
            ? NSColor.systemBlue.withAlphaComponent(0.9)
            : NSColor.secondaryLabelColor
        iconLoadPath = hit.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let img = NSWorkspace.shared.icon(forFile: hit.path)
            img.size = NSSize(width: 16, height: 16)
            DispatchQueue.main.async {
                guard self?.iconLoadPath == hit.path else { return }
                self?.iconView.image = img
            }
        }
    }
}

private final class PathColumnCell: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    func configure(hit: SearchResult, tokens: [String], query: String) {
        // F3: path de-emphasised (tertiaryLabelColor) so the name column
        // wins the visual hierarchy. Token highlights on the parent dir
        // still draw the eye to where the match occurred.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        // Show the parent directory in the path column; the name column
        // already shows the basename. That avoids redundant content and
        // makes the row easier to scan in dense multi-result views.
        let url = URL(fileURLWithPath: hit.path)
        let parent = url.deletingLastPathComponent().path
        let attr = NSMutableAttributedString(string: parent, attributes: attrs)
        highlightTokens(attr, segment: parent, start: 0, tokens: tokens)
        label.attributedStringValue = attr
        label.toolTip = hit.path
        _ = query // reserved for future full-path highlight mode
    }
}

private final class PlainColumnCell: NSView {
    private let label = NSTextField(labelWithString: "")

    init(alignment: NSTextAlignment = .left) {
        super.init(frame: .zero)
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        label.alignment = alignment
        // F3: use monospaced digits so size and date columns line up
        // vertically even when row values differ in digit count
        // ("1.2 MB" above "12 KB", "3 天前" above "刚刚" etc.). Cell label
        // colour stays on secondaryLabelColor to stay legible but
        // still visually below the primary name column.
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    func configure(text: String) { label.stringValue = text }
}

/// Localized "2 天前" / "刚刚" relative date formatting. Hoisted out of the
/// cell so the formatter is not re-allocated for every row.
private enum MtimeFormatter {
    private static let shared: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    static func relative(_ mtime: Int64) -> String {
        guard mtime > 0 else { return "—" }
        let d = Date(timeIntervalSince1970: TimeInterval(mtime))
        return shared.localizedString(for: d, relativeTo: Date())
    }
}

private enum SizeFormatter {
    private static let shared: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatted(hit: SearchResult) -> String {
        if hit.isDir { return "—" }
        if hit.size <= 0 { return "—" }
        return shared.string(fromByteCount: hit.size)
    }
}
