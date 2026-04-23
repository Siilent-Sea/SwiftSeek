import Foundation
import CoreServices

/// Real FSEvents-backed watcher. Each underlying file-system event is pushed
/// to an `EventQueue`, which handles debounce + de-dup before calling back
/// into the rescan pipeline.
public final class IncrementalWatcher: @unchecked Sendable {
    public struct Options {
        public var latency: TimeInterval
        public var useFileEvents: Bool

        public init(latency: TimeInterval = 0.1,
                    useFileEvents: Bool = true) {
            self.latency = latency
            self.useFileEvents = useFileEvents
        }
    }

    private let roots: [String]
    private let eventQueue: EventQueue
    private let options: Options
    private let dispatch: DispatchQueue

    private var stream: FSEventStreamRef?
    private var selfRefHolder: Unmanaged<IncrementalWatcher>?

    public init(roots: [String],
                eventQueue: EventQueue,
                options: Options = .init()) {
        self.roots = roots
        self.eventQueue = eventQueue
        self.options = options
        self.dispatch = DispatchQueue(label: "swiftseek.watcher", qos: .utility)
    }

    deinit {
        stop()
    }

    public var isRunning: Bool { stream != nil && started }

    private var started: Bool = false

    /// Attempt to subscribe to FSEvents for `roots`. Returns `true` if the
    /// stream was created AND `FSEventStreamStart` reported success; `false`
    /// on any failure (create returned nil, start returned false, empty roots,
    /// or already running). Callers must treat `false` as "FSEvents did not
    /// come up" and rely on a secondary source (e.g. `PollingWatcher`).
    @discardableResult
    public func start(since eventId: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)) -> Bool {
        guard stream == nil else { return started }
        guard !roots.isEmpty else { return false }

        // Retain `self` while the stream is alive so the C callback can safely
        // grab us via the info pointer.
        let unmanaged = Unmanaged<IncrementalWatcher>.passRetained(self)
        self.selfRefHolder = unmanaged

        var context = FSEventStreamContext(
            version: 0,
            info: unmanaged.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Always request CFArray-of-CFString paths so the callback can bridge
        // `eventPaths` straight to `[String]`. Without this flag FSEvents hands
        // us a raw `const char *const[]` and `as? [String]` segfaults.
        var flags: FSEventStreamCreateFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        if options.useFileEvents {
            flags |= FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        }

        let cfPaths = roots as CFArray
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            watcherCallback,
            &context,
            cfPaths,
            eventId,
            options.latency,
            flags
        ) else {
            unmanaged.release()
            selfRefHolder = nil
            return false
        }

        FSEventStreamSetDispatchQueue(s, dispatch)
        let ok = FSEventStreamStart(s)
        if !ok {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            unmanaged.release()
            selfRefHolder = nil
            return false
        }
        self.stream = s
        self.started = true
        return true
    }

    public func stop() {
        guard let s = stream else { return }
        if started {
            FSEventStreamStop(s)
        }
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        self.stream = nil
        self.started = false
        selfRefHolder?.release()
        selfRefHolder = nil
    }

    fileprivate func handle(paths: [String]) {
        guard !paths.isEmpty else { return }
        eventQueue.enqueue(paths)
    }
}

private func watcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<IncrementalWatcher>.fromOpaque(info).takeUnretainedValue()

    let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    guard let paths = cfArray as? [String] else { return }
    watcher.handle(paths: paths)
}
