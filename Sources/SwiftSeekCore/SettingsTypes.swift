import Foundation

/// A row in the `roots` table — an indexed directory and its enabled flag.
/// Disabled roots are retained in the table but skipped by rebuild / incremental
/// walkers; use `Database.removeRoot(id:)` for permanent removal.
public struct RootRow: Equatable, Sendable {
    public let id: Int64
    public let path: String
    public let enabled: Bool

    public init(id: Int64, path: String, enabled: Bool) {
        self.id = id
        self.path = path
        self.enabled = enabled
    }
}

/// A row in the `excludes` table. Pattern is a canonicalised directory path —
/// anything at or under this path is filtered out of first-time indexing,
/// incremental rescans, and (by virtue of not being in `files`) search results.
public struct ExcludeRow: Equatable, Sendable {
    public let id: Int64
    public let pattern: String

    public init(id: Int64, pattern: String) {
        self.id = id
        self.pattern = pattern
    }
}

/// Canonical keys used in the `settings` K/V table. Using typed constants avoids
/// string-key typos scattered across the UI layer.
public enum SettingsKey {
    public static let hiddenFilesEnabled = "hidden_files_enabled"
    public static let lastRebuildAt = "last_rebuild_at"          // ISO8601 string
    public static let lastRebuildResult = "last_rebuild_result"  // "success" / "failed:<msg>"
    public static let lastRebuildStats = "last_rebuild_stats"    // human-readable summary
    public static let searchLimit = "search_limit"               // positive integer, default 100
    public static let hotkeyKeyCode = "hotkey_key_code"          // Carbon virtual key code (UInt32 serialized as string)
    public static let hotkeyModifiers = "hotkey_modifiers"       // Carbon modifier mask (UInt32 serialized as string)
    // F3 result view layout state. Persisting the sort + column widths
    // lets the window come back the way the user left it across
    // restarts — basic "remember my preferences" ergonomics.
    public static let resultSortKey = "result_sort_key"          // SearchSortKey.rawValue (score/name/path/mtime/size/openCount/lastOpenedAt)
    public static let resultSortAscending = "result_sort_asc"    // "1" / "0"
    public static let resultColumnWidthName  = "result_col_width_name"
    public static let resultColumnWidthPath  = "result_col_width_path"
    public static let resultColumnWidthMtime = "result_col_width_mtime"
    public static let resultColumnWidthSize  = "result_col_width_size"
    // H2: Run Count / last-opened result columns. Both optional; if the
    // DB doesn't have the setting we fall back to the programmed default.
    public static let resultColumnWidthOpenCount    = "result_col_width_open_count"
    public static let resultColumnWidthLastOpened   = "result_col_width_last_opened"
    // G3: index mode (compact vs fullpath). New DBs default to compact
    // (set in Database.migrate's v5 branch). v4→v5 upgrades default to
    // fullpath to preserve the pre-existing user capability until they
    // explicitly switch.
    public static let indexMode              = "index_mode"
    // H4: usage history privacy toggle. "1" = record (default), "0" =
    // disabled. While disabled, Database.recordOpen is a no-op that
    // logs via NSLog; no rows are written. Flipping this back to "1"
    // resumes recording from 0; SwiftSeek does not retroactively fill
    // in missed opens.
    public static let usageHistoryEnabled    = "usage_history_enabled"
    // J4: query history privacy toggle. "1" = record (default), "0"
    // = disabled. Same semantics as usageHistoryEnabled — disabling
    // stops NEW writes but does not clear existing rows; use the
    // maintenance tab "清空搜索历史" for removal.
    public static let queryHistoryEnabled    = "query_history_enabled"
    // J6: remember which Settings tab the user had open last so
    // they don't have to re-navigate on each reopen. Integer index
    // into the tab view controller; out-of-range values are
    // silently clamped on read.
    public static let settingsTabIndex       = "settings_tab_index"
    // J6: Launch-at-Login UI mirror. The canonical state lives in
    // SMAppService (macOS), but we cache whether the user OPTED IN
    // so we can show the checkbox reflecting intent even if
    // SMAppService reports `.notRegistered` between launches on
    // unsigned dev builds. "1" = user wants login launch, "0" /
    // missing = no.
    public static let launchAtLoginRequested = "launch_at_login_requested"

    /// L2 (everything-menubar-agent): user-expressed intent for whether
    /// SwiftSeek's Dock icon is visible. Default behaviour is L1
    /// menubar-agent (no Dock); flipping this to "1" makes the next
    /// launch call `NSApp.setActivationPolicy(.regular)` instead of
    /// `.accessory`. We persist intent rather than live activation
    /// policy because runtime `.regular` ↔ `.accessory` transitions on
    /// ad-hoc / unsigned bundles are not reliable across macOS
    /// versions; the setting takes effect on next launch and the UI
    /// is responsible for telling the user that. "1" = show Dock,
    /// "0" / missing = no Dock (L1 default).
    public static let dockIconVisible = "dock_icon_visible"
}

/// G3 index modes defined in `docs/everything_footprint_v5_proposal.md` § 3/4.
public enum IndexMode: String, Equatable, Sendable {
    /// Default for new v5 DBs. Only basename grams/bigrams + per-segment
    /// path index. Smallest disk footprint; plain query won't surface
    /// path-only hits, `path:` does segment-prefix match.
    case compact
    /// Pre-G3 v4 behaviour. Full path substring via `file_grams` +
    /// `file_bigrams`. Users who need "match any substring of path"
    /// opt into this explicitly.
    case fullpath
}

// MARK: - E5 hotkey presets

/// Curated hotkey presets for the Settings UI. Writing a full keycode
/// recorder is a rabbit-hole (IME capture, layout-independence, media
/// keys); a closed list of sane Spotlight-style combos covers 95% of
/// real use without owning a recorder. Values here are Carbon constants
/// so they match what `GlobalHotkey.register` expects verbatim.
public struct HotkeyPreset: Equatable, Sendable {
    public let label: String
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(label: String, keyCode: UInt32, modifiers: UInt32) {
        self.label = label
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum HotkeyPresets {
    // Carbon constants (from <Carbon/HIToolbox/Events.h>); hard-coded here
    // so Core doesn't have to import Carbon.
    private static let optionKey: UInt32  = 1 << 11   // 0x0800
    private static let shiftKey: UInt32   = 1 << 9    // 0x0200
    private static let cmdKey: UInt32     = 1 << 8    // 0x0100
    private static let controlKey: UInt32 = 1 << 12   // 0x1000
    private static let kVK_Space: UInt32  = 49

    public static let all: [HotkeyPreset] = [
        HotkeyPreset(label: "⌥Space（默认）", keyCode: kVK_Space, modifiers: optionKey),
        HotkeyPreset(label: "⌃Space",        keyCode: kVK_Space, modifiers: controlKey),
        HotkeyPreset(label: "⇧⌘Space",       keyCode: kVK_Space, modifiers: shiftKey | cmdKey),
        HotkeyPreset(label: "⌃⌥Space",       keyCode: kVK_Space, modifiers: controlKey | optionKey),
        HotkeyPreset(label: "⌥⌘Space",       keyCode: kVK_Space, modifiers: optionKey | cmdKey),
    ]

    public static let `default`: HotkeyPreset = all[0]

    /// Resolve a keyCode + modifiers pair back to a labeled preset, or
    /// nil if the saved combo is not in the curated list (e.g. a value
    /// from a future version). Callers should fall back to the default
    /// label in that case.
    public static func preset(keyCode: UInt32, modifiers: UInt32) -> HotkeyPreset? {
        return all.first { $0.keyCode == keyCode && $0.modifiers == modifiers }
    }
}

/// E1 search result limit bounds. A hard cap keeps pathological settings
/// (e.g. 100_000) from swamping the GUI table reload; the floor keeps at
/// least one screenful of results available.
public enum SearchLimitBounds {
    public static let minimum = 20
    public static let maximum = 1000
    public static let defaultValue = 100
}

/// Typed wrapper for the hidden-files toggle. Stored as "1" / "0" to keep the
/// `settings` table human-readable when inspected via sqlite3 CLI.
public extension Database {
    func getHiddenFilesEnabled() throws -> Bool {
        return (try getSetting(SettingsKey.hiddenFilesEnabled)) == "1"
    }

    func setHiddenFilesEnabled(_ enabled: Bool) throws {
        try setSetting(SettingsKey.hiddenFilesEnabled, value: enabled ? "1" : "0")
    }

    /// E1 user-configurable search result limit. Reads the stored value if
    /// present and valid; falls back to `SearchLimitBounds.defaultValue` for
    /// missing / malformed / out-of-range entries. Callers should not have to
    /// think about migration: this is always safe to read on a fresh DB.
    func getSearchLimit() throws -> Int {
        guard let raw = try getSetting(SettingsKey.searchLimit) else {
            return SearchLimitBounds.defaultValue
        }
        guard let n = Int(raw) else { return SearchLimitBounds.defaultValue }
        return clampSearchLimit(n)
    }

    /// Persist a validated search limit. Values are clamped into the allowed
    /// [minimum, maximum] band before write so the settings table can never
    /// hold values the search layer would have to reject at read time.
    func setSearchLimit(_ value: Int) throws {
        let clamped = clampSearchLimit(value)
        try setSetting(SettingsKey.searchLimit, value: String(clamped))
    }
}

public func clampSearchLimit(_ value: Int) -> Int {
    return max(SearchLimitBounds.minimum,
               min(SearchLimitBounds.maximum, value))
}

public extension Database {
    /// G3: read persisted index mode. Returns `.compact` on missing /
    /// malformed rows (matches new-DB default). Callers that need to
    /// preserve v4 behaviour on upgrade paths must check for the
    /// setting's presence explicitly via `getSetting(_:)` before
    /// relying on this default.
    func getIndexMode() throws -> IndexMode {
        let raw = try getSetting(SettingsKey.indexMode) ?? ""
        return IndexMode(rawValue: raw) ?? .compact
    }

    /// G3: set index mode. No side effects here — the caller is
    /// responsible for triggering rebuild / backfill flows (see
    /// `MigrationCoordinator`).
    func setIndexMode(_ mode: IndexMode) throws {
        try setSetting(SettingsKey.indexMode, value: mode.rawValue)
    }

    /// F3: persisted result sort order, used by SearchViewController to
    /// restore the last-used sort on launch. Returns `.scoreDescending`
    /// on missing / malformed row so first-run UX is still sane.
    func getResultSortOrder() throws -> SearchSortOrder {
        let rawKey = try getSetting(SettingsKey.resultSortKey) ?? ""
        let rawAsc = try getSetting(SettingsKey.resultSortAscending) ?? ""
        guard let key = SearchSortKey(rawValue: rawKey) else {
            return .scoreDescending
        }
        let ascending = (rawAsc == "1")
        return SearchSortOrder(key: key, ascending: ascending)
    }

    /// F3: write back result sort order on user action.
    func setResultSortOrder(_ order: SearchSortOrder) throws {
        try setSetting(SettingsKey.resultSortKey, value: order.key.rawValue)
        try setSetting(SettingsKey.resultSortAscending, value: order.ascending ? "1" : "0")
    }

    /// F3: persisted per-column width for the result table. Returns nil
    /// when the column hasn't been resized; caller should fall back to
    /// its programmed default.
    func getResultColumnWidth(key: String) throws -> Double? {
        guard let raw = try getSetting(key), let d = Double(raw) else { return nil }
        return d
    }

    func setResultColumnWidth(key: String, width: Double) throws {
        try setSetting(key, value: String(format: "%.0f", width))
    }

    /// J6: persisted Settings tab index (which tab user had open
    /// last). Returns 0 when unset / malformed so first run opens
    /// on 常规 without surprise.
    func getSettingsTabIndex() throws -> Int {
        guard let raw = try getSetting(SettingsKey.settingsTabIndex),
              let n = Int(raw) else { return 0 }
        return max(0, n)
    }

    func setSettingsTabIndex(_ n: Int) throws {
        try setSetting(SettingsKey.settingsTabIndex, value: String(max(0, n)))
    }

    /// J6: user-expressed intent for login launch. This is an
    /// opt-in mirror of SMAppService state so the UI can reflect
    /// intent even if SMAppService reports a stale `.notRegistered`
    /// between unsigned-build launches.
    func getLaunchAtLoginRequested() throws -> Bool {
        let raw = try getSetting(SettingsKey.launchAtLoginRequested) ?? ""
        return raw == "1"
    }

    func setLaunchAtLoginRequested(_ enabled: Bool) throws {
        try setSetting(SettingsKey.launchAtLoginRequested, value: enabled ? "1" : "0")
    }

    /// L2: read the persisted Dock-icon-visible intent. Default is
    /// `false` (L1 menubar-agent / no Dock). The actual `NSApp`
    /// activation policy is applied by `AppDelegate` in
    /// `applicationDidFinishLaunching` based on this value.
    func getDockIconVisible() throws -> Bool {
        let raw = try getSetting(SettingsKey.dockIconVisible) ?? ""
        return raw == "1"
    }

    func setDockIconVisible(_ visible: Bool) throws {
        try setSetting(SettingsKey.dockIconVisible, value: visible ? "1" : "0")
    }

    /// J2: clear all persisted result-column widths so the next
    /// `SearchViewController` launch falls back to the programmed
    /// defaults. Invoked from the result table's header context
    /// menu ("重置列宽"). Returns the number of rows removed so
    /// callers can show a sensible status message.
    ///
    /// This does NOT touch the sort-order keys — the user's
    /// chosen sort is orthogonal to column widths.
    @discardableResult
    func resetResultColumnWidths() throws -> Int {
        let keys = [
            SettingsKey.resultColumnWidthName,
            SettingsKey.resultColumnWidthPath,
            SettingsKey.resultColumnWidthMtime,
            SettingsKey.resultColumnWidthSize,
            SettingsKey.resultColumnWidthOpenCount,
            SettingsKey.resultColumnWidthLastOpened,
        ]
        var removed = 0
        for k in keys {
            // setSetting stores an empty value rather than a real
            // DELETE, but getResultColumnWidth already treats
            // non-parseable strings as nil so round-tripping is
            // equivalent to "never set". Use a direct DELETE
            // anyway to keep the settings table tidy.
            if try getSetting(k) != nil { removed += 1 }
            try exec("DELETE FROM settings WHERE key = '\(k)';")
            invalidateSettingsCache(key: k)
        }
        return removed
    }

    /// Read persisted hotkey (Carbon keyCode + modifier mask). Returns
    /// the default preset if missing or malformed so first launches /
    /// corrupt settings rows never leave the app without a working
    /// global hotkey.
    func getHotkey() throws -> (keyCode: UInt32, modifiers: UInt32) {
        let raw1 = try getSetting(SettingsKey.hotkeyKeyCode)
        let raw2 = try getSetting(SettingsKey.hotkeyModifiers)
        if let r1 = raw1, let r2 = raw2,
           let k = UInt32(r1), let m = UInt32(r2) {
            return (k, m)
        }
        let d = HotkeyPresets.default
        return (d.keyCode, d.modifiers)
    }

    /// Persist a hotkey combo. Both values are written together so
    /// readers never see a partially-updated pair.
    func setHotkey(keyCode: UInt32, modifiers: UInt32) throws {
        try setSetting(SettingsKey.hotkeyKeyCode, value: String(keyCode))
        try setSetting(SettingsKey.hotkeyModifiers, value: String(modifiers))
    }
}

// MARK: - E4 root health

/// Stage-E4 + K5 health classification for a registered root.
///
/// K5 split: the original `.offline` lumped "volume ejected" together
/// with "path was deleted/renamed". Diagnostics + recovery steps are
/// different, so K5 separates `.volumeOffline` (under `/Volumes/X`
/// where `/Volumes/X` itself is gone) from `.offline` (path missing
/// elsewhere on disk). `.unavailable` (permission denied) stays
/// distinct from both — the recovery is "grant Full Disk Access in
/// System Settings", not "remount" or "recreate the path".
public enum RootHealth: String, Equatable, Sendable {
    /// Path exists, is readable, and the root is enabled by the user.
    case ready
    /// A rebuild is currently walking this root.
    case indexing
    /// User-disabled via the enable toggle. Data may still exist in the
    /// index but search is filtered out.
    case paused
    /// External volume mount point itself is missing (e.g. `/Volumes/Backup`
    /// where `/Volumes/Backup` doesn't exist on disk). Recovery: reconnect
    /// the drive.
    case volumeOffline
    /// Path doesn't exist on disk (directory moved / renamed / deleted).
    /// Recovery: re-add the new path or remove the entry.
    case offline
    /// Path exists but isn't readable. Typically macOS privacy / Full
    /// Disk Access. Recovery: System Settings → 隐私与安全性 → 完全
    /// 磁盘访问 → 添加 SwiftSeek → 回 SwiftSeek 点 "重新检查权限"。
    case unavailable

    /// Short human-facing marker for the roots table. The emoji carries
    /// the bulk of the visual signal; the text clarifies intent for
    /// accessibility / screen readers.
    public var uiLabel: String {
        switch self {
        case .ready:         return "✅ 就绪"
        case .indexing:      return "⏳ 索引中"
        case .paused:        return "⏸ 已停用"
        case .volumeOffline: return "💾 卷未挂载"
        case .offline:       return "🔌 路径不存在"
        case .unavailable:   return "⚠️ 无访问权限"
        }
    }
}

/// K5 — full health report for a registered root. Adds an explanatory
/// `detail` string keyed off the active `RootHealth` so the UI tooltip,
/// `Diagnostics.snapshot`, and CLI output share one phrasing.
public struct RootHealthReport: Equatable, Sendable {
    public let health: RootHealth
    public let detail: String
    public init(health: RootHealth, detail: String) {
        self.health = health
        self.detail = detail
    }
}

public extension Database {
    /// Compute health for a single root. Takes an optional
    /// `currentlyIndexingPath` so the caller can pass the path reported
    /// by `RebuildCoordinator` without doing its own matching.
    func computeRootHealth(for row: RootRow,
                           currentlyIndexingPath: String? = nil) -> RootHealth {
        return computeRootHealthReport(for: row,
                                       currentlyIndexingPath: currentlyIndexingPath).health
    }

    /// K5 — full root health report with explanatory detail. The
    /// detail string is suitable for tooltips and copyable
    /// diagnostics; never empty.
    func computeRootHealthReport(for row: RootRow,
                                 currentlyIndexingPath: String? = nil) -> RootHealthReport {
        if !row.enabled {
            return .init(health: .paused, detail: "用户已停用此 root；搜索结果不会包含它，但已索引数据仍保留。")
        }
        if let busy = currentlyIndexingPath, busy == row.path {
            return .init(health: .indexing, detail: "正在重新索引此 root；扫描完成后状态会变 ready。")
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: row.path, isDirectory: &isDir)
        if !exists {
            // K5: distinguish external-volume-offline from
            // generic path-missing. macOS mounts external volumes
            // at /Volumes/<name>; if the path is `/Volumes/Foo/...`
            // and `/Volumes/Foo` itself doesn't exist, the drive
            // is unmounted (not deleted).
            if let volRoot = volumeMountPoint(for: row.path),
               !fm.fileExists(atPath: volRoot) {
                return .init(health: .volumeOffline,
                             detail: "外接卷 \(volRoot) 当前未挂载。重新连接驱动器后回到 SwiftSeek 点 '重新检查权限' 即可恢复索引。")
            }
            return .init(health: .offline,
                         detail: "路径不存在：可能被移动 / 重命名 / 删除。请重新添加正确路径或在索引范围里移除此 root。")
        }
        if !isDir.boolValue {
            return .init(health: .offline,
                         detail: "路径指向的不是目录（可能是文件或符号链接）。请改为目录路径。")
        }
        if !fm.isReadableFile(atPath: row.path) {
            return .init(health: .unavailable,
                         detail: "路径存在但 SwiftSeek 没有读权限。常见原因：未授予完全磁盘访问。系统设置 → 隐私与安全性 → 完全磁盘访问 → 添加 SwiftSeek，然后回到 SwiftSeek 点 '重新检查权限'。")
        }
        return .init(health: .ready,
                     detail: "路径可访问，索引正常。")
    }

    /// K5 helper — returns the `/Volumes/<name>` mount point for a path
    /// rooted under `/Volumes/`, else nil. `/Volumes/Foo/sub` → `/Volumes/Foo`.
    /// `/Volumes/Foo` (volume root itself) → `/Volumes/Foo`. Anything not
    /// under `/Volumes/` → nil. Trims trailing slashes; returns nil for
    /// `/Volumes` alone (no actual volume name component).
    private func volumeMountPoint(for path: String) -> String? {
        guard path.hasPrefix("/Volumes/") else { return nil }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // After trim: "Volumes/Foo/sub" or "Volumes/Foo" or "Volumes".
        let parts = trimmed.split(separator: "/", maxSplits: 2).map(String.init)
        // parts[0] = "Volumes", parts[1] = volume name (required), tail ignored
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        return "/Volumes/\(parts[1])"
    }
}

/// Static predicate shared by `Indexer` (full-walk) and the rescan / watcher
/// paths so a path excluded at index time is ALSO excluded on any incremental
/// re-entry — keeps the two code paths consistent.
public enum ExcludeFilter {
    /// Returns true iff `path` equals any pattern, or is a strict descendant of
    /// any pattern (shares a `/` boundary).
    public static func isExcluded(_ path: String, patterns: [String]) -> Bool {
        let canonical = path
        for pattern in patterns {
            if canonical == pattern { return true }
            if canonical.hasPrefix(pattern + "/") { return true }
        }
        return false
    }
}

/// Hidden-file predicate.
///
/// macOS "hidden" is the union of three signals:
///   1. Any path component begins with "." (dotfiles, .DS_Store, .git, …)
///   2. The file has the UF_HIDDEN flag (rare; system files like "Volumes")
///   3. Is in a well-known system hidden location (e.g. "/Library/Caches/…")
///
/// For SwiftSeek v1 we use rule #1 only — it is the stable, filesystem-native
/// definition understood by `ls -a` and roughly 100% of developer use. If the
/// indexer walks into a path with ANY dot-prefixed component, the entry is
/// hidden; when the `hidden_files_enabled` toggle is OFF we skip it.
public enum HiddenPath {
    public static func isHidden(_ path: String) -> Bool {
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component.first == "." { return true }
        }
        return false
    }
}
