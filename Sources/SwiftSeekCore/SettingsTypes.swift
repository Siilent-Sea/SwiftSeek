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
