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

/// E2 result sort keys. Default is `.score` which reproduces the ranking
/// order returned by `SearchEngine.search()`. Other keys re-order the same
/// result set without re-running the query. Ties break on shorter path then
/// alphabetical path so the order is total and reproducible.
public enum SearchSortKey: String, Sendable {
    case score
    case name
    case path
    case mtime
    case size
}

public struct SearchSortOrder: Equatable, Sendable {
    public var key: SearchSortKey
    public var ascending: Bool

    public init(key: SearchSortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// Default order: score descending. Matches the native ranking order
    /// returned by `SearchEngine.search()`.
    public static let scoreDescending = SearchSortOrder(key: .score, ascending: false)
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

        public init(limit: Int = SearchLimitBounds.defaultValue,
                    candidateMultiplier: Int = 4) {
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

    // MARK: - Query normalization / tokenization

    /// Normalize query: trim, lowercase, collapse internal whitespace runs into
    /// single spaces. Preserves intra-token `/` so path-shaped queries like
    /// `docs/alpha` still work.
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "" }
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    /// E1 multi-word AND: split normalized query into whitespace-separated
    /// tokens. Each token is required to match (AND), not any-of.
    public static func tokenize(_ raw: String) -> [String] {
        let n = normalize(raw)
        if n.isEmpty { return [] }
        return n.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
    }

    // MARK: - Search

    public func search(_ rawQuery: String, options: Options = .init()) throws -> [SearchResult] {
        let tokens = SearchEngine.tokenize(rawQuery)
        guard !tokens.isEmpty else { return [] }

        let candidatePool = max(options.limit * options.candidateMultiplier, options.limit)
        let rows = try candidates(tokens: tokens, limit: candidatePool)

        // P5 root-enabled filter: drop candidates whose path is not covered by
        // any enabled root. Pre-P5 / unconfigured DBs (empty `roots` table) fall
        // through to legacy unfiltered behaviour so existing test DBs keep
        // working without forced migration.
        let allRoots: [RootRow]
        do {
            allRoots = try database.listRoots()
        } catch {
            NSLog("SwiftSeek: SearchEngine listRoots failed, falling back to unfiltered search: \(error)")
            allRoots = []
        }
        let enabledRoots = allRoots.filter { $0.enabled }.map { $0.path }
        let filtered: [Row]
        if allRoots.isEmpty {
            filtered = rows
        } else {
            filtered = rows.filter { SearchEngine.pathUnderAnyRoot($0.path, roots: enabledRoots) }
        }
        let scored = rank(rows: filtered, tokens: tokens)
        return Array(scored.prefix(options.limit))
    }

    /// True iff `path` equals one of `roots` or is a descendant (shares a `/`
    /// boundary). Empty `roots` returns false — caller must handle the
    /// "no enabled roots" case explicitly.
    public static func pathUnderAnyRoot(_ path: String, roots: [String]) -> Bool {
        for r in roots {
            if path == r { return true }
            if path.hasPrefix(r + "/") { return true }
        }
        return false
    }

    // MARK: - Candidate retrieval

    /// Retrieve the candidate pool for a multi-token query. Uses the union of
    /// grams from all tokens >=3 chars; tokens shorter than gram size add a
    /// LIKE constraint instead. Post-filters to ensure every token is a
    /// substring somewhere on each row (nameLower OR pathLower).
    private func candidates(tokens: [String], limit: Int) throws -> [Row] {
        var longTokens: [String] = []
        var shortTokens: [String] = []
        for t in tokens {
            if t.count >= Gram.size { longTokens.append(t) } else { shortTokens.append(t) }
        }

        let rawRows: [Row]
        if longTokens.isEmpty {
            // All tokens short. Any single one becomes the primary LIKE filter
            // (pick first), remaining tokens are applied as post-filters.
            guard let primary = shortTokens.first else { return [] }
            rawRows = try likeCandidates(token: primary, limit: limit)
        } else {
            // Use union of grams across all long tokens, requiring all unique
            // grams present via HAVING. Short tokens are post-filtered below.
            rawRows = try gramCandidates(longTokens: longTokens, limit: limit)
        }

        // Per-token substring AND: every token must be a substring of name OR
        // path; gram retrieval alone is only a gate, the contiguous match is
        // still required.
        return rawRows.filter { row in
            for t in tokens {
                if !row.nameLower.contains(t) && !row.pathLower.contains(t) {
                    return false
                }
            }
            return true
        }
    }

    private func likeCandidates(token: String, limit: Int) throws -> [Row] {
        let sql = """
        SELECT path, name, is_dir, size, mtime, name_lower, path_lower FROM files
        WHERE name_lower LIKE ? OR path_lower LIKE ?
        LIMIT ?;
        """
        let like = "%\(token)%"
        return try executeQuery(sql) { stmt, transient in
            _ = sqlite3_bind_text(stmt, 1, like, -1, transient)
            _ = sqlite3_bind_text(stmt, 2, like, -1, transient)
            _ = sqlite3_bind_int64(stmt, 3, Int64(limit))
        }
    }

    private func gramCandidates(longTokens: [String], limit: Int) throws -> [Row] {
        var gramSet: Set<String> = []
        for t in longTokens {
            gramSet.formUnion(Gram.grams(of: t))
        }
        let grams = Array(gramSet)
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
        return try executeQuery(sql) { stmt, transient in
            var idx: Int32 = 1
            for g in grams {
                _ = sqlite3_bind_text(stmt, idx, g, -1, transient)
                idx += 1
            }
            _ = sqlite3_bind_int64(stmt, idx, Int64(grams.count))
            idx += 1
            _ = sqlite3_bind_int64(stmt, idx, Int64(limit))
        }
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

    /// Back-compat single-token scoring entry point. Preserved so legacy
    /// callers / tests that pass a single raw query keep working.
    /// Base tiers (higher is better):
    ///   1000 filename exact match
    ///    800 filename starts with query
    ///    500 filename contains query
    ///    200 path (but not filename) contains query
    ///      0 no match
    /// E1 bonus bands (additive on top of base tier):
    ///   +50 basename bonus: token appears in basename, not only in path
    ///   +30 token-boundary bonus: match aligns with `/`, `.`, `-`, `_`, or space
    ///   +40 path-segment bonus: token equals an entire path segment or the basename
    ///   +80 extension bonus: token equals the file extension (after last `.`)
    public static func score(query q: String, nameLower: String, pathLower: String) -> Int {
        return scoreToken(q, nameLower: nameLower, pathLower: pathLower)
    }

    /// Multi-token score. Every token must match (AND); returns 0 if any
    /// token is absent from both nameLower and pathLower. Final score is the
    /// sum of per-token scores plus an `all-in-basename` multi-token bonus.
    public static func scoreTokens(_ tokens: [String],
                                   nameLower: String,
                                   pathLower: String) -> Int {
        guard !tokens.isEmpty else { return 0 }
        var total = 0
        var allInName = true
        for t in tokens {
            let s = scoreToken(t, nameLower: nameLower, pathLower: pathLower)
            guard s > 0 else { return 0 }
            total += s
            if !nameLower.contains(t) { allInName = false }
        }
        if tokens.count >= 2 && allInName {
            total += 100 // every word appears in basename — a strong signal
        }
        return total
    }

    /// Per-token scoring with E1 bonuses applied.
    static func scoreToken(_ t: String, nameLower: String, pathLower: String) -> Int {
        let base: Int
        if nameLower == t { base = 1000 }
        else if nameLower.hasPrefix(t) { base = 800 }
        else if nameLower.contains(t) { base = 500 }
        else if pathLower.contains(t) { base = 200 }
        else { return 0 }

        var bonus = 0
        // Basename bonus: token appears in basename, not only in path.
        if nameLower.contains(t) {
            bonus += 50
        }
        // Path-segment bonus: token equals a whole path segment or the name.
        if isExactSegment(t, in: pathLower) || nameLower == t {
            bonus += 40
        }
        // Extension bonus: token equals the file's trailing extension.
        if extensionMatches(t, name: nameLower) {
            bonus += 80
        }
        // Token-boundary bonus: match is adjacent to a word boundary char.
        if atWordBoundary(t, in: nameLower) || atWordBoundary(t, in: pathLower) {
            bonus += 30
        }
        return base + bonus
    }

    // MARK: - Bonus predicates

    static func atWordBoundary(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty, !haystack.isEmpty else { return false }
        // Look for any occurrence where either the preceding or following
        // character is a boundary (or the match touches a string end).
        var searchFrom = haystack.startIndex
        while searchFrom < haystack.endIndex,
              let range = haystack.range(of: needle,
                                         range: searchFrom..<haystack.endIndex) {
            let beforeBoundary: Bool
            if range.lowerBound == haystack.startIndex {
                beforeBoundary = true
            } else {
                let prev = haystack[haystack.index(before: range.lowerBound)]
                beforeBoundary = isBoundaryChar(prev)
            }
            let afterBoundary: Bool
            if range.upperBound == haystack.endIndex {
                afterBoundary = true
            } else {
                let next = haystack[range.upperBound]
                afterBoundary = isBoundaryChar(next)
            }
            if beforeBoundary || afterBoundary { return true }
            searchFrom = haystack.index(after: range.lowerBound)
        }
        return false
    }

    static func isBoundaryChar(_ c: Character) -> Bool {
        return c == "/" || c == "." || c == "-" || c == "_" || c == " "
    }

    static func isExactSegment(_ needle: String, in pathLower: String) -> Bool {
        guard !needle.isEmpty else { return false }
        for seg in pathLower.split(separator: "/", omittingEmptySubsequences: true) {
            if seg == needle { return true }
        }
        return false
    }

    static func extensionMatches(_ needle: String, name nameLower: String) -> Bool {
        guard !needle.isEmpty,
              let dot = nameLower.lastIndex(of: ".") else { return false }
        let extPart = nameLower[nameLower.index(after: dot)...]
        return String(extPart) == needle
    }

    // MARK: - Ranking

    private func rank(rows: [Row], tokens: [String]) -> [SearchResult] {
        let scored: [SearchResult] = rows.compactMap { row in
            let s = SearchEngine.scoreTokens(tokens,
                                             nameLower: row.nameLower,
                                             pathLower: row.pathLower)
            guard s > 0 else { return nil }
            return SearchResult(path: row.path,
                                name: row.name,
                                isDir: row.isDir,
                                size: row.size,
                                mtime: row.mtime,
                                score: s)
        }
        return SearchEngine.sort(scored, by: .scoreDescending)
    }

    /// E2 re-sort a result set by the requested key without re-querying.
    /// Tie-breaks on shorter path, then alphabetical path so the order is
    /// deterministic across runs. Uses a stable sort so equal-key groups
    /// preserve relative score order — that way switching to name-asc then
    /// back to score-desc is lossless.
    public static func sort(_ results: [SearchResult],
                            by order: SearchSortOrder) -> [SearchResult] {
        return results.sorted { lhs, rhs in
            let primary: Int
            switch order.key {
            case .score:
                // score is a natural "higher is better" key; flip if ascending.
                if lhs.score == rhs.score { primary = 0 }
                else {
                    primary = order.ascending
                        ? (lhs.score < rhs.score ? -1 : 1)
                        : (lhs.score > rhs.score ? -1 : 1)
                }
            case .name:
                primary = compareString(lhs.name.lowercased(),
                                        rhs.name.lowercased(),
                                        ascending: order.ascending)
            case .path:
                primary = compareString(lhs.path.lowercased(),
                                        rhs.path.lowercased(),
                                        ascending: order.ascending)
            case .mtime:
                primary = compareInt(lhs.mtime, rhs.mtime, ascending: order.ascending)
            case .size:
                primary = compareInt(lhs.size, rhs.size, ascending: order.ascending)
            }
            if primary != 0 { return primary < 0 }
            // Deterministic tie-break: shorter path first, then alphabetical.
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }
    }

    private static func compareString(_ l: String,
                                      _ r: String,
                                      ascending: Bool) -> Int {
        if l == r { return 0 }
        let less = l < r
        return ascending ? (less ? -1 : 1) : (less ? 1 : -1)
    }

    private static func compareInt(_ l: Int64,
                                   _ r: Int64,
                                   ascending: Bool) -> Int {
        if l == r { return 0 }
        let less = l < r
        return ascending ? (less ? -1 : 1) : (less ? 1 : -1)
    }
}
