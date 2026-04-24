import Foundation
import CSQLite

public struct SearchResult: Equatable {
    public let path: String
    public let name: String
    public let isDir: Bool
    public let size: Int64
    public let mtime: Int64
    public let score: Int
    /// H2: SwiftSeek-internal `open_count` for this file. 0 means "never
    /// opened through SwiftSeek" (or usage row missing). Filled in via
    /// `LEFT JOIN file_usage` on every search so callers don't need a
    /// second round-trip. NOT the macOS global launch count — see
    /// `docs/known_issues.md` §1-2 for the semantics contract.
    public let openCount: Int64
    /// H2: last time the user opened this file through SwiftSeek (Unix
    /// epoch seconds). 0 means "never / no row".
    public let lastOpenedAt: Int64

    public init(path: String,
                name: String,
                isDir: Bool,
                size: Int64,
                mtime: Int64,
                score: Int,
                openCount: Int64 = 0,
                lastOpenedAt: Int64 = 0) {
        self.path = path
        self.name = name
        self.isDir = isDir
        self.size = size
        self.mtime = mtime
        self.score = score
        self.openCount = openCount
        self.lastOpenedAt = lastOpenedAt
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
    /// H2: sort by SwiftSeek-internal open_count. "Higher = more used"
    /// is the natural user expectation, so the default binding in the
    /// UI flips `ascending` to false on first header click.
    case openCount
    /// H2: sort by last time opened through SwiftSeek (Unix epoch
    /// seconds). Default binding also flips to `ascending=false` so a
    /// first click gives "most recent first".
    case lastOpenedAt
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

// MARK: - E3 query filters

/// Type of entry a `kind:` filter admits. Kept as a small closed enum so
/// the parser rejects unknown values loudly rather than silently adopting
/// them.
public enum QueryKind: String, Equatable, Sendable {
    case file
    case dir
}

/// Whether the `hidden:` filter requires hidden / visible / either.
/// `.unspecified` is the "no filter" state — the presence of any other
/// case means the user explicitly asked for hidden-only or visible-only
/// (independent of the global `hidden_files_enabled` index toggle).
public enum HiddenFilterMode: Equatable, Sendable {
    case unspecified
    case requireHidden
    case requireVisible
}

/// Filters parsed out of a raw query. Every field is treated as "no
/// filter" when empty. Filters compose with AND; plain tokens are
/// scored independently in `scoreTokens` and are NOT stored here.
public struct QueryFilters: Equatable, Sendable {
    public var extensions: Set<String>   // lowercase, no leading dot
    public var kinds: Set<QueryKind>
    public var pathTokens: [String]      // substring must appear in pathLower (not just nameLower)
    public var rootRestriction: String?  // lowercased path prefix; empty = no restriction
    public var hiddenMode: HiddenFilterMode

    public init(extensions: Set<String> = [],
                kinds: Set<QueryKind> = [],
                pathTokens: [String] = [],
                rootRestriction: String? = nil,
                hiddenMode: HiddenFilterMode = .unspecified) {
        self.extensions = extensions
        self.kinds = kinds
        self.pathTokens = pathTokens
        self.rootRestriction = rootRestriction
        self.hiddenMode = hiddenMode
    }

    public var isEmpty: Bool {
        return extensions.isEmpty
            && kinds.isEmpty
            && pathTokens.isEmpty
            && rootRestriction == nil
            && hiddenMode == .unspecified
    }
}

/// H3: usage-driven query mode. `.normal` is the pre-H3 behavior.
/// `.recent` / `.frequent` reroute the candidate retrieval through
/// `file_usage` JOIN `files` and sort by `last_opened_at DESC` /
/// `open_count DESC`. Plain tokens and filters still compose via
/// post-filter so `recent: ext:md` means "most recent .md files I've
/// opened through SwiftSeek". Modes are mutually exclusive — the first
/// `recent:` / `frequent:` token wins and any later one is ignored
/// (typo tolerance, matches how `kind:` / `root:` behave).
///
/// Semantics boundary:
///   * Only files that have a `file_usage` row (openCount >= 1) show up.
///   * Ordering is the usage column; `score` is set to a baseline so
///     the existing H2 tie-break logic is a no-op here.
///   * NOT the macOS global recent-items list — `docs/known_issues.md`
///     §1 stays authoritative: Run Count / 最近打开 == SwiftSeek
///     internal `.open` only.
public enum UsageMode: Equatable, Sendable {
    case normal
    case recent
    case frequent
}

/// Result of parsing a raw user query into `plainTokens` (fed to the
/// scoring path) and `filters` (applied post-candidate).
public struct ParsedQuery: Equatable, Sendable {
    public var plainTokens: [String]
    public var filters: QueryFilters
    /// H3: `.recent` / `.frequent` reroute candidate retrieval through
    /// `file_usage`. `.normal` preserves pre-H3 behavior.
    public var usageMode: UsageMode

    public init(plainTokens: [String] = [],
                filters: QueryFilters = QueryFilters(),
                usageMode: UsageMode = .normal) {
        self.plainTokens = plainTokens
        self.filters = filters
        self.usageMode = usageMode
    }

    /// A query with no meaningful input at all. `search()` short-circuits
    /// to an empty result list for this case.
    public var isEmpty: Bool {
        plainTokens.isEmpty && filters.isEmpty && usageMode == .normal
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
        /// H2: LEFT JOIN file_usage. 0 when no usage row exists.
        let openCount: Int64
        let lastOpenedAt: Int64
    }

    private let database: Database
    /// F1: prepared statement cache keyed by SQL string. Each row is a single
    /// pointer we reset + rebind on reuse; SQLite is opened in
    /// `SQLITE_OPEN_FULLMUTEX` (serialized), so an internal lock keeps the
    /// dictionary itself safe across the background search queue and the
    /// smoke / bench threads that hit the engine directly.
    private let stmtLock = NSLock()
    private var stmtCache: [String: OpaquePointer] = [:]
    /// Exposed for F1 bench / smoke so tests can verify the cache is actually
    /// being hit rather than just compiled.
    public private(set) var stmtCacheHits: Int = 0
    public private(set) var stmtCacheMisses: Int = 0

    public init(database: Database) {
        self.database = database
    }

    deinit {
        // Finalize every cached statement so SQLite doesn't complain when
        // the DB is closed. Held under the lock for the same reason the
        // cache needs one.
        stmtLock.lock()
        for (_, stmt) in stmtCache { sqlite3_finalize(stmt) }
        stmtCache.removeAll()
        stmtLock.unlock()
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

    // MARK: - E3 query filter parser

    /// Known filter keys. Unknown `foo:bar` tokens are treated as plain
    /// tokens (i.e. literal substring), NOT silently adopted as filters.
    private static let filterKeys: Set<String> = ["ext", "kind", "path", "root", "hidden"]

    /// H3 usage-mode keys. Appear as bare `recent:` / `frequent:`
    /// tokens with no value. The first one wins; later ones are
    /// ignored (typo tolerance). Mixing `recent:` and `frequent:` in
    /// the same query is allowed but only the first sets the mode.
    private static let usageModeKeys: Set<String> = ["recent", "frequent"]

    /// Parse raw user input into `ParsedQuery`. Tokens formatted `key:value`
    /// where `key` is in `filterKeys` are treated as filters; all other
    /// tokens go to `plainTokens` verbatim.
    ///
    /// Filter value syntax:
    ///   - `ext:md`, `ext:md,txt`     – allowed extensions (comma-separated)
    ///   - `kind:file` / `kind:dir`   – entry type; unknown kinds are
    ///                                  silently dropped to keep the parser
    ///                                  tolerant of typos
    ///   - `path:foo`                 – token must appear in pathLower
    ///                                  (does NOT have to be in name);
    ///                                  multiple `path:` tokens AND together
    ///   - `root:/some/prefix`        – restrict to paths at-or-under that
    ///                                  absolute prefix
    ///   - `hidden:true|yes|1`        – only hidden entries
    ///   - `hidden:false|no|0`        – only visible entries
    ///
    /// Empty values (`ext:`) are ignored rather than raised as errors;
    /// this mirrors how Spotlight and Everything handle half-typed filters
    /// while the user is still editing.
    public static func parseQuery(_ raw: String) -> ParsedQuery {
        var parsed = ParsedQuery()
        for token in tokenize(raw) {
            guard let colonIdx = token.firstIndex(of: ":") else {
                parsed.plainTokens.append(token)
                continue
            }
            let key = String(token[..<colonIdx])
            let valueStart = token.index(after: colonIdx)
            let value = String(token[valueStart...])
            // H3: `recent:` / `frequent:` are bare mode switches; they
            // take no value. First one wins; we consume the token so
            // it doesn't leak into `plainTokens` as literal text.
            if usageModeKeys.contains(key), value.isEmpty {
                if parsed.usageMode == .normal {
                    parsed.usageMode = (key == "recent") ? .recent : .frequent
                }
                continue
            }
            if !filterKeys.contains(key) {
                parsed.plainTokens.append(token)
                continue
            }
            if value.isEmpty { continue }
            switch key {
            case "ext":
                for part in value.split(separator: ",") {
                    let ext = String(part).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                    if !ext.isEmpty { parsed.filters.extensions.insert(ext) }
                }
            case "kind":
                if let k = QueryKind(rawValue: value) {
                    parsed.filters.kinds.insert(k)
                }
                // Unknown kind → drop silently; future values may be added.
            case "path":
                parsed.filters.pathTokens.append(value)
            case "root":
                // Canonicalize as lowercase prefix without trailing slash
                // so the prefix match below is symmetric with how we store
                // paths (always rooted at `/`, never with trailing `/`).
                var r = value
                while r.hasSuffix("/") && r.count > 1 { r.removeLast() }
                parsed.filters.rootRestriction = r
            case "hidden":
                switch value {
                case "true", "yes", "1", "on":
                    parsed.filters.hiddenMode = .requireHidden
                case "false", "no", "0", "off":
                    parsed.filters.hiddenMode = .requireVisible
                default:
                    break // tolerant: ignore unknown value
                }
            default:
                parsed.plainTokens.append(token)
            }
        }
        return parsed
    }

    // MARK: - Search

    public func search(_ rawQuery: String, options: Options = .init()) throws -> [SearchResult] {
        let parsed = SearchEngine.parseQuery(rawQuery)
        if parsed.isEmpty { return [] }

        // G3: read index mode once per search. F1 settings cache makes
        // this cheap; compact vs fullpath drives the candidate tables
        // and the post-filter rules.
        let mode: IndexMode
        do {
            mode = try database.getIndexMode()
        } catch {
            NSLog("SwiftSeek: SearchEngine getIndexMode failed, defaulting to compact: \(error)")
            mode = .compact
        }

        let candidatePool = max(options.limit * options.candidateMultiplier, options.limit)
        let rows: [Row]
        if parsed.usageMode != .normal {
            // H3: `recent:` / `frequent:` candidate pool comes straight
            // from file_usage INNER JOIN files — by definition we only
            // want files the user has opened through SwiftSeek. SQL
            // emits them already in usage order so the post-filter
            // pipeline preserves ordering.
            rows = try usageCandidates(mode: parsed.usageMode, limit: candidatePool)
        } else if !parsed.plainTokens.isEmpty {
            rows = try candidates(tokens: parsed.plainTokens,
                                  pathTokens: parsed.filters.pathTokens,
                                  mode: mode,
                                  limit: candidatePool)
        } else {
            // E3 filter-only query: no plain tokens to gram-match against.
            // G3: filterOnlyCandidates already routes through the v4
            // tables via `gramCandidates` / `bigramCandidates`. In
            // compact mode `path:` tokens should instead go through
            // file_path_segments; extension / kind / root keep their
            // own primary SQL since those tables are the same.
            rows = try filterOnlyCandidates(filters: parsed.filters,
                                            mode: mode,
                                            limit: candidatePool)
        }

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
        let rooted: [Row]
        if allRoots.isEmpty {
            rooted = rows
        } else {
            rooted = rows.filter { SearchEngine.pathUnderAnyRoot($0.path, roots: enabledRoots) }
        }

        // E3 apply user-expressed filters AFTER root gating so we don't
        // pay for filter checks on rows the user could never see anyway.
        // G3: in compact mode the per-token substring AND also runs
        // against name-only; in fullpath mode the pre-G3 behaviour
        // (name OR path) is preserved via rowMatches below.
        let filtered = rooted.filter { row in
            // G3 compact plain-token check: every plain token must
            // match somewhere in nameLower. In fullpath mode name OR
            // path is accepted (pre-G3 semantics preserved inside
            // candidates()).
            // H3: usage modes also use the name-contain semantic
            // regardless of index mode — `recent: todo` means "most
            // recent files whose name contains todo". We never widen
            // back to path substring here so the usage pool stays
            // predictable.
            if mode == .compact || parsed.usageMode != .normal {
                for t in parsed.plainTokens {
                    if !row.nameLower.contains(t) { return false }
                }
            }
            return SearchEngine.rowMatches(row: row,
                                           filters: parsed.filters,
                                           mode: mode)
        }

        // If the query is filter-only (no plain tokens) we rank by mtime
        // descending — "show me all md files" is almost always most useful
        // in freshest-first order. Presence of plain tokens always keeps
        // the scoring path as the primary ranking signal.
        let scored: [SearchResult]
        if parsed.usageMode != .normal {
            // H3: the SQL ORDER BY already emitted rows in usage order
            // (last_opened_at DESC for .recent / open_count DESC for
            // .frequent), and `filter` preserves input order. Map to
            // SearchResult with a baseline score so the result view's
            // existing plumbing (limit, selection preservation) works
            // unchanged. score is identical for every hit so the H2
            // tie-break is a no-op here.
            scored = filtered.map { row in
                SearchResult(path: row.path,
                             name: row.name,
                             isDir: row.isDir,
                             size: row.size,
                             mtime: row.mtime,
                             score: 100,
                             openCount: row.openCount,
                             lastOpenedAt: row.lastOpenedAt)
            }
        } else if !parsed.plainTokens.isEmpty {
            scored = rank(rows: filtered, tokens: parsed.plainTokens)
        } else {
            scored = filtered.map { row in
                SearchResult(path: row.path,
                             name: row.name,
                             isDir: row.isDir,
                             size: row.size,
                             mtime: row.mtime,
                             score: 100, // baseline so "仅显示前 N 条" still makes sense
                             openCount: row.openCount,
                             lastOpenedAt: row.lastOpenedAt)
            }
            .sorted { lhs, rhs in
                if lhs.mtime != rhs.mtime { return lhs.mtime > rhs.mtime }
                if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
                return lhs.path < rhs.path
            }
        }
        return Array(scored.prefix(options.limit))
    }

    /// Public test-facing filter predicate. Identical semantics to the
    /// internal `rowMatches`; takes primitive fields so smoke tests can
    /// hand-craft rows without building a full `Row` value.
    ///
    /// `mode` defaults to `.fullpath` to preserve the pre-G3 contract
    /// (path: tokens do substring on pathLower). In `.compact` mode
    /// path: tokens switch to segment-prefix semantics (see
    /// docs/everything_footprint_v5_proposal.md §5.1).
    public static func matches(nameLower: String,
                               pathLower: String,
                               path: String,
                               isDir: Bool,
                               filters: QueryFilters,
                               mode: IndexMode = .fullpath) -> Bool {
        if !filters.extensions.isEmpty {
            if !filters.extensions.contains(extension_(of: nameLower)) { return false }
        }
        if !filters.kinds.isEmpty {
            let k: QueryKind = isDir ? .dir : .file
            if !filters.kinds.contains(k) { return false }
        }
        if !filters.pathTokens.isEmpty {
            if mode == .fullpath {
                // Pre-G3: simple substring anywhere in pathLower.
                for t in filters.pathTokens {
                    if !pathLower.contains(t) { return false }
                }
            } else {
                // G3 compact: prefix match against per-segment list.
                let segments = Gram.pathSegments(pathLower: pathLower)
                for t in filters.pathTokens {
                    if !segments.contains(where: { $0.hasPrefix(t) }) {
                        return false
                    }
                }
            }
        }
        if let prefix = filters.rootRestriction, !prefix.isEmpty {
            let lowerPrefix = prefix.lowercased()
            if pathLower != lowerPrefix && !pathLower.hasPrefix(lowerPrefix + "/") {
                return false
            }
        }
        switch filters.hiddenMode {
        case .unspecified:
            break
        case .requireHidden:
            if !HiddenPath.isHidden(path) { return false }
        case .requireVisible:
            if HiddenPath.isHidden(path) { return false }
        }
        return true
    }

    /// Return true iff `row` satisfies every active filter in `filters`.
    private static func rowMatches(row: Row,
                                   filters: QueryFilters,
                                   mode: IndexMode = .fullpath) -> Bool {
        return matches(nameLower: row.nameLower,
                       pathLower: row.pathLower,
                       path: row.path,
                       isDir: row.isDir,
                       filters: filters,
                       mode: mode)
    }

    /// Extract the extension token (lowercased, no dot) for filter checks.
    /// Returns empty string if the name has no extension (falls through the
    /// `extensions` filter as "no extension" cleanly).
    static func extension_(of nameLower: String) -> String {
        guard let dot = nameLower.lastIndex(of: ".") else { return "" }
        return String(nameLower[nameLower.index(after: dot)...])
    }

    /// Candidate pool for a query that has filters but no plain tokens.
    /// Emits a single SQL query biased toward whichever filter is likely
    /// to be most selective.
    ///
    /// F4 priority order — picks the candidate retrieval most likely to
    /// narrow the row set before post-filtering:
    ///   1. `path:` token(s) ≥3 chars → file_grams index (trigram).
    ///   2. `path:` token(s) ==2 chars → file_bigrams index.
    ///   3. extension filter → linear scan of `name_lower` using
    ///      `LIKE '%.ext'`. SQLite cannot use a B-tree index for a
    ///      pattern with a leading `%`, so this is a table scan in
    ///      practice. On typical SwiftSeek databases (10k–100k rows)
    ///      this still returns in milliseconds; the benefit is we
    ///      never materialise rows whose extension doesn't match at
    ///      SQL level, so post-filtering is cheap.
    ///   4. root prefix → `path_lower LIKE 'prefix/%'`. The `prefix/`
    ///      portion is before the wildcard, so B-tree
    ///      `idx_files_path_lower` IS usable for this one.
    ///   5. kind filter → `is_dir = ?`. No index on `is_dir`; it's a
    ///      cheap binary filter so the scan cost is bounded by limit.
    ///   6. fallback bounded scan. Reached for queries whose only
    ///      selectors are `hidden:` or `path:` with a 1-character token
    ///      (too short for either gram table).
    /// The first match wins; remaining filters are applied post-candidate
    /// via `rowMatches`.
    private func filterOnlyCandidates(filters: QueryFilters, mode: IndexMode, limit: Int) throws -> [Row] {
        // Priority 1 / 2: `path:` token routing depends on mode.
        if !filters.pathTokens.isEmpty {
            if mode == .compact {
                // G3 compact: segment-prefix lookup against
                // file_path_segments (the small index). No gram work.
                return try pathSegmentCandidates(pathTokens: filters.pathTokens, limit: limit)
            }
            // Fullpath mode (F4 behaviour).
            let longPath = filters.pathTokens.filter { $0.count >= Gram.size }
            let shortPath = filters.pathTokens.filter { $0.count == Gram.bigramSize }
            if !longPath.isEmpty {
                return try gramCandidates(longTokens: longPath, mode: .fullpath, limit: limit)
            }
            if !shortPath.isEmpty {
                return try bigramCandidates(shortTokens: shortPath, mode: .fullpath, limit: limit)
            }
        }
        // Priority 3: extension filter (typically very selective — most
        // users run `ext:md` to find notes on a specific type).
        if !filters.extensions.isEmpty {
            let placeholders = filters.extensions.map { _ in "?" }.joined(separator: " OR name_lower LIKE ")
            let sql = """
            SELECT path, name, is_dir, size, mtime, name_lower, path_lower, COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0) FROM files LEFT JOIN file_usage fu ON fu.file_id = files.id
            WHERE name_lower LIKE \(placeholders)
            LIMIT ?;
            """
            return try executeQuery(sql) { stmt, transient in
                var idx: Int32 = 1
                for ext in filters.extensions {
                    _ = sqlite3_bind_text(stmt, idx, "%.\(ext)", -1, transient)
                    idx += 1
                }
                _ = sqlite3_bind_int64(stmt, idx, Int64(limit))
            }
        }
        // Priority 2: root prefix restriction.
        if let root = filters.rootRestriction, !root.isEmpty {
            let sql = """
            SELECT path, name, is_dir, size, mtime, name_lower, path_lower, COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0) FROM files LEFT JOIN file_usage fu ON fu.file_id = files.id
            WHERE path_lower = ? OR path_lower LIKE ?
            LIMIT ?;
            """
            return try executeQuery(sql) { stmt, transient in
                let rLower = root.lowercased()
                _ = sqlite3_bind_text(stmt, 1, rLower, -1, transient)
                _ = sqlite3_bind_text(stmt, 2, "\(rLower)/%", -1, transient)
                _ = sqlite3_bind_int64(stmt, 3, Int64(limit))
            }
        }
        // Priority 3: kind filter only (file vs dir).
        if !filters.kinds.isEmpty {
            if filters.kinds.count == 1 {
                let wantDir = filters.kinds.contains(.dir)
                let sql = """
                SELECT path, name, is_dir, size, mtime, name_lower, path_lower, COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0) FROM files LEFT JOIN file_usage fu ON fu.file_id = files.id
                WHERE is_dir = ?
                LIMIT ?;
                """
                return try executeQuery(sql) { stmt, _ in
                    _ = sqlite3_bind_int(stmt, 1, wantDir ? 1 : 0)
                    _ = sqlite3_bind_int64(stmt, 2, Int64(limit))
                }
            }
            // Both kinds → naive bounded scan
        }
        // Fallback: bounded scan. Only reachable for filter-only queries
        // where the only filter is `path:` or `hidden:`, which we must
        // apply post-candidate regardless. The LIMIT keeps pathological
        // DBs from blowing up the GUI.
        let sql = """
        SELECT path, name, is_dir, size, mtime, name_lower, path_lower, COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0) FROM files LEFT JOIN file_usage fu ON fu.file_id = files.id
        LIMIT ?;
        """
        return try executeQuery(sql) { stmt, _ in
            _ = sqlite3_bind_int64(stmt, 1, Int64(limit))
        }
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

    /// Retrieve the candidate pool for a multi-token query.
    ///
    /// F1/G3 candidate retrieval. Routes by mode:
    ///   fullpath mode (v4 semantics, pre-G3 default):
    ///     * All tokens >=3 chars → `file_grams` (name+path)
    ///     * 2-char only → `file_bigrams`
    ///     * any 1-char → LIKE fallback
    ///   compact mode (G3 default for new DBs):
    ///     * >=3 chars → `file_name_grams` (name only)
    ///     * 2-char → `file_name_bigrams` (name only)
    ///     * 1-char → LIKE on name_lower only
    ///     * Post-filter also requires match in name (enforced at caller)
    private func candidates(tokens: [String],
                            pathTokens: [String],
                            mode: IndexMode,
                            limit: Int) throws -> [Row] {
        var longTokens: [String] = []   // >= 3 chars  (trigram)
        var shortTokens: [String] = []  // == 2 chars  (bigram)
        var tinyTokens: [String] = []   // == 1 char   (LIKE fallback)
        for t in tokens {
            if t.count >= Gram.size { longTokens.append(t) }
            else if t.count == Gram.bigramSize { shortTokens.append(t) }
            else { tinyTokens.append(t) }
        }

        let rawRows: [Row]
        if mode == .fullpath {
            if !tinyTokens.isEmpty {
                let primary = tokens.max(by: { $0.count < $1.count })!
                rawRows = try likeCandidates(token: primary, nameOnly: false, limit: limit)
            } else if longTokens.isEmpty, !shortTokens.isEmpty {
                rawRows = try bigramCandidates(shortTokens: shortTokens, mode: .fullpath, limit: limit)
            } else {
                rawRows = try gramCandidates(longTokens: longTokens, mode: .fullpath, limit: limit)
            }
        } else {
            // Compact mode: basename-only index candidate retrieval.
            if !tinyTokens.isEmpty {
                let primary = tokens.max(by: { $0.count < $1.count })!
                rawRows = try likeCandidates(token: primary, nameOnly: true, limit: limit)
            } else if longTokens.isEmpty, !shortTokens.isEmpty {
                rawRows = try bigramCandidates(shortTokens: shortTokens, mode: .compact, limit: limit)
            } else {
                rawRows = try gramCandidates(longTokens: longTokens, mode: .compact, limit: limit)
            }
        }

        // Per-token substring AND. In fullpath mode either name OR path
        // matches; in compact mode only name counts (and path: filters
        // are applied separately via rowMatches/matches).
        return rawRows.filter { row in
            for t in tokens {
                if mode == .fullpath {
                    if !row.nameLower.contains(t) && !row.pathLower.contains(t) {
                        return false
                    }
                } else {
                    if !row.nameLower.contains(t) { return false }
                }
            }
            return true
        }
    }

    private func likeCandidates(token: String, nameOnly: Bool, limit: Int) throws -> [Row] {
        let sql: String
        if nameOnly {
            sql = """
            SELECT path, name, is_dir, size, mtime, name_lower, path_lower, COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0) FROM files LEFT JOIN file_usage fu ON fu.file_id = files.id
            WHERE name_lower LIKE ?
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT path, name, is_dir, size, mtime, name_lower, path_lower, COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0) FROM files LEFT JOIN file_usage fu ON fu.file_id = files.id
            WHERE name_lower LIKE ? OR path_lower LIKE ?
            LIMIT ?;
            """
        }
        let like = "%\(token)%"
        return try executeQuery(sql) { stmt, transient in
            _ = sqlite3_bind_text(stmt, 1, like, -1, transient)
            var idx: Int32 = 2
            if !nameOnly {
                _ = sqlite3_bind_text(stmt, idx, like, -1, transient)
                idx += 1
            }
            _ = sqlite3_bind_int64(stmt, idx, Int64(limit))
        }
    }

    /// F1 / G3: bigram candidate retrieval. `mode` switches between
    /// the v4 name+path table (`file_bigrams`) and the compact
    /// basename-only table (`file_name_bigrams`).
    private func bigramCandidates(shortTokens: [String],
                                  mode: IndexMode,
                                  limit: Int) throws -> [Row] {
        var gramSet: Set<String> = []
        for t in shortTokens {
            gramSet.formUnion(Gram.bigrams(of: t))
        }
        let grams = Array(gramSet)
        guard !grams.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: grams.count).joined(separator: ",")
        let table = (mode == .compact) ? "file_name_bigrams" : "file_bigrams"
        let sql = """
        SELECT f.path, f.name, f.is_dir, f.size, f.mtime, f.name_lower, f.path_lower,
               COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0)
        FROM \(table) fg
        JOIN files f ON f.id = fg.file_id
        LEFT JOIN file_usage fu ON fu.file_id = f.id
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

    /// F1 / G3: trigram candidate retrieval. `mode` switches between
    /// the v4 name+path table (`file_grams`) and the compact
    /// basename-only table (`file_name_grams`).
    private func gramCandidates(longTokens: [String],
                                mode: IndexMode,
                                limit: Int) throws -> [Row] {
        var gramSet: Set<String> = []
        for t in longTokens {
            gramSet.formUnion(Gram.grams(of: t))
        }
        let grams = Array(gramSet)
        guard !grams.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: grams.count).joined(separator: ",")
        let table = (mode == .compact) ? "file_name_grams" : "file_grams"
        let sql = """
        SELECT f.path, f.name, f.is_dir, f.size, f.mtime, f.name_lower, f.path_lower,
               COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0)
        FROM \(table) fg
        JOIN files f ON f.id = fg.file_id
        LEFT JOIN file_usage fu ON fu.file_id = f.id
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

    /// G3: candidate rows by `path:<token>` segment-prefix match
    /// against the compact `file_path_segments` table. Emits rows
    /// whose *any* segment matches *any* of the tokens; the per-token
    /// AND contract is finished by the row-level post-filter in
    /// `matches()` (which re-checks each token independently via
    /// `Gram.pathSegments`). This avoids the "different tokens need
    /// different segments" trap that a naive
    /// `HAVING COUNT(DISTINCT segment) >= tokenCount` would fall into:
    /// G2 contract explicitly allows one segment to satisfy multiple
    /// tokens (e.g. `path:doc path:docs` both satisfied by segment
    /// "docs").
    /// H3: candidate rows for `recent:` / `frequent:` modes. INNER
    /// JOIN with `file_usage` so only files the user has actually
    /// opened through SwiftSeek appear (openCount >= 1 by
    /// construction — recordOpen only creates rows on success). Order
    /// is decided here in SQL so the post-filter pipeline preserves
    /// it by doing index-stable Array filtering.
    ///
    /// Tie-break: on equal primary key we fall back to the other
    /// usage column so the ordering is total. Paths are not used as a
    /// SQL tie-break — if two rows truly have identical open_count +
    /// last_opened_at, Array.filter + post-sort still yields a stable
    /// deterministic order via the root-gating / filter layer.
    private func usageCandidates(mode: UsageMode, limit: Int) throws -> [Row] {
        let orderBy: String
        switch mode {
        case .recent:
            orderBy = "u.last_opened_at DESC, u.open_count DESC"
        case .frequent:
            orderBy = "u.open_count DESC, u.last_opened_at DESC"
        case .normal:
            return [] // caller shouldn't dispatch .normal here.
        }
        let sql = """
        SELECT f.path, f.name, f.is_dir, f.size, f.mtime, f.name_lower, f.path_lower,
               u.open_count, u.last_opened_at
        FROM file_usage u
        JOIN files f ON f.id = u.file_id
        ORDER BY \(orderBy)
        LIMIT ?;
        """
        return try executeQuery(sql) { stmt, _ in
            _ = sqlite3_bind_int64(stmt, 1, Int64(limit))
        }
    }

    private func pathSegmentCandidates(pathTokens: [String], limit: Int) throws -> [Row] {
        guard !pathTokens.isEmpty else { return [] }
        let cases = pathTokens.map { _ in "(ps.segment = ? OR ps.segment LIKE ?)" }
            .joined(separator: " OR ")
        let sql = """
        SELECT f.path, f.name, f.is_dir, f.size, f.mtime, f.name_lower, f.path_lower,
               COALESCE(fu.open_count, 0), COALESCE(fu.last_opened_at, 0)
        FROM file_path_segments ps
        JOIN files f ON f.id = ps.file_id
        LEFT JOIN file_usage fu ON fu.file_id = f.id
        WHERE \(cases)
        GROUP BY ps.file_id
        LIMIT ?;
        """
        return try executeQuery(sql) { stmt, transient in
            var idx: Int32 = 1
            for t in pathTokens {
                _ = sqlite3_bind_text(stmt, idx, t, -1, transient)
                idx += 1
                _ = sqlite3_bind_text(stmt, idx, "\(t)%", -1, transient)
                idx += 1
            }
            _ = sqlite3_bind_int64(stmt, idx, Int64(limit))
        }
    }

    private func executeQuery(_ sql: String,
                              bind: (OpaquePointer?, sqlite3_destructor_type) -> Void) throws -> [Row] {
        guard let handle = database.rawHandle else { throw SearchError.closedDatabase }
        // F1: prepared-statement reuse. Same SQL string → same cached stmt;
        // we reset bindings on reuse. The number of distinct SQL strings is
        // bounded by the set of gram counts we emit (1..<k>), so the cache
        // stays small in practice.
        let stmt = try acquireStmt(sql, handle: handle)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        bind(stmt, transient)

        var out: [Row] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(handle))
                // Don't throw while holding the statement — reset first so
                // the next caller won't inherit a busy statement.
                sqlite3_reset(stmt)
                throw SearchError.stepFailed(step, msg, sql)
            }
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let isDir = sqlite3_column_int(stmt, 2) != 0
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = sqlite3_column_int64(stmt, 4)
            let nameLower = String(cString: sqlite3_column_text(stmt, 5))
            let pathLower = String(cString: sqlite3_column_text(stmt, 6))
            // H2: columns 7 / 8 come from `LEFT JOIN file_usage fu` and
            // are COALESCE'd to 0 when no row exists for this file.
            let openCount = sqlite3_column_int64(stmt, 7)
            let lastOpenedAt = sqlite3_column_int64(stmt, 8)
            out.append(Row(path: path,
                           name: name,
                           isDir: isDir,
                           size: size,
                           mtime: mtime,
                           nameLower: nameLower,
                           pathLower: pathLower,
                           openCount: openCount,
                           lastOpenedAt: lastOpenedAt))
        }
        return out
    }

    /// Look up an existing prepared statement for `sql` or compile one and
    /// cache it. Thread-safe: callers on the search queue and smoke tests
    /// on other threads can both go through this.
    private func acquireStmt(_ sql: String, handle: OpaquePointer) throws -> OpaquePointer {
        stmtLock.lock()
        if let hit = stmtCache[sql] {
            stmtCacheHits += 1
            stmtLock.unlock()
            return hit
        }
        stmtLock.unlock()

        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let prepared = stmt else {
            let msg = String(cString: sqlite3_errmsg(handle))
            if let stmt { sqlite3_finalize(stmt) }
            throw SearchError.prepareFailed(rc, msg, sql)
        }
        stmtLock.lock()
        if let race = stmtCache[sql] {
            // Another thread prepared the same SQL while we were compiling.
            // Keep the earlier one; finalize ours.
            stmtLock.unlock()
            sqlite3_finalize(prepared)
            return race
        }
        stmtCache[sql] = prepared
        stmtCacheMisses += 1
        stmtLock.unlock()
        return prepared
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
                                score: s,
                                openCount: row.openCount,
                                lastOpenedAt: row.lastOpenedAt)
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
            case .openCount:
                primary = compareInt(lhs.openCount, rhs.openCount, ascending: order.ascending)
            case .lastOpenedAt:
                primary = compareInt(lhs.lastOpenedAt, rhs.lastOpenedAt, ascending: order.ascending)
            }
            if primary != 0 { return primary < 0 }
            // H2 usage tie-break. Only kicks in when the primary key is
            // `.score` and two results tied on score — we want the
            // SwiftSeek-internal Run Count / last-opened signal to
            // break the tie so repeatedly-opened files climb. We do
            // NOT apply usage tie-break to non-score keys; users who
            // sort by `.name` / `.mtime` etc. expect the old behavior
            // (shorter-path + alpha) per the Codex H2 contract "不破
            // 坏现有 score/name/path/mtime/size 排序".
            if order.key == .score {
                if lhs.openCount != rhs.openCount {
                    // Higher open_count wins — this is never flipped
                    // by `order.ascending` because the primary key is
                    // still score; ascending there means "worst score
                    // first", tie-break semantics stay the same.
                    return lhs.openCount > rhs.openCount
                }
                if lhs.lastOpenedAt != rhs.lastOpenedAt {
                    return lhs.lastOpenedAt > rhs.lastOpenedAt
                }
            }
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
