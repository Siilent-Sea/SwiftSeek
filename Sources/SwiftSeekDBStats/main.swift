// G1 — DB footprint / maintenance CLI.
//
// usage:
//   swift run SwiftSeekDBStats [--db <path>] [--run <op>] [--yes]
//
// flags:
//   --db <path>   override default DB (~/Library/Application Support/SwiftSeek/index.sqlite3)
//   --run <op>    op ∈ {checkpoint, optimize, vacuum}. Defaults to
//                 read-only stats if omitted. vacuum requires --yes
//                 to confirm the risk banner.
//   --yes         bypass the VACUUM confirmation banner (script use).
//
// exits 0 on success, 2 on bad args, 1 on maintenance failure.

import Foundation
import SwiftSeekCore

// stdout line-buffering so `swift run SwiftSeekDBStats` streams output
// even when redirected to a file.
setlinebuf(stdout)

struct Args {
    var dbPath: String?
    var maintenance: MaintenanceKind?
    var confirmVacuum: Bool = false
}

func printUsageAndExit() -> Never {
    let msg = """
    SwiftSeekDBStats — G1 footprint observability

    usage:
      swift run SwiftSeekDBStats [--db <path>] [--run <op>] [--yes]

    flags:
      --db <path>   Override DB path
      --run <op>    One of checkpoint | optimize | vacuum
      --yes         Bypass the VACUUM confirmation prompt (script use)
    """
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(2)
}

func parse(_ argv: [String]) -> Args {
    var out = Args()
    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "-h", "--help":
            printUsageAndExit()
        case "--db":
            i += 1
            guard i < argv.count else { printUsageAndExit() }
            out.dbPath = argv[i]
        case "--run":
            i += 1
            guard i < argv.count, let k = MaintenanceKind(rawValue: argv[i])
            else { printUsageAndExit() }
            out.maintenance = k
        case "--yes":
            out.confirmVacuum = true
        default:
            FileHandle.standardError.write(Data("unknown arg: \(a)\n".utf8))
            printUsageAndExit()
        }
        i += 1
    }
    return out
}

let args = parse(CommandLine.arguments)

let dbURL: URL
if let override = args.dbPath {
    dbURL = URL(fileURLWithPath: override)
} else {
    let paths = try AppPaths.ensureSupportDirectory()
    dbURL = paths.databaseURL
}

guard FileManager.default.fileExists(atPath: dbURL.path) else {
    FileHandle.standardError.write(Data("[SwiftSeekDBStats] db not found: \(dbURL.path)\n".utf8))
    exit(1)
}

let db = try Database.open(at: dbURL)
// migrate() is the read-consistency path; safe to call and returns fast
// when already current. We don't introduce new schema in G1.
try db.migrate()

// --- Print stats header (always) -------------------------------------
print("DB: \(dbURL.path)")
print("schema: \(db.schemaVersion)")
print("—")

let stats = db.computeStats()

print("file sizes:")
print("  main : \(DatabaseStats.humanBytes(stats.mainFileBytes))")
print("  wal  : \(DatabaseStats.humanBytes(stats.walFileBytes))")
print("  shm  : \(DatabaseStats.humanBytes(stats.shmFileBytes))")
print("pages:")
print("  page_count : \(DatabaseStats.humanCount(stats.pageCount))")
print("  page_size  : \(DatabaseStats.humanBytes(stats.pageSize))")
print("rows:")
print("  files        : \(DatabaseStats.humanCount(stats.filesRowCount))")
print("  file_grams   : \(DatabaseStats.humanCount(stats.fileGramsRowCount))")
print("  file_bigrams : \(DatabaseStats.humanCount(stats.fileBigramsRowCount))")
print("  roots        : \(DatabaseStats.humanCount(stats.rootsRowCount))")
print("  excludes     : \(DatabaseStats.humanCount(stats.excludesRowCount))")
print("  settings     : \(DatabaseStats.humanCount(stats.settingsRowCount))")
print("  file_usage   : \(DatabaseStats.humanCount(stats.fileUsageRowCount))")
print("derived:")
print("  avg grams/file   : \(DatabaseStats.humanAvg(stats.avgGramsPerFile))")
print("  avg bigrams/file : \(DatabaseStats.humanAvg(stats.avgBigramsPerFile))")

if let per = stats.perTable, !per.isEmpty {
    print("per-table (via dbstat or fallback):")
    for row in per {
        let bytes = DatabaseStats.humanBytes(row.approxBytes)
        let pages = DatabaseStats.humanCount(row.pageCount)
        print("  \(row.name.padding(toLength: 14, withPad: " ", startingAt: 0))  \(bytes.padding(toLength: 10, withPad: " ", startingAt: 0))  pages=\(pages)")
    }
} else {
    print("per-table: unavailable")
}

// --- Optional maintenance -------------------------------------------
if let kind = args.maintenance {
    if kind == .vacuum && !args.confirmVacuum {
        let warning = """

        ⚠  VACUUM is a potentially long, disk-intensive operation.

        Before proceeding:
          • Quit any other SwiftSeek GUI / CLI using this DB.
          • VACUUM writes a full rebuilt copy alongside the original
            and then swaps — ensure free space at least equal to the
            current DB size (\(DatabaseStats.humanBytes(stats.mainFileBytes))).
          • Expect multi-minute durations on 500k+ file indexes.

        Re-run with --yes to confirm.

        """
        FileHandle.standardError.write(Data(warning.utf8))
        exit(1)
    }
    print("—")
    print("running maintenance: \(kind.rawValue) …")
    let result = db.runMaintenance(kind)
    if let err = result.error {
        print("failed after \(String(format: "%.2fs", result.durationSeconds)): \(err)")
        exit(1)
    } else {
        print("done in \(String(format: "%.2fs", result.durationSeconds))")
    }
    // Re-compute so the user can see the delta.
    print("—")
    let after = db.computeStats()
    print("after:")
    print("  main : \(DatabaseStats.humanBytes(after.mainFileBytes))  (was \(DatabaseStats.humanBytes(stats.mainFileBytes)))")
    print("  wal  : \(DatabaseStats.humanBytes(after.walFileBytes))  (was \(DatabaseStats.humanBytes(stats.walFileBytes)))")
}

db.close()
exit(0)
