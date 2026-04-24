import Foundation
import CSQLite

public enum DatabaseError: Error, CustomStringConvertible {
    case openFailed(code: Int32, message: String)
    case prepareFailed(code: Int32, message: String, sql: String)
    case stepFailed(code: Int32, message: String, sql: String)
    case bindFailed(code: Int32, message: String)

    public var description: String {
        switch self {
        case let .openFailed(code, message):
            return "open failed (\(code)): \(message)"
        case let .prepareFailed(code, message, sql):
            return "prepare failed (\(code)): \(message) sql=\(sql)"
        case let .stepFailed(code, message, sql):
            return "step failed (\(code)): \(message) sql=\(sql)"
        case let .bindFailed(code, message):
            return "bind failed (\(code)): \(message)"
        }
    }
}

public final class Database {
    private var handle: OpaquePointer?
    public let url: URL
    public private(set) var schemaVersion: Int32 = 0

    // F1 hot-path caches. Avoid re-reading the same rows on every single
    // keystroke's worth of search. All mutations (registerRoot, removeRoot,
    // setRootEnabled, setSetting) invalidate the relevant cache.
    private let cacheLock = NSLock()
    private var rootsCached: [RootRow]?
    private var settingsCached: [String: String?] = [:]
    /// Exposed for tests / bench harness. Observation-only: lets callers
    /// verify cache hit behaviour without reaching into `rootsCached`.
    public private(set) var rootsCacheHits: Int = 0
    public private(set) var rootsCacheMisses: Int = 0

    private init(handle: OpaquePointer, url: URL) {
        self.handle = handle
        self.url = url
    }

    /// F1: drop memoised roots / settings so the next read re-hits the DB.
    /// Called from the few write paths that can invalidate state.
    func invalidateRootsCache() {
        cacheLock.lock()
        rootsCached = nil
        cacheLock.unlock()
    }
    func invalidateSettingsCache(key: String? = nil) {
        cacheLock.lock()
        if let k = key {
            settingsCached.removeValue(forKey: k)
        } else {
            settingsCached.removeAll()
        }
        cacheLock.unlock()
    }

    public static func open(at url: URL) throws -> Database {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = String(cString: sqlite3_errmsg(handle))
            if let handle { sqlite3_close_v2(handle) }
            throw DatabaseError.openFailed(code: rc, message: msg)
        }
        let db = Database(handle: handle, url: url)
        try db.exec("PRAGMA journal_mode=WAL;")
        try db.exec("PRAGMA synchronous=NORMAL;")
        try db.exec("PRAGMA foreign_keys=ON;")
        return db
    }

    public var rawHandle: OpaquePointer? { handle }

    public func close() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    deinit {
        close()
    }

    public func migrate() throws {
        let current = try readUserVersion()
        if current >= Schema.currentVersion {
            schemaVersion = current
            return
        }
        let pending = Schema.migrations
            .filter { $0.target > current && $0.target <= Schema.currentVersion }
            .sorted { $0.target < $1.target }
        guard !pending.isEmpty else {
            schemaVersion = current
            return
        }
        try exec("BEGIN IMMEDIATE;")
        do {
            for migration in pending {
                for stmt in migration.statements {
                    try exec(stmt)
                }
                // v2 introduces the gram index. Backfill grams for rows that predate the
                // migration so existing P1 data becomes searchable without re-indexing.
                if migration.target == 2 {
                    try backfillFileGrams()
                }
                // F1 v4 introduces the bigram index. Backfill so existing v3
                // databases become short-query-searchable without re-indexing.
                if migration.target == 4 {
                    try backfillFileBigrams()
                }
                // G3 v5: CREATE-only migration. Backfill of existing rows
                // into the new compact tables is out-of-band via
                // MigrationCoordinator (so we don't hold a multi-minute
                // BEGIN IMMEDIATE during startup). Here we only seed the
                // index_mode setting:
                //   * brand-new DB (no pre-existing schema, current == 0)
                //     → compact (the new default)
                //   * any existing DB upgrading through v5 → fullpath so
                //     the user's current search behaviour is preserved
                //     until they explicitly opt into compact via the UI.
                //     (v2+ all had file_grams with full-path semantics;
                //     v1 had only name-level index but we still default
                //     fullpath for safety — the user can switch.)
                if migration.target == 5 {
                    // `current` == pre-migrate version captured before the
                    // loop; brand-new DB iff it was 0.
                    let defaultMode: IndexMode = (current == 0) ? .compact : .fullpath
                    try exec("INSERT OR IGNORE INTO settings(key, value) VALUES ('\(SettingsKey.indexMode)', '\(defaultMode.rawValue)');")
                }
            }
            try exec("PRAGMA user_version=\(Schema.currentVersion);")
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
        schemaVersion = Schema.currentVersion
    }

    private func backfillFileGrams() throws {
        guard let handle else { return }
        var selectStmt: OpaquePointer?
        let selectSQL = "SELECT id, name_lower, path_lower FROM files;"
        let prepSel = sqlite3_prepare_v2(handle, selectSQL, -1, &selectStmt, nil)
        guard prepSel == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: prepSel, message: msg, sql: selectSQL)
        }
        defer { sqlite3_finalize(selectStmt) }

        var rows: [(Int64, String, String)] = []
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(selectStmt, 0)
            let nameLower = String(cString: sqlite3_column_text(selectStmt, 1))
            let pathLower = String(cString: sqlite3_column_text(selectStmt, 2))
            rows.append((id, nameLower, pathLower))
        }
        guard !rows.isEmpty else { return }

        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT OR IGNORE INTO file_grams(file_id, gram) VALUES (?, ?);"
        let prepIns = sqlite3_prepare_v2(handle, insertSQL, -1, &insertStmt, nil)
        guard prepIns == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: prepIns, message: msg, sql: insertSQL)
        }
        defer { sqlite3_finalize(insertStmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (id, nameLower, pathLower) in rows {
            for gram in Gram.indexGrams(nameLower: nameLower, pathLower: pathLower) {
                sqlite3_reset(insertStmt)
                sqlite3_clear_bindings(insertStmt)
                _ = sqlite3_bind_int64(insertStmt, 1, id)
                _ = sqlite3_bind_text(insertStmt, 2, gram, -1, transient)
                let rc = sqlite3_step(insertStmt)
                if rc != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(handle))
                    throw DatabaseError.stepFailed(code: rc, message: msg, sql: insertSQL)
                }
            }
        }
    }

    /// F1: mirror of `backfillFileGrams` for the new 2-gram index table.
    /// Keeps the two tables populated from the same source of truth (the
    /// `files` table) so a db migrated from v3 → v4 is searchable on the
    /// short-query path without requiring a full re-index.
    private func backfillFileBigrams() throws {
        guard let handle else { return }
        var selectStmt: OpaquePointer?
        let selectSQL = "SELECT id, name_lower, path_lower FROM files;"
        let prepSel = sqlite3_prepare_v2(handle, selectSQL, -1, &selectStmt, nil)
        guard prepSel == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: prepSel, message: msg, sql: selectSQL)
        }
        defer { sqlite3_finalize(selectStmt) }

        var rows: [(Int64, String, String)] = []
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(selectStmt, 0)
            let nameLower = String(cString: sqlite3_column_text(selectStmt, 1))
            let pathLower = String(cString: sqlite3_column_text(selectStmt, 2))
            rows.append((id, nameLower, pathLower))
        }
        guard !rows.isEmpty else { return }

        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT OR IGNORE INTO file_bigrams(file_id, gram) VALUES (?, ?);"
        let prepIns = sqlite3_prepare_v2(handle, insertSQL, -1, &insertStmt, nil)
        guard prepIns == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: prepIns, message: msg, sql: insertSQL)
        }
        defer { sqlite3_finalize(insertStmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (id, nameLower, pathLower) in rows {
            for bigram in Gram.indexBigrams(nameLower: nameLower, pathLower: pathLower) {
                sqlite3_reset(insertStmt)
                sqlite3_clear_bindings(insertStmt)
                _ = sqlite3_bind_int64(insertStmt, 1, id)
                _ = sqlite3_bind_text(insertStmt, 2, bigram, -1, transient)
                let rc = sqlite3_step(insertStmt)
                if rc != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(handle))
                    throw DatabaseError.stepFailed(code: rc, message: msg, sql: insertSQL)
                }
            }
        }
    }

    public func exec(_ sql: String) throws {
        guard let handle else { return }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError.stepFailed(code: rc, message: message, sql: sql)
        }
    }

    public func readUserVersion() throws -> Int32 {
        guard let handle else { return 0 }
        var stmt: OpaquePointer?
        let sql = "PRAGMA user_version;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0)
        }
        return 0
    }

    public func scalarInt(_ sql: String) throws -> Int64? {
        guard let handle else { return nil }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let step = sqlite3_step(stmt)
        guard step == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    public func registerRoot(path: String) throws -> Int64 {
        defer { invalidateRootsCache() }
        guard let handle else { throw DatabaseError.openFailed(code: 0, message: "closed") }
        var stmt: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO roots(path, enabled) VALUES (?, 1);"
        let prepRC = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard prepRC == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: prepRC, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bindRC = sqlite3_bind_text(stmt, 1, path, -1, transient)
        if bindRC != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.bindFailed(code: bindRC, message: msg)
        }
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
        return try rootId(path: path) ?? 0
    }

    public func rootId(path: String) throws -> Int64? {
        guard let handle else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT id FROM roots WHERE path = ?;"
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

    public func countRows(in table: String) throws -> Int64 {
        return try scalarInt("SELECT COUNT(*) FROM \(table);") ?? 0
    }

    public func fileExists(path: String) throws -> Bool {
        guard let handle else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM files WHERE path = ? LIMIT 1;"
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
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// G3: helper for the upsert-style index pattern used in insertFiles.
    /// Takes a pre-prepared (delete, insert) pair and writes each value
    /// for the given file_id after clearing any existing rows. Keeps
    /// the main insertFiles body readable across the 3-way
    /// fullpath/compact split.
    static func clearAndWriteIndex(
        fileId: Int64,
        values: Set<String>,
        deleteStmt: OpaquePointer?,
        insertStmt: OpaquePointer?,
        deleteSQL: String,
        insertSQL: String,
        handle: OpaquePointer,
        transient: sqlite3_destructor_type
    ) throws {
        guard let deleteStmt, let insertStmt else { return }
        sqlite3_reset(deleteStmt)
        sqlite3_clear_bindings(deleteStmt)
        _ = sqlite3_bind_int64(deleteStmt, 1, fileId)
        let delRC = sqlite3_step(deleteStmt)
        if delRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: delRC, message: msg, sql: deleteSQL)
        }
        for value in values {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            _ = sqlite3_bind_int64(insertStmt, 1, fileId)
            _ = sqlite3_bind_text(insertStmt, 2, value, -1, transient)
            let insRC = sqlite3_step(insertStmt)
            if insRC != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw DatabaseError.stepFailed(code: insRC, message: msg, sql: insertSQL)
            }
        }
    }

    public func insertFiles(_ rows: [FileRow]) throws {
        guard !rows.isEmpty else { return }
        guard let handle else { throw DatabaseError.openFailed(code: 0, message: "closed") }

        try exec("BEGIN IMMEDIATE;")
        do {
            let upsertSQL = """
            INSERT INTO files(path, path_lower, name, name_lower, is_dir, size, mtime)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                path_lower=excluded.path_lower,
                name=excluded.name,
                name_lower=excluded.name_lower,
                is_dir=excluded.is_dir,
                size=excluded.size,
                mtime=excluded.mtime;
            """
            let selectIdSQL = "SELECT id FROM files WHERE path = ?;"
            // v4 fullpath-mode tables
            let deleteGramsSQL = "DELETE FROM file_grams WHERE file_id = ?;"
            let insertGramSQL = "INSERT OR IGNORE INTO file_grams(file_id, gram) VALUES (?, ?);"
            let deleteBigramsSQL = "DELETE FROM file_bigrams WHERE file_id = ?;"
            let insertBigramSQL = "INSERT OR IGNORE INTO file_bigrams(file_id, gram) VALUES (?, ?);"
            // G3 v5 compact-mode tables
            let deleteNameGramsSQL = "DELETE FROM file_name_grams WHERE file_id = ?;"
            let insertNameGramSQL = "INSERT OR IGNORE INTO file_name_grams(file_id, gram) VALUES (?, ?);"
            let deleteNameBigramsSQL = "DELETE FROM file_name_bigrams WHERE file_id = ?;"
            let insertNameBigramSQL = "INSERT OR IGNORE INTO file_name_bigrams(file_id, gram) VALUES (?, ?);"
            let deletePathSegSQL = "DELETE FROM file_path_segments WHERE file_id = ?;"
            let insertPathSegSQL = "INSERT OR IGNORE INTO file_path_segments(file_id, segment) VALUES (?, ?);"

            // Read index_mode once per batch. The F1 settings cache
            // makes this essentially free.
            let indexMode: IndexMode = (try? getIndexMode()) ?? .compact

            var upsert: OpaquePointer?
            var selectId: OpaquePointer?
            var deleteGrams: OpaquePointer?
            var insertGram: OpaquePointer?
            var deleteBigrams: OpaquePointer?
            var insertBigram: OpaquePointer?
            var deleteNameGrams: OpaquePointer?
            var insertNameGram: OpaquePointer?
            var deleteNameBigrams: OpaquePointer?
            var insertNameBigram: OpaquePointer?
            var deletePathSeg: OpaquePointer?
            var insertPathSeg: OpaquePointer?

            let prep: (String, UnsafeMutablePointer<OpaquePointer?>) throws -> Void = { sql, ptr in
                let rc = sqlite3_prepare_v2(handle, sql, -1, ptr, nil)
                guard rc == SQLITE_OK else {
                    let msg = String(cString: sqlite3_errmsg(handle))
                    throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
                }
            }
            try prep(upsertSQL, &upsert)
            try prep(selectIdSQL, &selectId)
            // Only prepare the statements we're going to use. v4 tables
            // remain present after v5 migration, so fullpath mode keeps
            // writing to them without any schema change.
            if indexMode == .fullpath {
                try prep(deleteGramsSQL, &deleteGrams)
                try prep(insertGramSQL, &insertGram)
                try prep(deleteBigramsSQL, &deleteBigrams)
                try prep(insertBigramSQL, &insertBigram)
            } else {
                try prep(deleteNameGramsSQL, &deleteNameGrams)
                try prep(insertNameGramSQL, &insertNameGram)
                try prep(deleteNameBigramsSQL, &deleteNameBigrams)
                try prep(insertNameBigramSQL, &insertNameBigram)
                try prep(deletePathSegSQL, &deletePathSeg)
                try prep(insertPathSegSQL, &insertPathSeg)
            }
            defer {
                sqlite3_finalize(upsert)
                sqlite3_finalize(selectId)
                sqlite3_finalize(deleteGrams)
                sqlite3_finalize(insertGram)
                sqlite3_finalize(deleteBigrams)
                sqlite3_finalize(insertBigram)
                sqlite3_finalize(deleteNameGrams)
                sqlite3_finalize(insertNameGram)
                sqlite3_finalize(deleteNameBigrams)
                sqlite3_finalize(insertNameBigram)
                sqlite3_finalize(deletePathSeg)
                sqlite3_finalize(insertPathSeg)
            }

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

            for row in rows {
                sqlite3_reset(upsert)
                sqlite3_clear_bindings(upsert)
                _ = sqlite3_bind_text(upsert, 1, row.path, -1, transient)
                _ = sqlite3_bind_text(upsert, 2, row.pathLower, -1, transient)
                _ = sqlite3_bind_text(upsert, 3, row.name, -1, transient)
                _ = sqlite3_bind_text(upsert, 4, row.nameLower, -1, transient)
                _ = sqlite3_bind_int(upsert, 5, row.isDir ? 1 : 0)
                _ = sqlite3_bind_int64(upsert, 6, row.size)
                _ = sqlite3_bind_int64(upsert, 7, row.mtime)
                let stepRC = sqlite3_step(upsert)
                if stepRC != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(handle))
                    throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: upsertSQL)
                }

                // Resolve file id (rowid) for grams.
                sqlite3_reset(selectId)
                sqlite3_clear_bindings(selectId)
                _ = sqlite3_bind_text(selectId, 1, row.path, -1, transient)
                guard sqlite3_step(selectId) == SQLITE_ROW else {
                    let msg = String(cString: sqlite3_errmsg(handle))
                    throw DatabaseError.stepFailed(code: 0, message: "cannot locate row for \(row.path): \(msg)", sql: selectIdSQL)
                }
                let fileId = sqlite3_column_int64(selectId, 0)

                // G3: write the index tables that match the current mode.
                // In fullpath mode we write file_grams + file_bigrams (the
                // F1 behaviour, with full path included in the sliding
                // window). In compact mode we write file_name_grams +
                // file_name_bigrams (basename only) plus file_path_segments
                // for `path:<token>` queries.
                if indexMode == .fullpath {
                    try Database.clearAndWriteIndex(
                        fileId: fileId,
                        values: Gram.indexGrams(nameLower: row.nameLower, pathLower: row.pathLower),
                        deleteStmt: deleteGrams, insertStmt: insertGram,
                        deleteSQL: deleteGramsSQL, insertSQL: insertGramSQL,
                        handle: handle, transient: transient)
                    try Database.clearAndWriteIndex(
                        fileId: fileId,
                        values: Gram.indexBigrams(nameLower: row.nameLower, pathLower: row.pathLower),
                        deleteStmt: deleteBigrams, insertStmt: insertBigram,
                        deleteSQL: deleteBigramsSQL, insertSQL: insertBigramSQL,
                        handle: handle, transient: transient)
                } else {
                    try Database.clearAndWriteIndex(
                        fileId: fileId,
                        values: Gram.nameGrams(nameLower: row.nameLower),
                        deleteStmt: deleteNameGrams, insertStmt: insertNameGram,
                        deleteSQL: deleteNameGramsSQL, insertSQL: insertNameGramSQL,
                        handle: handle, transient: transient)
                    try Database.clearAndWriteIndex(
                        fileId: fileId,
                        values: Gram.nameBigrams(nameLower: row.nameLower),
                        deleteStmt: deleteNameBigrams, insertStmt: insertNameBigram,
                        deleteSQL: deleteNameBigramsSQL, insertSQL: insertNameBigramSQL,
                        handle: handle, transient: transient)
                    try Database.clearAndWriteIndex(
                        fileId: fileId,
                        values: Gram.pathSegments(pathLower: row.pathLower),
                        deleteStmt: deletePathSeg, insertStmt: insertPathSeg,
                        deleteSQL: deletePathSegSQL, insertSQL: insertPathSegSQL,
                        handle: handle, transient: transient)
                }
            }

            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    public func clearFiles(underRoot root: String) throws {
        guard let handle else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM files WHERE path = ? OR path LIKE ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let prefix = root.hasSuffix("/") ? root + "%" : root + "/%"
        _ = sqlite3_bind_text(stmt, 1, root, -1, transient)
        _ = sqlite3_bind_text(stmt, 2, prefix, -1, transient)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
    }

    /// Delete rows whose `path` equals `p` or is a descendant of `p`
    /// (i.e. starts with `p + "/"`). Returns the number of rows actually
    /// removed (via `sqlite3_changes`), so callers can tell deletion apart
    /// from a no-op.
    @discardableResult
    public func deleteFiles(atOrUnderPath p: String) throws -> Int {
        guard let handle else { return 0 }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM files WHERE path = ? OR path LIKE ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let prefix = p.hasSuffix("/") ? p + "%" : p + "/%"
        _ = sqlite3_bind_text(stmt, 1, p, -1, transient)
        _ = sqlite3_bind_text(stmt, 2, prefix, -1, transient)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
        return Int(sqlite3_changes(handle))
    }

    /// Return known paths at or under `p` (self + descendants). Used by the
    /// incremental rescan to diff DB state against filesystem state.
    public func pathsAtOrUnder(_ p: String) throws -> [String] {
        guard let handle else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT path FROM files WHERE path = ? OR path LIKE ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let prefix = p.hasSuffix("/") ? p + "%" : p + "/%"
        _ = sqlite3_bind_text(stmt, 1, p, -1, transient)
        _ = sqlite3_bind_text(stmt, 2, prefix, -1, transient)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return out
    }

    // MARK: - P5 roots management

    public func listRoots() throws -> [RootRow] {
        // F1 hot path: memoise roots across back-to-back search calls. Writes
        // (registerRoot / removeRoot / setRootEnabled) invalidate. Reads are
        // guarded by the same lock; the snapshot itself is a Swift array of
        // value types so callers mutating their copy cannot corrupt the cache.
        cacheLock.lock()
        if let hit = rootsCached {
            rootsCacheHits += 1
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        guard let handle else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, path, enabled FROM roots ORDER BY path;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        var out: [RootRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(RootRow(
                id: sqlite3_column_int64(stmt, 0),
                path: String(cString: sqlite3_column_text(stmt, 1)),
                enabled: sqlite3_column_int(stmt, 2) != 0
            ))
        }
        cacheLock.lock()
        rootsCached = out
        rootsCacheMisses += 1
        cacheLock.unlock()
        return out
    }

    public func setRootEnabled(id: Int64, enabled: Bool) throws {
        defer { invalidateRootsCache() }
        guard let handle else { return }
        var stmt: OpaquePointer?
        let sql = "UPDATE roots SET enabled = ? WHERE id = ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_bind_int(stmt, 1, enabled ? 1 : 0)
        _ = sqlite3_bind_int64(stmt, 2, id)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
    }

    /// Remove a root AND prune every file row that lives under that root's path.
    /// Disabled roots are still tracked in the roots table, but removal deletes the
    /// registration entirely — caller should use setRootEnabled for reversible pause.
    public func removeRoot(id: Int64) throws {
        defer { invalidateRootsCache() }
        guard let handle else { return }
        // Look up the path first so we can clean up files under it.
        var pathStmt: OpaquePointer?
        let selSQL = "SELECT path FROM roots WHERE id = ?;"
        let selRC = sqlite3_prepare_v2(handle, selSQL, -1, &pathStmt, nil)
        guard selRC == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: selRC, message: msg, sql: selSQL)
        }
        _ = sqlite3_bind_int64(pathStmt, 1, id)
        var pathOpt: String? = nil
        if sqlite3_step(pathStmt) == SQLITE_ROW {
            pathOpt = String(cString: sqlite3_column_text(pathStmt, 0))
        }
        sqlite3_finalize(pathStmt)
        guard let path = pathOpt else { return }

        try exec("BEGIN IMMEDIATE;")
        do {
            _ = try deleteFiles(atOrUnderPath: path)
            var delStmt: OpaquePointer?
            let delSQL = "DELETE FROM roots WHERE id = ?;"
            let prep = sqlite3_prepare_v2(handle, delSQL, -1, &delStmt, nil)
            guard prep == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw DatabaseError.prepareFailed(code: prep, message: msg, sql: delSQL)
            }
            _ = sqlite3_bind_int64(delStmt, 1, id)
            let stepRC = sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
            if stepRC != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: delSQL)
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - P5 excludes management

    public func listExcludes() throws -> [ExcludeRow] {
        guard let handle else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT id, pattern FROM excludes ORDER BY pattern;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        var out: [ExcludeRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(ExcludeRow(
                id: sqlite3_column_int64(stmt, 0),
                pattern: String(cString: sqlite3_column_text(stmt, 1))
            ))
        }
        return out
    }

    @discardableResult
    public func addExclude(pattern: String) throws -> Int64 {
        guard let handle else { throw DatabaseError.openFailed(code: 0, message: "closed") }
        var stmt: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO excludes(pattern) VALUES (?);"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, pattern, -1, transient)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
        // Look up id (INSERT OR IGNORE may have hit existing row).
        var sel: OpaquePointer?
        defer { sqlite3_finalize(sel) }
        _ = sqlite3_prepare_v2(handle, "SELECT id FROM excludes WHERE pattern = ?;", -1, &sel, nil)
        _ = sqlite3_bind_text(sel, 1, pattern, -1, transient)
        if sqlite3_step(sel) == SQLITE_ROW {
            return sqlite3_column_int64(sel, 0)
        }
        return 0
    }

    public func removeExclude(id: Int64) throws {
        guard let handle else { return }
        var stmt: OpaquePointer?
        let sql = "DELETE FROM excludes WHERE id = ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        _ = sqlite3_bind_int64(stmt, 1, id)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
    }

    /// Delete every file row under one exclude path (called when user promotes a
    /// previously indexed directory to an excluded one).
    @discardableResult
    public func deleteFilesMatchingExclude(_ pattern: String) throws -> Int {
        return try deleteFiles(atOrUnderPath: Indexer.canonicalize(path: pattern))
    }

    // MARK: - P5 settings key/value store

    public func getSetting(_ key: String) throws -> String? {
        // F1 hot path: memoise the occasional string read. Callers like the
        // search box read `search_limit` on every keystroke; without this
        // cache that was a full prepare / step / finalize cycle each time.
        cacheLock.lock()
        if let hit = settingsCached[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        guard let handle else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM settings WHERE key = ?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, key, -1, transient)
        let value: String?
        if sqlite3_step(stmt) == SQLITE_ROW {
            value = String(cString: sqlite3_column_text(stmt, 0))
        } else {
            value = nil
        }
        cacheLock.lock()
        settingsCached[key] = value
        cacheLock.unlock()
        return value
    }

    public func setSetting(_ key: String, value: String) throws {
        defer { invalidateSettingsCache(key: key) }
        guard let handle else { return }
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO settings(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = sqlite3_bind_text(stmt, 1, key, -1, transient)
        _ = sqlite3_bind_text(stmt, 2, value, -1, transient)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.stepFailed(code: stepRC, message: msg, sql: sql)
        }
    }

    public func tableExists(_ name: String) throws -> Bool {
        guard let handle else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?;"
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bindRC = sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        if bindRC != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.bindFailed(code: bindRC, message: msg)
        }
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
