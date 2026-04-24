import Foundation
import SwiftSeekCore

struct CLIArgs {
    var query: String?
    var dbPath: String?
    /// F2: nil = "fall back to the DB's persisted search_limit". Only set
    /// when the user explicitly passes `--limit N`, which keeps GUI and
    /// CLI on the same default without breaking scripts that rely on the
    /// override.
    var limitOverride: Int?
    var showScore: Bool = false
}

func printUsageAndExit() -> Never {
    let msg = """
    SwiftSeekSearch — search entry

    usage:
      swift run SwiftSeekSearch <query> [--db <path>] [--limit N] [--show-score]

    flags:
      --db <path>     Override database file (default: ~/Library/Application Support/SwiftSeek/index.sqlite3)
      --limit N       Maximum results. When omitted, reads the persisted
                      settings.search_limit (default 100) so CLI and GUI
                      agree on the same result cap.
      --show-score    Prepend score to each result line
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
        case "--limit":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { printUsageAndExit() }
            args.limitOverride = n
        case "--show-score":
            args.showScore = true
        default:
            if a.hasPrefix("-") {
                printUsageAndExit()
            }
            positional.append(a)
        }
        i += 1
    }
    // Allow multi-word queries: "swift run SwiftSeekSearch alpha notes"
    if !positional.isEmpty {
        args.query = positional.joined(separator: " ")
    }
    return args
}

let parsed = parse(CommandLine.arguments)
guard let rawQuery = parsed.query, !rawQuery.isEmpty else {
    printUsageAndExit()
}

let dbURL: URL
if let override = parsed.dbPath {
    dbURL = URL(fileURLWithPath: override)
} else {
    let paths = try AppPaths.ensureSupportDirectory()
    dbURL = paths.databaseURL
}

guard FileManager.default.fileExists(atPath: dbURL.path) else {
    FileHandle.standardError.write(Data("[SwiftSeekSearch] database not found: \(dbURL.path)\n".utf8))
    exit(1)
}

let db = try Database.open(at: dbURL)
try db.migrate()

FileHandle.standardError.write(Data("[SwiftSeekSearch] db=\(dbURL.path)\n".utf8))
FileHandle.standardError.write(Data("[SwiftSeekSearch] query=\(rawQuery) normalized=\(SearchEngine.normalize(rawQuery))\n".utf8))

let engine = SearchEngine(database: db)
// F2: CLI default limit now comes from the same settings.search_limit
// that the GUI respects. --limit N still wins when explicitly passed so
// pre-F2 scripts keep working.
let effectiveLimit: Int
if let override = parsed.limitOverride {
    effectiveLimit = override
} else {
    effectiveLimit = (try? db.getSearchLimit()) ?? SearchLimitBounds.defaultValue
}
FileHandle.standardError.write(Data("[SwiftSeekSearch] limit=\(effectiveLimit)\(parsed.limitOverride == nil ? " (from settings.search_limit)" : " (--limit override)")\n".utf8))
do {
    let start = Date()
    let results = try engine.search(rawQuery, options: .init(limit: effectiveLimit))
    let elapsed = Date().timeIntervalSince(start)
    FileHandle.standardError.write(Data("[SwiftSeekSearch] results=\(results.count) time=\(String(format: "%.3f", elapsed))s\n".utf8))
    for r in results {
        let prefix = parsed.showScore ? "[\(r.score)] " : ""
        let kind = r.isDir ? "d" : "f"
        print("\(prefix)\(kind) \(r.path)")
    }
    db.close()
    exit(0)
} catch {
    let msg = "[SwiftSeekSearch] error: \(error)\n"
    FileHandle.standardError.write(Data(msg.utf8))
    db.close()
    exit(1)
}
