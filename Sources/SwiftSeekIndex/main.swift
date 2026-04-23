import Foundation
import SwiftSeekCore

struct CLIArgs {
    var root: String?
    var dbPath: String?
    var batch: Int = 500
    var progressEvery: Int = 500
    var verbose: Bool = false
    var cancelAfterMs: Int? = nil
    var clearBeforeIndex: Bool = true
    var watch: Bool = false
    var watchSeconds: Double? = nil
    var debounceMs: Int = 200
    var pollSeconds: Double = 1.0
    var disablePoll: Bool = false
}

func printUsageAndExit() -> Never {
    let msg = """
    SwiftSeekIndex — P1 first full index + P3 incremental watch

    usage:
      swift run SwiftSeekIndex <rootPath> [--db <path>] [--batch N] [--progress N] [--verbose] [--no-clear] [--cancel-after-ms N] [--watch | --watch-seconds N] [--debounce-ms N]

    flags:
      --db <path>              Override database file (default: ~/Library/Application Support/SwiftSeek/index.sqlite3)
      --batch N                Batch size for insert (default 500)
      --progress N             Emit progress every N scanned items (default 500)
      --verbose                Log every progress and every batch flush to stderr
      --no-clear               Do not delete existing rows under root before index
      --cancel-after-ms N      Fire cancel N milliseconds after start (dev/acceptance aid)
      --watch                  After initial index, keep running and apply FSEvents-driven incremental rescans until Ctrl-C
      --watch-seconds N        Same as --watch but exit automatically after N seconds (may be fractional)
      --debounce-ms N          Event-queue debounce window in ms (default 200)
      --poll-seconds N         PollingWatcher interval seconds (default 1.0, fractional ok)
      --no-poll                Disable PollingWatcher fallback (FSEvents only)

    press Ctrl-C during indexing or watching to stop.
    """
    FileHandle.standardError.write(Data(msg.utf8))
    FileHandle.standardError.write(Data("\n".utf8))
    exit(2)
}

func parse(_ argv: [String]) -> CLIArgs {
    var args = CLIArgs()
    var positional: [String] = []
    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "-h", "--help":
            printUsageAndExit()
        case "--db":
            i += 1
            guard i < argv.count else { printUsageAndExit() }
            args.dbPath = argv[i]
        case "--batch":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { printUsageAndExit() }
            args.batch = n
        case "--progress":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { printUsageAndExit() }
            args.progressEvery = n
        case "--verbose":
            args.verbose = true
        case "--no-clear":
            args.clearBeforeIndex = false
        case "--cancel-after-ms":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n >= 0 else { printUsageAndExit() }
            args.cancelAfterMs = n
        case "--watch":
            args.watch = true
        case "--watch-seconds":
            i += 1
            guard i < argv.count, let n = Double(argv[i]), n >= 0 else { printUsageAndExit() }
            args.watch = true
            args.watchSeconds = n
        case "--debounce-ms":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n >= 0 else { printUsageAndExit() }
            args.debounceMs = n
        case "--poll-seconds":
            i += 1
            guard i < argv.count, let n = Double(argv[i]), n > 0 else { printUsageAndExit() }
            args.pollSeconds = n
        case "--no-poll":
            args.disablePoll = true
        default:
            if a.hasPrefix("-") {
                printUsageAndExit()
            }
            positional.append(a)
        }
        i += 1
    }
    args.root = positional.first
    return args
}

let argv = CommandLine.arguments
let parsed = parse(argv)

guard let rootArg = parsed.root else {
    printUsageAndExit()
}

let rootURL = URL(fileURLWithPath: rootArg).standardizedFileURL

let dbURL: URL
if let override = parsed.dbPath {
    let overrideURL = URL(fileURLWithPath: override)
    try FileManager.default.createDirectory(at: overrideURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    dbURL = overrideURL
} else {
    let paths = try AppPaths.ensureSupportDirectory()
    dbURL = paths.databaseURL
}

FileHandle.standardError.write(Data("[SwiftSeekIndex] root=\(rootURL.path)\n".utf8))
FileHandle.standardError.write(Data("[SwiftSeekIndex] db=\(dbURL.path)\n".utf8))

let db = try Database.open(at: dbURL)
try db.migrate()

let cancel = CancellationToken()

// Trap SIGINT. DispatchSource handles SIGINT cleanly without losing the signal.
signal(SIGINT, SIG_IGN)
let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signalSource.setEventHandler {
    FileHandle.standardError.write(Data("\n[SwiftSeekIndex] SIGINT received — cancelling\n".utf8))
    cancel.cancel()
}
signalSource.resume()

// Optional dev timer cancel for reproducible cancel tests
var timer: DispatchSourceTimer?
if let ms = parsed.cancelAfterMs {
    let t = DispatchSource.makeTimerSource(queue: .global())
    t.schedule(deadline: .now() + .milliseconds(ms))
    t.setEventHandler {
        FileHandle.standardError.write(Data("[SwiftSeekIndex] --cancel-after-ms fired\n".utf8))
        cancel.cancel()
    }
    t.resume()
    timer = t
}

let indexer = Indexer(database: db)

do {
    let stats = try indexer.indexRoot(
        rootURL,
        options: .init(
            batchSize: parsed.batch,
            progressEvery: parsed.progressEvery,
            clearBeforeIndex: parsed.clearBeforeIndex
        ),
        cancel: cancel,
        progress: { p in
            if parsed.verbose {
                let line = "[progress] scanned=\(p.scanned) inserted=\(p.inserted) path=\(p.currentPath)\n"
                FileHandle.standardError.write(Data(line.utf8))
            } else {
                let line = "[progress] scanned=\(p.scanned) inserted=\(p.inserted)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
    )
    timer?.cancel()
    signalSource.cancel()

    let summary = stats.description
    print(summary)

    let rootsCount = (try? db.countRows(in: "roots")) ?? -1
    let filesCount = (try? db.countRows(in: "files")) ?? -1
    print("db: roots=\(rootsCount) files=\(filesCount)")

    if parsed.watch, !stats.cancelled {
        let debounce = TimeInterval(parsed.debounceMs) / 1000.0
        let rootPath = stats.rootPath

        let queue = EventQueue(options: .init(debounce: debounce)) { batch in
            let coalesced = batch.sorted()
            FileHandle.standardError.write(Data("[watch] batch size=\(batch.count) sample=\(coalesced.prefix(3))\n".utf8))
            do {
                let rescan = try indexer.rescanPaths(batch)
                FileHandle.standardError.write(Data("\(rescan)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("[watch] rescan error: \(error)\n".utf8))
            }
        }
        let watcher = IncrementalWatcher(
            roots: [rootPath],
            eventQueue: queue,
            options: .init(latency: 0.1, useFileEvents: true)
        )
        let fsStarted = watcher.start()
        FileHandle.standardError.write(Data("[watch] FSEvents start=\(fsStarted)\n".utf8))

        var pollingWatcher: PollingWatcher? = nil
        if !parsed.disablePoll {
            let pw = PollingWatcher(
                roots: [rootPath],
                eventQueue: queue,
                options: .init(interval: parsed.pollSeconds)
            )
            pw.start()
            pollingWatcher = pw
            FileHandle.standardError.write(Data("[watch] polling started interval=\(parsed.pollSeconds)s\n".utf8))
        }
        FileHandle.standardError.write(Data("[watch] started root=\(rootPath) debounce=\(debounce)s fsevents=\(fsStarted) polling=\(pollingWatcher != nil)\n".utf8))

        let watchCancel = CancellationToken()
        signal(SIGINT, SIG_IGN)
        let watchSignal = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        watchSignal.setEventHandler {
            FileHandle.standardError.write(Data("\n[watch] SIGINT received — stopping\n".utf8))
            watchCancel.cancel()
        }
        watchSignal.resume()

        var watchTimer: DispatchSourceTimer?
        if let seconds = parsed.watchSeconds {
            let t = DispatchSource.makeTimerSource(queue: .global())
            t.schedule(deadline: .now() + seconds)
            t.setEventHandler {
                FileHandle.standardError.write(Data("[watch] --watch-seconds elapsed\n".utf8))
                watchCancel.cancel()
            }
            t.resume()
            watchTimer = t
        }

        while !watchCancel.isCancelled {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        watcher.stop()
        pollingWatcher?.stop()
        queue.stop()
        watchTimer?.cancel()
        watchSignal.cancel()

        let finalRoots = (try? db.countRows(in: "roots")) ?? -1
        let finalFiles = (try? db.countRows(in: "files")) ?? -1
        print("[watch] stopped. db: roots=\(finalRoots) files=\(finalFiles)")
    }

    db.close()
    exit(stats.cancelled ? 130 : 0)
} catch {
    timer?.cancel()
    signalSource.cancel()
    let msg = "[SwiftSeekIndex] error: \(error)\n"
    FileHandle.standardError.write(Data(msg.utf8))
    db.close()
    exit(1)
}
