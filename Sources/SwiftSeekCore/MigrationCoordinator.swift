import Foundation
import CSQLite

/// G3 — background compact-index backfill coordinator.
///
/// When a user switches from fullpath mode to compact mode on an existing
/// DB, all files that were indexed under fullpath still need to get their
/// compact-index rows written (`file_name_grams`, `file_name_bigrams`,
/// `file_path_segments`). Doing this inside `Database.migrate()` would
/// hold a multi-minute `BEGIN IMMEDIATE` during app startup on 500k+
/// libraries — exactly the footprint regression we set out to avoid.
///
/// This coordinator runs out of the `migrate()` path on a background queue
/// with one small transaction per batch and a WAL checkpoint between
/// batches. Progress is stamped into `migration_progress` so an
/// interrupted run can resume where it left off.
///
/// The caller (UI/CLI) is responsible for triggering this; migrate()
/// only creates the schema.
public final class MigrationCoordinator: @unchecked Sendable {
    public struct Progress: Sendable {
        public var processed: Int64        // file rows processed so far
        public var total: Int64            // total files table row count snapshotted at start
        public var lastFileId: Int64       // last fully-processed file id
        public init(processed: Int64, total: Int64, lastFileId: Int64) {
            self.processed = processed
            self.total = total
            self.lastFileId = lastFileId
        }
    }

    public struct Summary: Sendable {
        public var processed: Int64
        public var total: Int64
        public var durationSeconds: TimeInterval
        public var error: String?
        public init(processed: Int64 = 0, total: Int64 = 0,
                    durationSeconds: TimeInterval = 0, error: String? = nil) {
            self.processed = processed
            self.total = total
            self.durationSeconds = durationSeconds
            self.error = error
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case running(started: Date, processed: Int64, total: Int64)
    }

    /// Settings key under `migration_progress` for the resume point.
    public static let progressLastFileIdKey = "compact_backfill_last_file_id"

    private let database: Database
    private let queue = DispatchQueue(label: "swiftseek.migration", qos: .utility)
    private let stateLock = NSLock()
    private var _state: State = .idle
    /// Batch size — exposed for tests so we can drive partial runs on
    /// small fixtures.
    public var batchSize: Int = 5000

    public init(database: Database) {
        self.database = database
    }

    public var state: State {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Kick off a compact-index backfill. Returns false when one is
    /// already in flight. Progress is written to `migration_progress`
    /// on every batch so a later resume can continue; failures leave
    /// the row in place so "继续回填 (X / Y)" UX still works.
    ///
    /// `resume: true` continues from the last saved `last_file_id`;
    /// `resume: false` resets the resume point and starts over.
    @discardableResult
    public func backfillCompact(resume: Bool = true,
                                onProgress: @escaping (Progress) -> Void = { _ in },
                                onFinish: @escaping (Summary) -> Void = { _ in }) -> Bool {
        stateLock.lock()
        if case .running = _state { stateLock.unlock(); return false }
        stateLock.unlock()

        let startedAt = Date()
        queue.async { [weak self] in
            guard let self else { return }
            var summary = Summary(durationSeconds: 0)
            do {
                // Reset resume point if requested.
                if !resume {
                    try self.database.exec(
                        "DELETE FROM migration_progress WHERE key = '\(Self.progressLastFileIdKey)';")
                }
                let lastFileId = self.readLastFileId()
                let total = try self.database.scalarInt("SELECT COUNT(*) FROM files;") ?? 0
                summary.total = total

                // Update state → running.
                self.setState(.running(started: startedAt,
                                       processed: 0,
                                       total: total))

                var cursor = lastFileId
                var processed: Int64 = 0
                let batchSize = self.batchSize
                while true {
                    let batchRows = try self.fetchBatch(afterFileId: cursor, limit: batchSize)
                    if batchRows.isEmpty { break }
                    try self.database.exec("BEGIN IMMEDIATE;")
                    do {
                        for row in batchRows {
                            try self.writeCompactRowsFor(fileId: row.id,
                                                        nameLower: row.nameLower,
                                                        pathLower: row.pathLower)
                            cursor = row.id
                            processed += 1
                        }
                        // Stamp resume point inside the batch transaction
                        // so the whole batch is atomic.
                        try self.database.exec("""
                        INSERT INTO migration_progress(key, value)
                        VALUES ('\(Self.progressLastFileIdKey)', '\(cursor)')
                        ON CONFLICT(key) DO UPDATE SET value=excluded.value;
                        """)
                        try self.database.exec("COMMIT;")
                    } catch {
                        try? self.database.exec("ROLLBACK;")
                        throw error
                    }
                    // Keep WAL from ballooning. PASSIVE = best-effort, doesn't
                    // block; if a reader is active we just skip and try again
                    // next batch.
                    try? self.database.exec("PRAGMA wal_checkpoint(PASSIVE);")
                    self.setState(.running(started: startedAt,
                                           processed: processed,
                                           total: total))
                    onProgress(Progress(processed: processed,
                                        total: total,
                                        lastFileId: cursor))
                }

                summary.processed = processed
                summary.durationSeconds = Date().timeIntervalSince(startedAt)
            } catch {
                NSLog("SwiftSeek: MigrationCoordinator backfillCompact failed: \(error)")
                summary.error = "\(error)"
                summary.durationSeconds = Date().timeIntervalSince(startedAt)
            }
            self.setState(.idle)
            onFinish(summary)
        }
        return true
    }

    /// Expose the persisted resume point so the UI / CLI can decide
    /// whether to show a "resume" or "start fresh" button.
    public func readLastFileId() -> Int64 {
        guard let handle = database.rawHandle else { return 0 }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM migration_progress WHERE key = ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, Self.progressLastFileIdKey, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        let text = String(cString: sqlite3_column_text(stmt, 0))
        return Int64(text) ?? 0
    }

    // MARK: - Internals

    private struct FetchedRow {
        let id: Int64
        let nameLower: String
        let pathLower: String
    }

    private func fetchBatch(afterFileId: Int64, limit: Int) throws -> [FetchedRow] {
        guard let handle = database.rawHandle else { return [] }
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, name_lower, path_lower FROM files
        WHERE id > ?
        ORDER BY id
        LIMIT ?;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_bind_int64(stmt, 1, afterFileId)
        _ = sqlite3_bind_int64(stmt, 2, Int64(limit))
        var out: [FetchedRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(FetchedRow(
                id: sqlite3_column_int64(stmt, 0),
                nameLower: String(cString: sqlite3_column_text(stmt, 1)),
                pathLower: String(cString: sqlite3_column_text(stmt, 2))
            ))
        }
        return out
    }

    /// Write one file's compact-index rows. Prepared statements are
    /// re-created per batch transaction in writeCompactRowsFor rather
    /// than once per coordinator lifetime — coordinator runs rarely so
    /// the overhead is negligible.
    private func writeCompactRowsFor(fileId: Int64,
                                     nameLower: String,
                                     pathLower: String) throws {
        guard let handle = database.rawHandle else { return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        // Trigrams
        try upsertIndex(
            handle: handle,
            deleteSQL: "DELETE FROM file_name_grams WHERE file_id = ?;",
            insertSQL: "INSERT OR IGNORE INTO file_name_grams(file_id, gram) VALUES (?, ?);",
            fileId: fileId,
            values: Gram.nameGrams(nameLower: nameLower),
            transient: transient
        )
        // Bigrams
        try upsertIndex(
            handle: handle,
            deleteSQL: "DELETE FROM file_name_bigrams WHERE file_id = ?;",
            insertSQL: "INSERT OR IGNORE INTO file_name_bigrams(file_id, gram) VALUES (?, ?);",
            fileId: fileId,
            values: Gram.nameBigrams(nameLower: nameLower),
            transient: transient
        )
        // Path segments
        try upsertIndex(
            handle: handle,
            deleteSQL: "DELETE FROM file_path_segments WHERE file_id = ?;",
            insertSQL: "INSERT OR IGNORE INTO file_path_segments(file_id, segment) VALUES (?, ?);",
            fileId: fileId,
            values: Gram.pathSegments(pathLower: pathLower),
            transient: transient
        )
    }

    private func upsertIndex(handle: OpaquePointer,
                             deleteSQL: String,
                             insertSQL: String,
                             fileId: Int64,
                             values: Set<String>,
                             transient: sqlite3_destructor_type) throws {
        // Delete
        var delStmt: OpaquePointer?
        let delRC = sqlite3_prepare_v2(handle, deleteSQL, -1, &delStmt, nil)
        guard delRC == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: delRC, message: msg, sql: deleteSQL)
        }
        defer { sqlite3_finalize(delStmt) }
        _ = sqlite3_bind_int64(delStmt, 1, fileId)
        let d = sqlite3_step(delStmt)
        if d != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: d, message: msg, sql: deleteSQL)
        }
        // Insert each value
        var insStmt: OpaquePointer?
        let insRC = sqlite3_prepare_v2(handle, insertSQL, -1, &insStmt, nil)
        guard insRC == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: insRC, message: msg, sql: insertSQL)
        }
        defer { sqlite3_finalize(insStmt) }
        for v in values {
            sqlite3_reset(insStmt)
            sqlite3_clear_bindings(insStmt)
            _ = sqlite3_bind_int64(insStmt, 1, fileId)
            _ = sqlite3_bind_text(insStmt, 2, v, -1, transient)
            let step = sqlite3_step(insStmt)
            if step != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw DatabaseError.stepFailed(code: step, message: msg, sql: insertSQL)
            }
        }
    }

    private func setState(_ s: State) {
        stateLock.lock()
        _state = s
        stateLock.unlock()
    }
}
