import Foundation
import CSQLite

/// H1 — SwiftSeek-internal usage record for a single file.
///
/// Semantics (documented for users in `docs/known_issues.md`):
///   * `openCount` is the number of times the user triggered a successful
///     `.open` action through SwiftSeek (window / CLI). It is NOT the macOS
///     global launch count — we have no reliable public API for that and
///     we will not use private API or scrape system history.
///   * `lastOpenedAt` / `updatedAt` are Unix epoch seconds.
///   * A row is only created on the first successful `.open`; a fresh DB
///     has zero `file_usage` rows.
public struct UsageRecord: Equatable, Sendable {
    public let fileId: Int64
    public let openCount: Int64
    public let lastOpenedAt: Int64
    public let updatedAt: Int64

    public init(fileId: Int64,
                openCount: Int64,
                lastOpenedAt: Int64,
                updatedAt: Int64) {
        self.fileId = fileId
        self.openCount = openCount
        self.lastOpenedAt = lastOpenedAt
        self.updatedAt = updatedAt
    }
}

public extension Database {
    /// H1 — look up `files.id` by canonical path. Returns nil if path is
    /// not indexed (yet). Callers in the recordOpen path use this to
    /// distinguish "usage write succeeded" from "target not in DB" so
    /// they can log instead of silently failing.
    func lookupFileId(path: String) throws -> Int64? {
        guard let handle = rawHandle else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT id FROM files WHERE path = ? LIMIT 1;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if sqlite3_bind_text(stmt, 1, path, -1, transient) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.bindFailed(code: -1, message: msg)
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }

    /// H1 — record a successful `.open`. Upserts the file_usage row:
    ///   * open_count += 1
    ///   * last_opened_at = now
    ///   * updated_at = now
    ///
    /// Contract:
    ///   * Returns `true` if `path` resolved to a `files.id` and the
    ///     upsert executed.
    ///   * Returns `false` if `path` is not in the index — the caller
    ///     should `NSLog` / surface this so it's not a silent fail. The
    ///     usage table is NOT written.
    ///   * The caller is responsible for ONLY invoking this after a
    ///     successful open (e.g. `NSWorkspace.shared.open(URL) -> Bool`
    ///     returned true). We do not check the filesystem here; a call
    ///     to `recordOpen` is the contract that "the action succeeded".
    @discardableResult
    func recordOpen(path: String, now: Int64? = nil) throws -> Bool {
        let ts = now ?? Int64(Date().timeIntervalSince1970)
        guard let fileId = try lookupFileId(path: path) else {
            NSLog("SwiftSeek: recordOpen skipped, path not in index: \(path)")
            return false
        }
        try upsertUsage(fileId: fileId, now: ts)
        return true
    }

    /// H1 — direct-by-id variant. Exposed so tests (and future H2/H3
    /// internal callers) can drive the usage table without an extra
    /// path lookup round-trip.
    @discardableResult
    func recordOpen(fileId: Int64, now: Int64? = nil) throws -> Bool {
        let ts = now ?? Int64(Date().timeIntervalSince1970)
        try upsertUsage(fileId: fileId, now: ts)
        return true
    }

    private func upsertUsage(fileId: Int64, now: Int64) throws {
        guard let handle = rawHandle else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO file_usage(file_id, open_count, last_opened_at, updated_at)
        VALUES (?, 1, ?, ?)
        ON CONFLICT(file_id) DO UPDATE SET
            open_count = open_count + 1,
            last_opened_at = excluded.last_opened_at,
            updated_at = excluded.updated_at;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_bind_int64(stmt, 1, fileId)
        _ = sqlite3_bind_int64(stmt, 2, now)
        _ = sqlite3_bind_int64(stmt, 3, now)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
    }

    /// H1 — read usage row by file_id. Returns nil if no row (initial
    /// state for any file that has never been opened through SwiftSeek).
    func getUsageByFileId(_ fileId: Int64) throws -> UsageRecord? {
        guard let handle = rawHandle else { return nil }
        var stmt: OpaquePointer?
        let sql = """
        SELECT file_id, open_count, last_opened_at, updated_at
        FROM file_usage WHERE file_id = ? LIMIT 1;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_bind_int64(stmt, 1, fileId)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return UsageRecord(
                fileId: sqlite3_column_int64(stmt, 0),
                openCount: sqlite3_column_int64(stmt, 1),
                lastOpenedAt: sqlite3_column_int64(stmt, 2),
                updatedAt: sqlite3_column_int64(stmt, 3)
            )
        }
        return nil
    }

    /// H1 — read usage row by path (convenience for tests and UI).
    /// Returns nil if the path is not in the index OR if the path has no
    /// usage row yet.
    func getUsageByPath(_ path: String) throws -> UsageRecord? {
        guard let fileId = try lookupFileId(path: path) else { return nil }
        return try getUsageByFileId(fileId)
    }
}
