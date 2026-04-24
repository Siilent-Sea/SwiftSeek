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

/// Stage-E4 health classification for a registered root. The UI uses this
/// to replace the pure enabled/disabled flag with a richer state so the
/// user can tell the difference between "I paused this" and "the volume
/// is not mounted right now".
public enum RootHealth: String, Equatable, Sendable {
    /// Path exists, is readable, and the root is enabled by the user.
    case ready
    /// A rebuild is currently walking this root.
    case indexing
    /// User-disabled via the enable toggle. Data may still exist in the
    /// index but search is filtered out.
    case paused
    /// Path does not exist on disk (e.g. external volume ejected,
    /// directory moved or deleted).
    case offline
    /// Path exists but is not readable (permission denied). Typically
    /// macOS privacy / full-disk-access constraints.
    case unavailable

    /// Short human-facing marker for the roots table. The emoji carries
    /// the bulk of the visual signal; the text clarifies intent for
    /// accessibility / screen readers.
    public var uiLabel: String {
        switch self {
        case .ready:       return "✅ 就绪"
        case .indexing:    return "⏳ 索引中"
        case .paused:      return "⏸ 已停用"
        case .offline:     return "🔌 未挂载"
        case .unavailable: return "⚠️ 不可访问"
        }
    }
}

public extension Database {
    /// Compute health for a single root. Takes an optional
    /// `currentlyIndexingPath` so the caller can pass the path reported
    /// by `RebuildCoordinator` without doing its own matching.
    func computeRootHealth(for row: RootRow,
                           currentlyIndexingPath: String? = nil) -> RootHealth {
        if !row.enabled { return .paused }
        if let busy = currentlyIndexingPath, busy == row.path { return .indexing }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: row.path, isDirectory: &isDir) else {
            return .offline
        }
        // A file-as-root is still "offline-shaped" from the user's
        // perspective: we can't walk it. Treat the same as a missing dir.
        if !isDir.boolValue { return .offline }
        guard fm.isReadableFile(atPath: row.path) else { return .unavailable }
        return .ready
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
