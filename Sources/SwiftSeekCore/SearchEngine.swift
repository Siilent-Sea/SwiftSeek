import Foundation
import CSQLite

public struct SearchResult: Equatable {
    public let path: String
    public let name: String
    public let isDir: Bool
    public let size: Int64
    public let mtime: Int64
    public let score: Int

    public init(path: String,
                name: String,
                isDir: Bool,
                size: Int64,
                mtime: Int64,
                score: Int) {
        self.path = path
        self.name = name
        self.isDir = isDir
        self.size = size
        self.mtime = mtime
        self.score = score
    }
}

public enum SearchError: Error, CustomStringConvertible {
    case closedDatabase
    case prepareFailed(Int32, String, String)
    case stepFailed(Int32, String, String)

    public var description: String {
        switch self {
        case .closedDatabase:
            return "search: database closed"
        case let .prepareFailed(code, message, sql):
            return "search prepare failed (\(code)): \(message) sql=\(sql)"
        case let .stepFailed(code, message, sql):
            return "search step failed (\(code)): \(message) sql=\(sql)"
        }
    }
}

public final class SearchEngine {
    public struct Options {
        public var limit: Int
        public var candidateMultiplier: Int

        public init(limit: Int = 100, candidateMultiplier: Int = 4) {
            self.limit = limit
            self.candidateMultiplier = candidateMultiplier
        }
    }

    private struct Row {
        let path: String
        let name: String
        let isDir: Bool
        let size: Int64
        let mtime: Int64
        let nameLower: String
        let pathLower: String
    }

    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    // MARK: - Query normalization

    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "" }
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    // MARK: - Search

    public func search(_ rawQuery: String, options: Options = .init()) throws -> [SearchResult] {
        let q = SearchEngine.normalize(rawQuery)
        guard !q.isEmpty else { return [] }
        let qLen = q.count
        let rows: [Row]
        if qLen < Gram.size {
            rows = try shortQueryCandidates(q, limit: options.limit * options.candidateMultiplier)
        } else {
            rows = try gramCandidates(q, limit: options.limit * options.candidateMultiplier)
        }
        // P5 root-enabled filter: drop candidates whose path is not covered by
        // any enabled root. Rationale: the UI lets the user flip `enabled` on
        // `roots` rows without clearing the indexed data under them (reversible
        // pause). Without this gate, a disabled root would still surface
        // results — contradicting P5's "UI changed, index scope changed" rule.
        // Empty result from `listRoots` means a fresh DB with no indexing yet,
        // so the filter naturally yields no hits, which matches expectations.
        let allRoots: [RootRow]
        do {
            allRoots = try database.listRoots()
        } catch {
            // Don't silently show old results when the roots table is
            // unreadable — fall through to legacy behaviour (no filter) but
            // surface the cause so the user can investigate via Console.app.
            NSLog("SwiftSeek: SearchEngine listRoots failed, falling back to unfiltered search: \(error)")
            allRoots = []
        }
        let enabledRoots = allRoots.filter { $0.enabled }.map { $0.path }
        let filtered: [Row]
        if allRoots.isEmpty {
            // Pre-P5 / unconfigured DBs that still have files but no `roots` row:
            // don't silently suppress, keep legacy behaviour.
            filtered = rows
        } else {
            filtered = rows.filter { SearchEngine.pathUnderAnyRoot($0.path, roots: enabledRoots) }
        }
        let scored = rank(rows: filtered, query: q)
        return Array(scored.prefix(options.limit))
    }

    /// True iff `path` equals one of `roots` or is a descendant (shares a `/`
    /// boundary). Empty `roots` returns false — caller must handle the
    /// "no enabled roots" case explicitly, since that usually means the user
    /// disabled everything.
    public static func pathUnderAnyRoot(_ path: String, roots: [String]) -> Bool {
        for r in roots {
            if path == r { return true }
            if path.hasPrefix(r + "/") { return true }
        }
        return false
    }

    // MARK: - Candidate retrieval

    private func shortQueryCandidates(_ q: String, limit: Int) throws -> [Row] {
        // Short queries fall back to LIKE on name_lower / path_lower. Still bounded by limit.
        let sql = """
        SELECT path, name, is_dir, size, mtime, name_lower, path_lower FROM files
        WHERE name_lower LIKE ? OR path_lower LIKE ?
        LIMIT ?;
        """
        let like = "%\(q)%"
        return try executeQuery(sql) { stmt, transient in
            _ = sqlite3_bind_text(stmt, 1, like, -1, transient)
            _ = sqlite3_bind_text(stmt, 2, like, -1, transient)
            _ = sqlite3_bind_int64(stmt, 3, Int64(limit))
        }
    }

    private func gramCandidates(_ q: String, limit: Int) throws -> [Row] {
        let grams = Array(Gram.grams(of: q))
        guard !grams.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: grams.count).joined(separator: ",")
        let sql = """
        SELECT f.path, f.name, f.is_dir, f.size, f.mtime, f.name_lower, f.path_lower
        FROM file_grams fg
        JOIN files f ON f.id = fg.file_id
        WHERE fg.gram IN (\(placeholders))
        GROUP BY fg.file_id
        HAVING COUNT(DISTINCT fg.gram) = ?
        LIMIT ?;
        """
        let rows = try executeQuery(sql) { stmt, transient in
            var idx: Int32 = 1
            for g in grams {
                _ = sqlite3_bind_text(stmt, idx, g, -1, transient)
                idx += 1
            }
            _ = sqlite3_bind_int64(stmt, idx, Int64(grams.count))
            idx += 1
            _ = sqlite3_bind_int64(stmt, idx, Int64(limit))
        }
        // The gram gate can admit false positives (grams all present but not contiguous),
        // so we still enforce a literal substring match on either name_lower or path_lower.
        return rows.filter { $0.nameLower.contains(q) || $0.pathLower.contains(q) }
    }

    private func executeQuery(_ sql: String,
                              bind: (OpaquePointer?, sqlite3_destructor_type) -> Void) throws -> [Row] {
        guard let handle = database.rawHandle else { throw SearchError.closedDatabase }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw SearchError.prepareFailed(rc, msg, sql)
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        bind(stmt, transient)

        var out: [Row] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw SearchError.stepFailed(step, msg, sql)
            }
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let isDir = sqlite3_column_int(stmt, 2) != 0
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = sqlite3_column_int64(stmt, 4)
            let nameLower = String(cString: sqlite3_column_text(stmt, 5))
            let pathLower = String(cString: sqlite3_column_text(stmt, 6))
            out.append(Row(path: path,
                           name: name,
                           isDir: isDir,
                           size: size,
                           mtime: mtime,
                           nameLower: nameLower,
                           pathLower: pathLower))
        }
        return out
    }

    // MARK: - Scoring

    /// Score bands (higher is better):
    ///   1000 filename exact match
    ///    800 filename starts with query
    ///    500 filename contains query (not at start)
    ///    200 path (but not filename) contains query
    /// Ties break on shorter path, then alphabetical path.
    static func score(query q: String, nameLower: String, pathLower: String) -> Int {
        if nameLower == q { return 1000 }
        if nameLower.hasPrefix(q) { return 800 }
        if nameLower.contains(q) { return 500 }
        if pathLower.contains(q) { return 200 }
        return 0
    }

    private func rank(rows: [Row], query q: String) -> [SearchResult] {
        let scored: [SearchResult] = rows.compactMap { row in
            let s = SearchEngine.score(query: q, nameLower: row.nameLower, pathLower: row.pathLower)
            guard s > 0 else { return nil }
            return SearchResult(path: row.path,
                                name: row.name,
                                isDir: row.isDir,
                                size: row.size,
                                mtime: row.mtime,
                                score: s)
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }
    }
}
