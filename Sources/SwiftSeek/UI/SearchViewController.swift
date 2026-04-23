import AppKit
import Foundation
import Quartz
import SwiftSeekCore

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

    init(database: Database) {
        self.database = database
        self.engine = SearchEngine(database: database)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("unused") }

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

        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.style = .fullWidth
        tableView.target = self
        tableView.doubleAction = #selector(onRowDoubleClick(_:))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = buildRowContextMenu()
        tableView.setDraggingSourceOperationMask([.copy, .link], forLocal: false)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        col.title = ""
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
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

        let stack = NSStackView(views: [openBtn, revealBtn, copyBtn, previewBtn, NSView(), statusLabel])
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

    private func buildRowContextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "打开", action: #selector(openSelected), keyEquivalent: "")
        m.addItem(withTitle: "在 Finder 中显示", action: #selector(revealSelected), keyEquivalent: "")
        m.addItem(withTitle: "复制路径", action: #selector(copyPathSelected), keyEquivalent: "")
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "移到废纸篓", action: #selector(trashSelected), keyEquivalent: "")
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
        let limit = 20
        let hits: [SearchResult]
        do {
            hits = try engine.search(raw, options: .init(limit: limit, candidateMultiplier: 4))
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.queryGeneration == generation else { return }
                self.statusLabel.stringValue = "查询失败：\(error)"
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
            self.results = hits
            self.currentQuery = raw
            self.lastQueryLimit = limit
            self.selection.setResultCount(hits.count)
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
            emptyStateLabel.stringValue = "未找到匹配 “\(trimmed)”"
        }
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
            ResultActionRunner.perform(.open, target: target)
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
            showToast("✓ 已复制")
        }
    }

    @objc func trashSelected() {
        guard let target = selectedTarget() else { return }
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
        let hit = results[row]

        let id = NSUserInterfaceItemIdentifier("ResultCell")
        var cell = tableView.makeView(withIdentifier: id, owner: nil) as? ResultCell
        if cell == nil {
            cell = ResultCell()
            cell!.identifier = id
        }
        cell!.configure(hit: hit, query: SearchEngine.normalize(currentQuery))
        return cell
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

// MARK: - Reusable result cell with match highlighting + metadata

private final class ResultCell: NSView {
    private let iconView = NSImageView()
    private let primaryLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        primaryLabel.usesSingleLineMode = true
        primaryLabel.lineBreakMode = .byTruncatingMiddle
        primaryLabel.allowsDefaultTighteningForTruncation = true
        primaryLabel.maximumNumberOfLines = 1
        primaryLabel.translatesAutoresizingMaskIntoConstraints = false
        primaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metaLabel.usesSingleLineMode = true
        metaLabel.font = NSFont.systemFont(ofSize: 10)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.alignment = .right
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.setContentHuggingPriority(.required, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [iconView, primaryLabel, metaLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("unused") }

    func configure(hit: SearchResult, query: String) {
        let name = hit.name
        let path = hit.path
        let attr = NSMutableAttributedString()
        let prefix = hit.isDir ? "📁 " : "📄 "

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
        let pathAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        attr.append(NSAttributedString(string: prefix, attributes: nameAttrs))

        let nameStart = attr.length
        attr.append(NSAttributedString(string: name, attributes: nameAttrs))
        ResultCell.highlight(attr: attr, segment: name, start: nameStart, query: query)

        attr.append(NSAttributedString(string: "   ", attributes: nameAttrs))

        let pathStart = attr.length
        attr.append(NSAttributedString(string: path, attributes: pathAttrs))
        ResultCell.highlight(attr: attr, segment: path, start: pathStart, query: query)

        primaryLabel.attributedStringValue = attr

        iconView.image = hit.isDir
            ? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            : NSImage(systemSymbolName: "doc", accessibilityDescription: nil)

        metaLabel.stringValue = Self.metaString(for: hit)
    }

    private static func highlight(attr: NSMutableAttributedString,
                                  segment: String,
                                  start: Int,
                                  query: String) {
        guard !query.isEmpty else { return }
        let lower = segment.lowercased()
        var searchFrom = lower.startIndex
        while searchFrom < lower.endIndex,
              let range = lower.range(of: query, options: [], range: searchFrom..<lower.endIndex) {
            let nsLoc = start + lower.distance(from: lower.startIndex, to: range.lowerBound)
            let nsLen = lower.distance(from: range.lowerBound, to: range.upperBound)
            attr.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ], range: NSRange(location: nsLoc, length: nsLen))
            searchFrom = range.upperBound
        }
    }

    private static func metaString(for hit: SearchResult) -> String {
        var parts: [String] = []
        if hit.mtime > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(hit.mtime))
            parts.append(dateFormatter.localizedString(for: date, relativeTo: Date()))
        }
        if !hit.isDir, hit.size > 0 {
            parts.append(sizeFormatter.string(fromByteCount: hit.size))
        }
        return parts.joined(separator: " · ")
    }
}
