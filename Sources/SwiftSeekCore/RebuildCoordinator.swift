import Foundation

/// Orchestrates a full "rebuild index" cycle triggered from the Settings →
/// Maintenance tab or programmatically.
///
/// Why this class exists:
///   - There are two callers that want to "walk all enabled roots and refresh
///     the DB": the GUI button and smoke tests. Both need the same rules
///     (read excludes + hidden toggle from settings, clear-before-index, etc.),
///     so we extract them here instead of duplicating in both.
///   - Concurrent presses of the rebuild button must not run multiple walkers.
///     The `state` lock + `isRebuilding` flag guarantee at most one cycle at
///     any time and surfaces "already running" to the caller.
///   - On finish the coordinator stamps `settings.last_rebuild_*` so the
///     Diagnostics tab can show an audit trail without needing a separate
///     NotificationCenter listener.
///
/// Design decisions:
///   - Runs on a dedicated background DispatchQueue so the caller returns
///     immediately; a `progress` callback fires on that queue (the UI should
///     hop back to main itself).
///   - Does NOT try to pause watchers during the walk — `Indexer.indexRoot`
///     wraps every batch in `BEGIN IMMEDIATE` so a concurrent watcher-driven
///     `rescanPaths` blocks on the SQLite lock rather than corrupting state.
public final class RebuildCoordinator: @unchecked Sendable {
    public struct Progress: Sendable {
        public var rootPath: String
        public var rootIndex: Int
        public var rootCount: Int
        public var indexProgress: IndexProgress

        public init(rootPath: String,
                    rootIndex: Int,
                    rootCount: Int,
                    indexProgress: IndexProgress) {
            self.rootPath = rootPath
            self.rootIndex = rootIndex
            self.rootCount = rootCount
            self.indexProgress = indexProgress
        }
    }

    public struct Summary: Sendable {
        public var totalScanned: Int
        public var totalInserted: Int
        public var totalSkipped: Int
        public var roots: Int
        public var durationSeconds: TimeInterval
        public var error: String?

        public init(totalScanned: Int = 0,
                    totalInserted: Int = 0,
                    totalSkipped: Int = 0,
                    roots: Int = 0,
                    durationSeconds: TimeInterval = 0,
                    error: String? = nil) {
            self.totalScanned = totalScanned
            self.totalInserted = totalInserted
            self.totalSkipped = totalSkipped
            self.roots = roots
            self.durationSeconds = durationSeconds
            self.error = error
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case rebuilding(startedAt: Date, processedRoots: Int, totalRoots: Int)
    }

    private let database: Database
    private let queue = DispatchQueue(label: "swiftseek.rebuild", qos: .utility)
    private let stateLock = NSLock()
    private var _state: State = .idle

    /// UI observer. Fires on every state transition. Called on the rebuild
    /// worker queue — observer is responsible for hopping to main if needed.
    public var onStateChange: ((State) -> Void)?

    public init(database: Database) {
        self.database = database
    }

    public var state: State {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    private func updateState(_ newValue: State) {
        stateLock.lock()
        _state = newValue
        stateLock.unlock()
        onStateChange?(newValue)
    }

    public var isRebuilding: Bool {
        if case .rebuilding = state { return true }
        return false
    }

    /// Kick off a rebuild. Returns false if one is already in flight (caller
    /// should surface that as "already running" rather than silently retrying).
    @discardableResult
    public func rebuild(onProgress: @escaping (Progress) -> Void = { _ in },
                        onFinish: @escaping (Summary) -> Void = { _ in }) -> Bool {
        stateLock.lock()
        if case .rebuilding = _state {
            stateLock.unlock()
            return false
        }
        stateLock.unlock()
        let startedAt = Date()
        updateState(.rebuilding(startedAt: startedAt, processedRoots: 0, totalRoots: 0))

        queue.async { [weak self] in
            guard let self else { return }
            let start = Date()
            var summary = Summary()
            do {
                let allRoots = try self.database.listRoots()
                let enabled = allRoots.filter { $0.enabled }
                summary.roots = enabled.count

                self.updateState(.rebuilding(startedAt: startedAt,
                                             processedRoots: 0,
                                             totalRoots: enabled.count))

                if enabled.isEmpty {
                    summary.durationSeconds = Date().timeIntervalSince(start)
                    do { try self.stampResult(summary: summary, startedAt: startedAt) }
                catch { NSLog("SwiftSeek: RebuildCoordinator stampResult failed: \(error)") }
                    self.finish(summary)
                    onFinish(summary)
                    return
                }

                let excludes = try self.database.listExcludes().map { $0.pattern }
                let includeHidden = try self.database.getHiddenFilesEnabled()
                let indexer = Indexer(database: self.database)

                for (idx, root) in enabled.enumerated() {
                    let rootURL = URL(fileURLWithPath: root.path, isDirectory: true)
                    let stats = try indexer.indexRoot(
                        rootURL,
                        options: .init(batchSize: 500,
                                       progressEvery: 500,
                                       clearBeforeIndex: true,
                                       excludes: excludes,
                                       includeHiddenFiles: includeHidden),
                        progress: { ip in
                            onProgress(Progress(rootPath: root.path,
                                                rootIndex: idx + 1,
                                                rootCount: enabled.count,
                                                indexProgress: ip))
                        }
                    )
                    summary.totalScanned += stats.scanned
                    summary.totalInserted += stats.inserted
                    summary.totalSkipped += stats.skipped

                    self.updateState(.rebuilding(startedAt: startedAt,
                                                 processedRoots: idx + 1,
                                                 totalRoots: enabled.count))
                }

                summary.durationSeconds = Date().timeIntervalSince(start)
                do { try self.stampResult(summary: summary, startedAt: startedAt) }
                catch { NSLog("SwiftSeek: RebuildCoordinator stampResult failed: \(error)") }
            } catch {
                summary.durationSeconds = Date().timeIntervalSince(start)
                summary.error = "\(error)"
                do { try self.stampResult(summary: summary, startedAt: startedAt) }
                catch { NSLog("SwiftSeek: RebuildCoordinator stampResult failed: \(error)") }
            }
            self.finish(summary)
            onFinish(summary)
        }
        return true
    }

    private func finish(_ summary: Summary) {
        updateState(.idle)
        _ = summary
    }

    private func stampResult(summary: Summary, startedAt: Date) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        try database.setSetting(SettingsKey.lastRebuildAt, value: iso.string(from: startedAt))
        if let err = summary.error {
            try database.setSetting(SettingsKey.lastRebuildResult, value: "failed: \(err)")
        } else {
            try database.setSetting(SettingsKey.lastRebuildResult, value: "success")
        }
        let stats = "roots=\(summary.roots) scanned=\(summary.totalScanned) inserted=\(summary.totalInserted) skipped=\(summary.totalSkipped) duration=\(String(format: "%.2f", summary.durationSeconds))s"
        try database.setSetting(SettingsKey.lastRebuildStats, value: stats)
    }
}
