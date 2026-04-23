import Foundation

/// Filesystem watcher of last resort. Periodically walks every root, builds a
/// `{path -> mtime}` snapshot, diffs against the previous snapshot and pushes
/// changed / appeared / disappeared paths into an `EventQueue`.
///
/// Why this exists alongside `IncrementalWatcher`:
///   - FSEvents depends on the `com.apple.FSEvents.client` mach service. Some
///     execution sandboxes (notably `codex exec`'s workspace-write profile)
///     deny that service, so `FSEventStreamStart` either returns `false` or
///     delivers no events at all.
///   - Polling is dumb, slow, CPU-hungry at short intervals, but it uses only
///     ordinary file-metadata syscalls that every sandbox permits.
/// The CLI runs both watchers in parallel; whichever surfaces a change first
/// wakes the `EventQueue`, which de-dupes by path, so a single change costs at
/// most one rescan even when both backends observe it.
public final class PollingWatcher: @unchecked Sendable {
    public struct Options {
        public var interval: TimeInterval
        public var label: String
        public var excludes: [String]
        public var includeHiddenFiles: Bool

        public init(interval: TimeInterval = 1.0,
                    label: String = "swiftseek.pollingwatcher",
                    excludes: [String] = [],
                    includeHiddenFiles: Bool = true) {
            self.interval = interval
            self.label = label
            self.excludes = excludes
            self.includeHiddenFiles = includeHiddenFiles
        }
    }

    private let roots: [String]
    private let eventQueue: EventQueue
    private let options: Options
    private let queue: DispatchQueue

    private var timer: DispatchSourceTimer?
    private var snapshot: [String: Int64] = [:]
    private var started: Bool = false

    public init(roots: [String],
                eventQueue: EventQueue,
                options: Options = .init()) {
        self.roots = roots.map { Self.canonicalize($0) }
        self.eventQueue = eventQueue
        self.options = options
        self.queue = DispatchQueue(label: options.label, qos: .utility)
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        var running = false
        queue.sync { running = started }
        return running
    }

    public func start() {
        queue.sync {
            guard !started else { return }
            guard !roots.isEmpty else { return }
            snapshot = currentSnapshot()
            started = true
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + options.interval,
                       repeating: options.interval,
                       leeway: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
    }

    public func stop() {
        queue.sync {
            guard started else { return }
            started = false
            timer?.cancel()
            timer = nil
        }
    }

    /// Force one scan cycle. Exposed mostly for tests / CLI so a caller can
    /// synchronously flush a diff without waiting for the next `interval`
    /// boundary.
    public func pollOnce() {
        queue.sync {
            guard started else { return }
        }
        queue.sync {
            self.tick()
        }
    }

    private func tick() {
        let fresh = currentSnapshot()
        var changed: Set<String> = []
        // New or modified
        for (path, mtime) in fresh {
            if let prev = snapshot[path] {
                if prev != mtime { changed.insert(path) }
            } else {
                changed.insert(path)
            }
        }
        // Disappeared
        for path in snapshot.keys where fresh[path] == nil {
            changed.insert(path)
        }
        snapshot = fresh
        if !changed.isEmpty {
            eventQueue.enqueue(Array(changed))
        }
    }

    private func currentSnapshot() -> [String: Int64] {
        var out: [String: Int64] = [:]
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir) else { continue }
            let rootURL = URL(fileURLWithPath: root, isDirectory: isDir.boolValue)
            if let stamp = stamp(of: rootURL) { out[root] = stamp }
            guard isDir.boolValue else { continue }
            let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            )
            while let next = enumerator?.nextObject() as? URL {
                let p = next.path
                if ExcludeFilter.isExcluded(p, patterns: options.excludes) {
                    if (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator?.skipDescendants()
                    }
                    continue
                }
                if !options.includeHiddenFiles && HiddenPath.isHidden(p) {
                    if (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator?.skipDescendants()
                    }
                    continue
                }
                if let s = stamp(of: next) { out[p] = s }
            }
        }
        return out
    }

    private func stamp(of url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        // Mix mtime + size into a single 64-bit "version" key. mtime alone
        // misses quick overwrites that keep the same second; size alone misses
        // same-length edits. Combining cuts the false-negative rate enough for
        // a 1s poll interval without needing a real hash.
        let mtime = Int64((values.contentModificationDate ?? Date(timeIntervalSince1970: 0))
            .timeIntervalSince1970 * 1000)
        let size = Int64(values.fileSize ?? 0)
        return mtime ^ (size &* 1_000_003)
    }

    private static func canonicalize(_ path: String) -> String {
        return path.withCString { cstr in
            guard let resolved = realpath(cstr, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
