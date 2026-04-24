import Foundation
import CSQLite

/// G1 — `Database` footprint observability.
///
/// This extension is deliberately side-effect free: every method is read-only,
/// never mutates schema, never writes to the `settings` table. Callers that
/// want to cause mutation (checkpoint / optimize / VACUUM) go through the
/// explicit maintenance helpers below, each of which is documented with its
/// failure mode and user-visible cost.

public struct DatabaseStats: Equatable, Sendable {
    // File system sizes (bytes, -1 if unknown).
    public var mainFileBytes: Int64
    public var walFileBytes: Int64
    public var shmFileBytes: Int64

    // SQLite page info.
    public var pageCount: Int64
    public var pageSize: Int64

    // Row counts for core / footprint-heavy tables. -1 when the table is
    // missing on the current schema (old v1 DB, partially-migrated fixture,
    // etc.).
    public var filesRowCount: Int64
    public var fileGramsRowCount: Int64
    public var fileBigramsRowCount: Int64
    public var rootsRowCount: Int64
    public var excludesRowCount: Int64
    public var settingsRowCount: Int64
    /// H4 — number of `file_usage` rows. -1 when the table is missing
    /// (pre-v6 DB). Surfaced in CLI + Settings → 维护 tab so users can
    /// see whether usage data is present and (post-clear) confirm 0.
    public var fileUsageRowCount: Int64

    // Derived averages. `nil` when files is 0 / missing so UIs can show
    // "—" cleanly instead of a divide-by-zero.
    public var avgGramsPerFile: Double?
    public var avgBigramsPerFile: Double?

    // `dbstat` virtual-table per-table payload. Nil when dbstat was not
    // available at build time (the system SQLite on macOS typically
    // exposes it as `SQLITE_ENABLE_DBSTAT_VTAB`; we probe at runtime).
    public var perTable: [PerTable]?

    public struct PerTable: Equatable, Sendable {
        public var name: String
        /// Total bytes this table occupies (pages × pageSize when derived
        /// from `dbstat`, otherwise an estimate).
        public var approxBytes: Int64
        public var pageCount: Int64

        public init(name: String, approxBytes: Int64, pageCount: Int64) {
            self.name = name
            self.approxBytes = approxBytes
            self.pageCount = pageCount
        }
    }

    public init(mainFileBytes: Int64 = -1,
                walFileBytes: Int64 = -1,
                shmFileBytes: Int64 = -1,
                pageCount: Int64 = -1,
                pageSize: Int64 = -1,
                filesRowCount: Int64 = -1,
                fileGramsRowCount: Int64 = -1,
                fileBigramsRowCount: Int64 = -1,
                rootsRowCount: Int64 = -1,
                excludesRowCount: Int64 = -1,
                settingsRowCount: Int64 = -1,
                fileUsageRowCount: Int64 = -1,
                avgGramsPerFile: Double? = nil,
                avgBigramsPerFile: Double? = nil,
                perTable: [PerTable]? = nil) {
        self.mainFileBytes = mainFileBytes
        self.walFileBytes = walFileBytes
        self.shmFileBytes = shmFileBytes
        self.pageCount = pageCount
        self.pageSize = pageSize
        self.filesRowCount = filesRowCount
        self.fileGramsRowCount = fileGramsRowCount
        self.fileBigramsRowCount = fileBigramsRowCount
        self.rootsRowCount = rootsRowCount
        self.excludesRowCount = excludesRowCount
        self.settingsRowCount = settingsRowCount
        self.fileUsageRowCount = fileUsageRowCount
        self.avgGramsPerFile = avgGramsPerFile
        self.avgBigramsPerFile = avgBigramsPerFile
        self.perTable = perTable
    }
}

public extension Database {
    /// Compute a stats snapshot. Every sub-probe is wrapped in its own
    /// do/catch so one unreadable field never prevents the rest of the
    /// report from rendering — callers (CLI + UI) always get a usable
    /// report, even on a partially-migrated DB.
    func computeStats() -> DatabaseStats {
        var stats = DatabaseStats()

        // --- File system sizes -------------------------------------------
        let fm = FileManager.default
        let mainURL = url
        let walURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + "-wal")
        let shmURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + "-shm")
        stats.mainFileBytes = DatabaseStats.fileBytes(at: mainURL.path, fm: fm)
        stats.walFileBytes  = DatabaseStats.fileBytes(at: walURL.path, fm: fm)
        stats.shmFileBytes  = DatabaseStats.fileBytes(at: shmURL.path, fm: fm)

        // --- Page info ---------------------------------------------------
        stats.pageCount = (try? scalarInt("PRAGMA page_count;")) ?? -1
        stats.pageSize  = (try? scalarInt("PRAGMA page_size;")) ?? -1

        // --- Row counts per known table ---------------------------------
        stats.filesRowCount       = countIfExists(table: "files")
        stats.fileGramsRowCount   = countIfExists(table: "file_grams")
        stats.fileBigramsRowCount = countIfExists(table: "file_bigrams")
        stats.rootsRowCount       = countIfExists(table: "roots")
        stats.excludesRowCount    = countIfExists(table: "excludes")
        stats.settingsRowCount    = countIfExists(table: "settings")
        stats.fileUsageRowCount   = countIfExists(table: "file_usage")

        // --- Derived averages -------------------------------------------
        if stats.filesRowCount > 0 {
            if stats.fileGramsRowCount >= 0 {
                stats.avgGramsPerFile = Double(stats.fileGramsRowCount) / Double(stats.filesRowCount)
            }
            if stats.fileBigramsRowCount >= 0 {
                stats.avgBigramsPerFile = Double(stats.fileBigramsRowCount) / Double(stats.filesRowCount)
            }
        }

        // --- Per-table footprint via dbstat (probed + fallback) ---------
        stats.perTable = perTableBytesViaDBStat() ?? perTableBytesFallback()

        return stats
    }

    // MARK: - Internals

    /// Probe `dbstat` once; return nil if the virtual table is not
    /// available on this SQLite build (the call to
    /// `SELECT ... FROM dbstat` will fail with a clean error we can
    /// classify as "unavailable"). Callers should fall through to the
    /// row-count estimate.
    private func perTableBytesViaDBStat() -> [DatabaseStats.PerTable]? {
        // Any clean failure → treat as "dbstat not available" and fall back.
        // We don't want to noise up the log for a feature that's genuinely
        // optional at this layer.
        guard let rows = try? dbstatRows() else { return nil }
        guard !rows.isEmpty else { return nil }
        return rows
    }

    private func dbstatRows() throws -> [DatabaseStats.PerTable] {
        guard let handle = rawHandle else { return [] }
        // Schema: dbstat(name, pagesize, ...). We aggregate per `name`
        // (the sqlite_master object name) into page count × pagesize.
        let sql = """
        SELECT name, COUNT(*) AS pages, SUM(pgsize) AS bytes
        FROM dbstat
        GROUP BY name
        ORDER BY bytes DESC;
        """
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            // Typical failure: "no such table: dbstat" when the build
            // is missing `SQLITE_ENABLE_DBSTAT_VTAB`. Surface as thrown
            // so the caller's try? turns it into nil; do NOT NSLog.
            let msg = String(cString: sqlite3_errmsg(handle))
            throw DatabaseError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        var out: [DatabaseStats.PerTable] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let pages = sqlite3_column_int64(stmt, 1)
            let bytes = sqlite3_column_int64(stmt, 2)
            out.append(.init(name: name,
                             approxBytes: bytes,
                             pageCount: pages))
        }
        return out
    }

    /// Fallback per-table estimate used when `dbstat` is unavailable.
    /// We can't know actual bytes, but we can still show row counts
    /// with a coarse "bytes" column filled with -1 so the UI renders
    /// "—" instead of a misleading number.
    private func perTableBytesFallback() -> [DatabaseStats.PerTable] {
        let names = ["files", "file_grams", "file_bigrams",
                     "roots", "excludes", "settings", "file_usage"]
        var out: [DatabaseStats.PerTable] = []
        for name in names {
            let rows = countIfExists(table: name)
            if rows < 0 { continue } // skip missing tables
            out.append(.init(name: name, approxBytes: -1, pageCount: rows))
        }
        return out
    }

    private func countIfExists(table: String) -> Int64 {
        guard (try? tableExists(table)) == true else { return -1 }
        return (try? countRows(in: table)) ?? -1
    }
}

// MARK: - G1 maintenance ops

public enum MaintenanceKind: String, Sendable {
    case checkpoint  // PRAGMA wal_checkpoint(TRUNCATE)
    case optimize    // PRAGMA optimize
    case vacuum      // VACUUM
}

public struct MaintenanceResult: Equatable, Sendable {
    public var kind: MaintenanceKind
    public var durationSeconds: TimeInterval
    /// Raw message from SQLite on failure, nil on success.
    public var error: String?

    public init(kind: MaintenanceKind, durationSeconds: TimeInterval, error: String? = nil) {
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.error = error
    }
}

public extension Database {
    /// Run a single maintenance operation synchronously. The caller is
    /// responsible for dispatching to a background queue if needed —
    /// VACUUM on a large DB can take minutes and must never be scheduled
    /// on the main thread.
    @discardableResult
    func runMaintenance(_ kind: MaintenanceKind) -> MaintenanceResult {
        let start = Date()
        let sql: String
        switch kind {
        case .checkpoint: sql = "PRAGMA wal_checkpoint(TRUNCATE);"
        case .optimize:   sql = "PRAGMA optimize;"
        case .vacuum:     sql = "VACUUM;"
        }
        do {
            try exec(sql)
            // F1 caches may point at stale row counts post-VACUUM, but
            // cached `Int64` row counts aren't stored in our caches; we
            // only cache roots + settings, both unaffected by these ops.
            // Still, invalidate to be safe — cheap and avoids surprises.
            invalidateRootsCache()
            invalidateSettingsCache()
            return .init(kind: kind,
                         durationSeconds: Date().timeIntervalSince(start))
        } catch {
            NSLog("SwiftSeek: maintenance \(kind.rawValue) failed: \(error)")
            return .init(kind: kind,
                         durationSeconds: Date().timeIntervalSince(start),
                         error: "\(error)")
        }
    }
}

// MARK: - Human-friendly formatting helpers (shared by CLI + UI)

public extension DatabaseStats {
    /// Bytes → "3.4 GB" / "1.2 MB" style, or "—" when unknown (-1).
    static func humanBytes(_ n: Int64) -> String {
        if n < 0 { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    /// Int64 count → "1,234,567" or "—" for -1.
    static func humanCount(_ n: Int64) -> String {
        if n < 0 { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Double average → "40.12" or "—" for nil.
    static func humanAvg(_ d: Double?) -> String {
        guard let d else { return "—" }
        return String(format: "%.2f", d)
    }

    static func fileBytes(at path: String, fm: FileManager) -> Int64 {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return -1 }
        return size.int64Value
    }
}
