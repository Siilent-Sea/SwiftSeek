import Foundation
import CSQLite

/// J4 — recent search query record.
public struct QueryHistoryEntry: Equatable, Sendable {
    public let query: String
    public let lastUsedAt: Int64
    public let useCount: Int64

    public init(query: String, lastUsedAt: Int64, useCount: Int64) {
        self.query = query
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

/// J4 — user-saved filter: a named query template.
public struct SavedFilterEntry: Equatable, Sendable {
    public let name: String
    public let query: String
    public let createdAt: Int64
    public let updatedAt: Int64

    public init(name: String, query: String, createdAt: Int64, updatedAt: Int64) {
        self.name = name
        self.query = query
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension Database {
    // MARK: - J4 query history

    /// Read the query-history privacy toggle. Defaults to `true`
    /// when the setting is unset or malformed. Same opt-out pattern
    /// as `isUsageHistoryEnabled` (H4).
    func isQueryHistoryEnabled() throws -> Bool {
        let raw = try getSetting(SettingsKey.queryHistoryEnabled) ?? ""
        if raw.isEmpty { return true }
        return raw != "0"
    }

    /// Flip the query-history privacy toggle. While disabled,
    /// `recordQueryHistory` returns false without writing.
    func setQueryHistoryEnabled(_ enabled: Bool) throws {
        try setSetting(SettingsKey.queryHistoryEnabled, value: enabled ? "1" : "0")
    }

    /// Record a committed query (user invoked `.open` on a result
    /// from this query). Returns:
    ///   * `false` when `query` is empty / whitespace-only, or when
    ///     the history toggle is off (with an NSLog trace so we
    ///     don't silently discard user intent).
    ///   * `true` after a successful UPSERT (`use_count += 1`,
    ///     `last_used_at = now`).
    @discardableResult
    func recordQueryHistory(_ query: String, now: Int64? = nil) throws -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if try !isQueryHistoryEnabled() {
            NSLog("SwiftSeek: recordQueryHistory skipped, query history disabled: \(trimmed)")
            return false
        }
        let ts = now ?? Int64(Date().timeIntervalSince1970)
        guard let handle = rawHandle else { return false }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO query_history(query, last_used_at, use_count)
        VALUES (?, ?, 1)
        ON CONFLICT(query) DO UPDATE SET
            last_used_at = excluded.last_used_at,
            use_count    = use_count + 1;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, trimmed, -1, transient)
        _ = sqlite3_bind_int64(stmt, 2, ts)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
        return true
    }

    /// Most-recent-first list of query history. `limit` caps the
    /// result set; default 20 covers the UI dropdown.
    func listRecentQueries(limit: Int = 20) throws -> [QueryHistoryEntry] {
        guard let handle = rawHandle else { return [] }
        var stmt: OpaquePointer?
        let sql = """
        SELECT query, last_used_at, use_count
        FROM query_history
        ORDER BY last_used_at DESC
        LIMIT ?;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_bind_int64(stmt, 1, Int64(limit))
        var out: [QueryHistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let q = String(cString: sqlite3_column_text(stmt, 0))
            let ts = sqlite3_column_int64(stmt, 1)
            let n = sqlite3_column_int64(stmt, 2)
            out.append(QueryHistoryEntry(query: q, lastUsedAt: ts, useCount: n))
        }
        return out
    }

    /// Delete ALL rows from `query_history`. Returns the pre-delete
    /// row count so callers can show a confirmation toast.
    @discardableResult
    func clearQueryHistory() throws -> Int64 {
        let before = try countRows(in: "query_history")
        try exec("DELETE FROM query_history;")
        return before
    }

    // MARK: - J4 saved filters

    /// Save (or overwrite) a named filter. Empty name or empty
    /// query → false. Does NOT check whether the filter would return
    /// any results — users may legitimately save queries that are
    /// empty today but populate later.
    @discardableResult
    func saveFilter(name: String, query: String, now: Int64? = nil) throws -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedQuery.isEmpty { return false }
        let ts = now ?? Int64(Date().timeIntervalSince1970)
        guard let handle = rawHandle else { return false }
        var stmt: OpaquePointer?
        // Use strftime-style created_at preservation: keep the earliest
        // created_at on overwrite, refresh updated_at.
        let sql = """
        INSERT INTO saved_filters(name, query, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET
            query = excluded.query,
            updated_at = excluded.updated_at;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, trimmedName, -1, transient)
        _ = sqlite3_bind_text(stmt, 2, trimmedQuery, -1, transient)
        _ = sqlite3_bind_int64(stmt, 3, ts)
        _ = sqlite3_bind_int64(stmt, 4, ts)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
        return true
    }

    /// Delete a saved filter by name. Returns true if a row was
    /// removed, false if no row matched (callers can show "not
    /// found" messaging).
    @discardableResult
    func removeSavedFilter(name: String) throws -> Bool {
        guard let handle = rawHandle else { return false }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM saved_filters WHERE name = ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, name, -1, transient)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
        return sqlite3_changes(handle) > 0
    }

    /// List saved filters ordered by `name` (alpha) — stable output
    /// so UI rendering doesn't jitter on unrelated updates.
    func listSavedFilters() throws -> [SavedFilterEntry] {
        guard let handle = rawHandle else { return [] }
        var stmt: OpaquePointer?
        let sql = """
        SELECT name, query, created_at, updated_at
        FROM saved_filters
        ORDER BY name ASC;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        var out: [SavedFilterEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let q = String(cString: sqlite3_column_text(stmt, 1))
            let ca = sqlite3_column_int64(stmt, 2)
            let ua = sqlite3_column_int64(stmt, 3)
            out.append(SavedFilterEntry(name: name, query: q,
                                        createdAt: ca, updatedAt: ua))
        }
        return out
    }
}
