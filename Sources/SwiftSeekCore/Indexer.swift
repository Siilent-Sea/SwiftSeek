import Foundation

public enum IndexerError: Error, CustomStringConvertible {
    case rootNotFound(String)
    case rootNotDirectory(String)

    public var description: String {
        switch self {
        case let .rootNotFound(path): return "root not found: \(path)"
        case let .rootNotDirectory(path): return "root not a directory: \(path)"
        }
    }
}

public final class Indexer {
    public struct Options {
        public var batchSize: Int
        public var progressEvery: Int
        public var clearBeforeIndex: Bool
        /// Canonicalised directory paths to skip during walk. Matched by exact
        /// equality or strict descendant (`path.hasPrefix(pattern + "/")`).
        public var excludes: [String]
        /// When false, any path with a dot-prefixed component is skipped.
        public var includeHiddenFiles: Bool

        public init(batchSize: Int = 500,
                    progressEvery: Int = 500,
                    clearBeforeIndex: Bool = true,
                    excludes: [String] = [],
                    includeHiddenFiles: Bool = false) {
            self.batchSize = batchSize
            self.progressEvery = progressEvery
            self.clearBeforeIndex = clearBeforeIndex
            self.excludes = excludes
            self.includeHiddenFiles = includeHiddenFiles
        }
    }

    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    @discardableResult
    public func indexRoot(_ rootURL: URL,
                          options: Options = .init(),
                          cancel: CancellationToken = .init(),
                          progress: (IndexProgress) -> Void = { _ in }) throws -> IndexStats {
        let fm = FileManager.default
        let rootPath = Indexer.canonicalize(path: rootURL.path)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootPath, isDirectory: &isDir) else {
            throw IndexerError.rootNotFound(rootPath)
        }
        guard isDir.boolValue else {
            throw IndexerError.rootNotDirectory(rootPath)
        }

        _ = try database.registerRoot(path: rootPath)
        if options.clearBeforeIndex {
            try database.clearFiles(underRoot: rootPath)
        }

        let start = Date()
        var scanned = 0
        var inserted = 0
        var skipped = 0
        var batch: [FileRow] = []
        batch.reserveCapacity(options.batchSize)

        if let rootRow = makeRow(url: URL(fileURLWithPath: rootPath, isDirectory: true)) {
            batch.append(rootRow)
            scanned += 1
        } else {
            skipped += 1
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let opts: FileManager.DirectoryEnumerationOptions = []
        let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: rootPath, isDirectory: true),
            includingPropertiesForKeys: keys,
            options: opts,
            errorHandler: { _, _ in true }
        )

        var cancelled = false
        walkLoop: while let next = enumerator?.nextObject() as? URL {
            if cancel.isCancelled {
                cancelled = true
                break walkLoop
            }

            let candidatePath = next.path
            if ExcludeFilter.isExcluded(candidatePath, patterns: options.excludes) {
                // Don't descend into excluded directories.
                if (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                skipped += 1
                continue
            }
            if !options.includeHiddenFiles && HiddenPath.isHidden(candidatePath) {
                if (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                skipped += 1
                continue
            }

            if let row = makeRow(url: next) {
                batch.append(row)
                scanned += 1
            } else {
                skipped += 1
                continue
            }

            if batch.count >= options.batchSize {
                try database.insertFiles(batch)
                inserted += batch.count
                batch.removeAll(keepingCapacity: true)
            }

            if scanned % options.progressEvery == 0 {
                progress(IndexProgress(scanned: scanned, inserted: inserted, currentPath: next.path))
            }
        }

        if !cancelled, !batch.isEmpty {
            try database.insertFiles(batch)
            inserted += batch.count
            batch.removeAll(keepingCapacity: true)
        }

        progress(IndexProgress(scanned: scanned, inserted: inserted, currentPath: rootPath))

        return IndexStats(
            rootPath: rootPath,
            scanned: scanned,
            inserted: inserted,
            skipped: skipped,
            cancelled: cancelled,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }

    public static func canonicalize(path: String) -> String {
        return path.withCString { cstr in
            guard let resolved = realpath(cstr, nil) else {
                return path
            }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    private func makeRow(url: URL) -> FileRow? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        let isDir = values.isDirectory ?? false
        let size = Int64(values.fileSize ?? 0)
        let mtime = Int64((values.contentModificationDate ?? Date(timeIntervalSince1970: 0))
            .timeIntervalSince1970)
        return FileRow.from(url: url, isDir: isDir, size: size, mtime: mtime)
    }

    // MARK: - P3 incremental rescan

    /// Apply a debounced batch of filesystem changes to the database.
    ///
    /// For each input path:
    ///   - missing path → delete the row (and any descendants, for a removed dir).
    ///   - existing file → upsert a single row.
    ///   - existing dir  → walk the subtree, upsert every row, then prune DB rows
    ///                     that are no longer on disk. This is the "fallback" dir
    ///                     rescan referenced in `docs/next_stage.md` — it stays
    ///                     bounded because the watcher only hands us paths that
    ///                     actually changed, never the whole root.
    ///
    /// Paths that are strict ancestors of other input paths absorb them, so a
    /// directory-level event plus a file-level event inside that directory costs
    /// exactly one dir walk instead of duplicating work.
    @discardableResult
    public func rescanPaths(_ paths: Set<String>,
                            batchSize: Int = 500,
                            excludes: [String] = [],
                            includeHiddenFiles: Bool = true) throws -> RescanStats {
        var stats = RescanStats()
        guard !paths.isEmpty else { return stats }
        let fm = FileManager.default
        let coalesced = Indexer.coalescePrefixes(paths)
        for path in coalesced {
            let canonical = Indexer.canonicalize(path: path)
            // Skip paths that are excluded or (when hidden files are off) hidden.
            // For excluded dirs we still want to delete any row that lingered from
            // before the exclude was added; that is handled by the explicit
            // purgeExcluded path, NOT by routine rescans.
            if ExcludeFilter.isExcluded(canonical, patterns: excludes) {
                continue
            }
            if !includeHiddenFiles && HiddenPath.isHidden(canonical) {
                continue
            }
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: canonical, isDirectory: &isDir)
            if !exists {
                let removed = try database.deleteFiles(atOrUnderPath: canonical)
                stats.deleted += removed
                stats.processed += 1
                continue
            }
            if isDir.boolValue {
                try rescanDirectory(canonical,
                                    batchSize: batchSize,
                                    excludes: excludes,
                                    includeHiddenFiles: includeHiddenFiles,
                                    stats: &stats)
            } else {
                if let row = makeRow(url: URL(fileURLWithPath: canonical)) {
                    try database.insertFiles([row])
                    stats.upserted += 1
                }
                stats.processed += 1
            }
        }
        return stats
    }

    private func rescanDirectory(_ dir: String,
                                 batchSize: Int,
                                 excludes: [String] = [],
                                 includeHiddenFiles: Bool = true,
                                 stats: inout RescanStats) throws {
        let known = try Set(database.pathsAtOrUnder(dir))
        var seen = Set<String>()
        var batch: [FileRow] = []
        batch.reserveCapacity(batchSize)

        let rootURL = URL(fileURLWithPath: dir, isDirectory: true)
        if let rootRow = makeRow(url: rootURL) {
            batch.append(rootRow)
            seen.insert(rootRow.path)
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        )
        while let next = enumerator?.nextObject() as? URL {
            let p = next.path
            if ExcludeFilter.isExcluded(p, patterns: excludes) {
                if (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            if !includeHiddenFiles && HiddenPath.isHidden(p) {
                if (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            if let row = makeRow(url: next) {
                batch.append(row)
                seen.insert(row.path)
            }
            if batch.count >= batchSize {
                try database.insertFiles(batch)
                stats.upserted += batch.count
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            try database.insertFiles(batch)
            stats.upserted += batch.count
        }

        let gone = known.subtracting(seen)
        if !gone.isEmpty {
            for p in gone {
                let removed = try database.deleteFiles(atOrUnderPath: p)
                stats.deleted += removed
            }
        }
        stats.fallbackDirs += 1
        stats.processed += 1
    }

    /// Drop any path in `paths` that is a strict descendant of another path in
    /// the same set. Produces a canonicalised list sorted for deterministic
    /// processing order. "Descendant" means `p.hasPrefix(ancestor + "/")`.
    public static func coalescePrefixes(_ paths: Set<String>) -> [String] {
        let sorted = paths.sorted()
        var kept: [String] = []
        kept.reserveCapacity(sorted.count)
        for p in sorted {
            if let last = kept.last {
                if p == last { continue }
                if p.hasPrefix(last + "/") { continue }
            }
            kept.append(p)
        }
        return kept
    }
}

public struct RescanStats: CustomStringConvertible {
    public var processed: Int = 0
    public var upserted: Int = 0
    public var deleted: Int = 0
    public var fallbackDirs: Int = 0

    public init(processed: Int = 0,
                upserted: Int = 0,
                deleted: Int = 0,
                fallbackDirs: Int = 0) {
        self.processed = processed
        self.upserted = upserted
        self.deleted = deleted
        self.fallbackDirs = fallbackDirs
    }

    public var description: String {
        return "[rescan] processed=\(processed) upserted=\(upserted) deleted=\(deleted) fallbackDirs=\(fallbackDirs)"
    }
}
