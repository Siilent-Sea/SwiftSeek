// F1 + G5 perf probe.
//
// F1 usage (search hot path):
//   swift run SwiftSeekBench                         # 10k files, 50 iters, current default mode
//   swift run SwiftSeekBench --files 20000 --iters 100
//
// G5 usage (compact vs fullpath footprint + timing comparison):
//   swift run SwiftSeekBench --mode both --files 50000    # build both, compare
//   swift run SwiftSeekBench --mode compact --files 500000
//
// Output is human-readable; exit 0 on success, 2 on bad args, 1 if a
// warm-search sample exceeds the documented F1 target and
// --enforce-targets was passed.

import Foundation
import SwiftSeekCore
// H5 usage benchmark needs raw sqlite3 to grab file_ids in a single
// prepared pass (there's no list-all helper on Database and we don't
// want to ship one just for bench scaffolding).
import CSQLite

setlinebuf(stdout)

enum BenchMode: String { case compact, fullpath, both }

struct BenchArgs {
    var fileCount: Int = 10_000
    var iterations: Int = 50
    var enforceTargets: Bool = false
    var mode: BenchMode = .compact
    /// H5: number of `file_usage` rows to pre-populate before
    /// measuring. 0 = skip the usage benchmark entirely (backward
    /// compatible with G5 mode). Non-zero enables:
    ///   * `recent:` / `frequent:` query latency
    ///   * recordOpen write latency
    ///   * usage-populated normal-search JOIN cost
    var usageRows: Int = 0
    /// H5: number of recordOpen ops to sample for the write-path
    /// latency. Default tied to iterations so small --iters runs
    /// don't spend forever. Only used when --usage-rows > 0.
    var recordOpenOps: Int = 500
}

func parseArgs(_ argv: [String]) -> BenchArgs {
    var args = BenchArgs()
    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--files":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { exit(2) }
            args.fileCount = n
        case "--iters":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { exit(2) }
            args.iterations = n
        case "--enforce-targets":
            args.enforceTargets = true
        case "--mode":
            i += 1
            guard i < argv.count, let m = BenchMode(rawValue: argv[i]) else { exit(2) }
            args.mode = m
        case "--usage-rows":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n >= 0 else { exit(2) }
            args.usageRows = n
        case "--record-open-ops":
            i += 1
            guard i < argv.count, let n = Int(argv[i]), n > 0 else { exit(2) }
            args.recordOpenOps = n
        case "-h", "--help":
            print("""
            SwiftSeekBench — F1 perf probe + G5 footprint + H5 usage benchmark
            usage:
              swift run SwiftSeekBench [--files N] [--iters N] [--enforce-targets]
                                       [--mode compact|fullpath|both]
                                       [--usage-rows N] [--record-open-ops N]

              --mode compact    (default) index in compact mode, measure
              --mode fullpath   index in fullpath mode, measure
              --mode both       index once in each mode, print comparison
              --usage-rows N    H5: pre-populate N rows in file_usage and
                                measure recent: / frequent: / recordOpen
                                (0 = skip, backwards compatible with G5)
              --record-open-ops N  H5: number of recordOpen ops sampled
                                   for write-path latency (default 500).
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown arg: \(a)\n".utf8))
            exit(2)
        }
        i += 1
    }
    return args
}

let args = parseArgs(CommandLine.arguments)

let words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta",
             "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi",
             "rho", "sigma", "tau", "phi", "chi", "psi", "omega",
             "docs", "notes", "ideas", "todo", "readme", "config", "test",
             "source", "build", "output", "sample", "example", "tmp"]
let exts = ["txt", "md", "swift", "h", "c", "json", "yaml", "log"]

struct BenchResult {
    let mode: BenchMode
    let fileCount: Int
    let mainBytes: Int64
    let walBytes: Int64
    let fileGramsRows: Int64
    let fileBigramsRows: Int64
    let fileNameGramsRows: Int64
    let fileNameBigramsRows: Int64
    let filePathSegsRows: Int64
    let indexingTimeSec: Double
    /// G5 round 2: measure re-open cost. This is the closest proxy to
    /// "startup time" the user observes when launching SwiftSeek
    /// against a populated DB (open + migrate).
    let reopenTimeSec: Double
    /// G5 round 2: migrate() cost when opening the DB (no-op on fresh
    /// or already-current DB; non-zero on a v4→v5 upgrade).
    let migrateTimeSec: Double
    let twoCharMedianMs: Double
    let twoCharP95Ms: Double
    let threePlusCharMedianMs: Double
    let threePlusCharP95Ms: Double
    /// H5 usage benchmark results. All -1 / 0 when `--usage-rows == 0`
    /// (the G5-compatible path; bench result still valid but usage
    /// fields are not populated).
    let usageRowCount: Int64
    let normalSearchWithUsageMedianMs: Double  // same queries as 3+ char
    let normalSearchWithUsageP95Ms: Double
    let recentMedianMs: Double
    let recentP95Ms: Double
    let frequentMedianMs: Double
    let frequentP95Ms: Double
    let recordOpenMedianMs: Double
    let recordOpenP95Ms: Double
}

func buildFixture(mode: IndexMode, fileCount: Int) throws -> (Database, URL, Double) {
    let scratchDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftseek-bench-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratchDir,
                                            withIntermediateDirectories: true)
    let dbURL = scratchDir.appendingPathComponent("bench.sqlite3")
    let db = try Database.open(at: dbURL)
    try db.migrate()
    try db.setIndexMode(mode)
    _ = try db.registerRoot(path: scratchDir.path)

    var rows: [FileRow] = []
    rows.reserveCapacity(fileCount)
    for i in 0..<fileCount {
        let w1 = words[i % words.count]
        let w2 = words[(i / words.count) % words.count]
        let ext = exts[i % exts.count]
        let name = "\(w1)-\(w2)-\(i).\(ext)"
        let parent = "\(scratchDir.path)/\(w1)/\(w2)"
        let path = "\(parent)/\(name)"
        rows.append(FileRow(
            path: path,
            pathLower: path.lowercased(),
            name: name,
            nameLower: name.lowercased(),
            isDir: false,
            size: Int64(100 + i),
            mtime: Int64(1_700_000_000 + i)
        ))
    }
    let start = Date()
    try db.insertFiles(rows)
    let indexElapsed = Date().timeIntervalSince(start)
    // Checkpoint so the main DB file shows actual footprint instead of
    // WAL-holds-everything. This doubles as the CLI maintenance path.
    _ = db.runMaintenance(.checkpoint)
    return (db, scratchDir, indexElapsed)
}

func warmUp(_ engine: SearchEngine) {
    for q in ["al", "be", "alp", "beta"] {
        _ = try? engine.search(q)
    }
}

func timedSearch(_ q: String, iterations: Int, engine: SearchEngine) -> (median: Double, p95: Double) {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let t0 = Date()
        _ = try? engine.search(q)
        samples.append(Date().timeIntervalSince(t0) * 1000)
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
    return (median, p95)
}

func runOneMode(mode: IndexMode,
                fileCount: Int,
                iters: Int,
                usageRows: Int,
                recordOpenOps: Int) throws -> BenchResult {
    print("[bench] building \(fileCount) files in \(mode.rawValue) mode…")
    let (db, scratchDir, idxTime) = try buildFixture(mode: mode, fileCount: fileCount)
    print(String(format: "[bench] indexed in %.2fs", idxTime))

    // G5 round 2: close + reopen + migrate to measure the
    // startup-against-populated-DB cost. Migrate is a no-op here (we
    // already stamped v5 during build), but open still has to parse
    // headers / checkpoint / warm the B-tree; that's what the user
    // experiences on SwiftSeek launch.
    let dbURL = db.url
    db.close()
    let t0 = Date()
    let reopened = try Database.open(at: dbURL)
    let reopenT = Date().timeIntervalSince(t0)
    let mT0 = Date()
    try reopened.migrate()
    let migrateT = Date().timeIntervalSince(mT0)
    print(String(format: "[bench] reopen=%.3fs  migrate=%.3fs", reopenT, migrateT))

    defer { try? FileManager.default.removeItem(at: scratchDir); reopened.close() }

    let engine = SearchEngine(database: reopened)
    warmUp(engine); warmUp(engine)

    // 2-char queries
    var two2: [(Double, Double)] = []
    for q in ["al", "be", "do"] {
        two2.append(timedSearch(q, iterations: iters, engine: engine))
    }
    let twoMed = two2.map(\.0).reduce(0, +) / Double(two2.count)
    let twoP95 = two2.map(\.1).reduce(0, +) / Double(two2.count)

    // 3+ char queries
    var three3: [(Double, Double)] = []
    for q in ["alpha", "beta", "docs"] {
        three3.append(timedSearch(q, iterations: iters, engine: engine))
    }
    let threeMed = three3.map(\.0).reduce(0, +) / Double(three3.count)
    let threeP95 = three3.map(\.1).reduce(0, +) / Double(three3.count)

    // --- H5 usage benchmark -----------------------------------------
    var usageCount: Int64 = 0
    var normalWithUsageMed: Double = -1
    var normalWithUsageP95: Double = -1
    var recentMed: Double = -1
    var recentP95: Double = -1
    var frequentMed: Double = -1
    var frequentP95: Double = -1
    var recordOpenMed: Double = -1
    var recordOpenP95: Double = -1

    if usageRows > 0 {
        print("[bench] pre-populating \(usageRows) file_usage rows…")
        // Grab `usageRows` real file_ids from the files table so foreign
        // keys are happy (file_usage.file_id REFERENCES files(id)).
        // Using the first N ids gives a deterministic subset.
        var ids: [Int64] = []
        ids.reserveCapacity(usageRows)
        do {
            var stmt: OpaquePointer?
            let sql = "SELECT id FROM files ORDER BY id LIMIT ?;"
            guard let h = reopened.rawHandle else { throw NSError(domain: "bench", code: -1) }
            _ = sqlite3_prepare_v2(h, sql, -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            _ = sqlite3_bind_int64(stmt, 1, Int64(usageRows))
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(sqlite3_column_int64(stmt, 0))
            }
        }
        // Batch insert — single transaction so the 100k pre-populate
        // doesn't cost one fsync per row.
        let preT0 = Date()
        try reopened.exec("BEGIN IMMEDIATE;")
        do {
            // Stagger open_count / last_opened_at across ids so
            // recent: and frequent: have meaningfully different orders.
            var idx: Int64 = 0
            for fid in ids {
                // open_count: 1..20 cyclically
                let oc = (idx % 20) + 1
                // last_opened_at: monotonically increasing, packed into
                // a 3-day window so real timestamps are realistic.
                let ts = 1_700_000_000 + idx
                try reopened.exec("""
                INSERT INTO file_usage(file_id, open_count, last_opened_at, updated_at)
                VALUES (\(fid), \(oc), \(ts), \(ts));
                """)
                idx += 1
            }
            try reopened.exec("COMMIT;")
        } catch {
            try? reopened.exec("ROLLBACK;")
            throw error
        }
        print(String(format: "[bench] file_usage pre-populate took %.2fs", Date().timeIntervalSince(preT0)))
        usageCount = (try? reopened.countRows(in: "file_usage")) ?? -1

        // (1) Normal search under populated usage — remeasure 3+char to
        // see if the LEFT JOIN + tie-break costs anything significant.
        warmUp(engine); warmUp(engine)
        var nwu: [(Double, Double)] = []
        for q in ["alpha", "beta", "docs"] {
            nwu.append(timedSearch(q, iterations: iters, engine: engine))
        }
        normalWithUsageMed = nwu.map(\.0).reduce(0, +) / Double(nwu.count)
        normalWithUsageP95 = nwu.map(\.1).reduce(0, +) / Double(nwu.count)

        // (2) recent: — pure usage-mode query; SQL hits file_usage JOIN files.
        let recentSample = timedSearch("recent:", iterations: iters, engine: engine)
        recentMed = recentSample.median
        recentP95 = recentSample.p95

        // (3) frequent:
        let frequentSample = timedSearch("frequent:", iterations: iters, engine: engine)
        frequentMed = frequentSample.median
        frequentP95 = frequentSample.p95

        // (4) recordOpen write latency. Keep it honest: we sample
        // against existing file_ids (they already have a usage row so
        // each op is an UPSERT increment, which is the realistic hot
        // path after the first open). Rotate through the id list so
        // SQLite cache behavior is representative.
        var roSamples: [Double] = []
        roSamples.reserveCapacity(recordOpenOps)
        let idsCount = ids.count
        for i in 0..<recordOpenOps {
            let fid = ids[i % idsCount]
            let t0 = Date()
            _ = try reopened.recordOpen(fileId: fid, now: 1_700_100_000 + Int64(i))
            roSamples.append(Date().timeIntervalSince(t0) * 1000)
        }
        roSamples.sort()
        recordOpenMed = roSamples[roSamples.count / 2]
        recordOpenP95 = roSamples[min(roSamples.count - 1, Int(Double(roSamples.count) * 0.95))]
    }

    let s = reopened.computeStats()
    let benchMode: BenchMode = (mode == .compact) ? .compact : .fullpath
    return BenchResult(
        mode: benchMode,
        fileCount: fileCount,
        mainBytes: s.mainFileBytes,
        walBytes: s.walFileBytes,
        fileGramsRows: s.fileGramsRowCount,
        fileBigramsRows: s.fileBigramsRowCount,
        fileNameGramsRows: (try? reopened.countRows(in: "file_name_grams")) ?? -1,
        fileNameBigramsRows: (try? reopened.countRows(in: "file_name_bigrams")) ?? -1,
        filePathSegsRows: (try? reopened.countRows(in: "file_path_segments")) ?? -1,
        indexingTimeSec: idxTime,
        reopenTimeSec: reopenT,
        migrateTimeSec: migrateT,
        twoCharMedianMs: twoMed,
        twoCharP95Ms: twoP95,
        threePlusCharMedianMs: threeMed,
        threePlusCharP95Ms: threeP95,
        usageRowCount: usageCount,
        normalSearchWithUsageMedianMs: normalWithUsageMed,
        normalSearchWithUsageP95Ms: normalWithUsageP95,
        recentMedianMs: recentMed,
        recentP95Ms: recentP95,
        frequentMedianMs: frequentMed,
        frequentP95Ms: frequentP95,
        recordOpenMedianMs: recordOpenMed,
        recordOpenP95Ms: recordOpenP95
    )
}

func pad(_ s: String, _ w: Int) -> String {
    if s.count >= w { return s }
    return s + String(repeating: " ", count: w - s.count)
}

func printRow(_ r: BenchResult) {
    let mainStr = DatabaseStats.humanBytes(r.mainBytes)
    let walStr = DatabaseStats.humanBytes(r.walBytes)
    let idx = String(format: "%.2fs", r.indexingTimeSec)
    let re = String(format: "%.3fs", r.reopenTimeSec)
    let mg = String(format: "%.3fs", r.migrateTimeSec)
    let tm = String(format: "%.2fms", r.twoCharMedianMs)
    let tp = String(format: "%.2fms", r.twoCharP95Ms)
    let em = String(format: "%.2fms", r.threePlusCharMedianMs)
    let ep = String(format: "%.2fms", r.threePlusCharP95Ms)
    print("  mode=\(pad(r.mode.rawValue, 9)) main=\(pad(mainStr, 12)) wal=\(pad(walStr, 9)) index=\(pad(idx, 8)) reopen=\(pad(re, 8)) migrate=\(pad(mg, 8))")
    print("    2-char-med=\(pad(tm, 9)) 2-char-p95=\(pad(tp, 9)) 3+char-med=\(pad(em, 9)) 3+char-p95=\(pad(ep, 9))")
    print("    grams=\(pad(DatabaseStats.humanCount(r.fileGramsRows), 10)) bigrams=\(pad(DatabaseStats.humanCount(r.fileBigramsRows), 10)) name_grams=\(pad(DatabaseStats.humanCount(r.fileNameGramsRows), 10)) name_bigrams=\(pad(DatabaseStats.humanCount(r.fileNameBigramsRows), 10)) path_segs=\(DatabaseStats.humanCount(r.filePathSegsRows))")
    if r.usageRowCount > 0 {
        let usage = DatabaseStats.humanCount(r.usageRowCount)
        let nm = String(format: "%.2fms", r.normalSearchWithUsageMedianMs)
        let np = String(format: "%.2fms", r.normalSearchWithUsageP95Ms)
        let rm = String(format: "%.2fms", r.recentMedianMs)
        let rp = String(format: "%.2fms", r.recentP95Ms)
        let fm = String(format: "%.2fms", r.frequentMedianMs)
        let fp = String(format: "%.2fms", r.frequentP95Ms)
        let om = String(format: "%.3fms", r.recordOpenMedianMs)
        let op = String(format: "%.3fms", r.recordOpenP95Ms)
        print("    H5 usage_rows=\(pad(usage, 10)) 3+char(w/usage)-med=\(pad(nm, 9)) p95=\(pad(np, 9))")
        print("       recent:-med=\(pad(rm, 9)) p95=\(pad(rp, 9)) frequent:-med=\(pad(fm, 9)) p95=\(pad(fp, 9))")
        print("       recordOpen-med=\(pad(om, 9)) p95=\(pad(op, 9))")
    }
}

// --- Run ---------------------------------------------------------------
print("[bench] files=\(args.fileCount)  iters/query=\(args.iterations)  mode=\(args.mode.rawValue)")

var results: [BenchResult] = []
switch args.mode {
case .compact:
    results.append(try runOneMode(mode: .compact,
                                  fileCount: args.fileCount,
                                  iters: args.iterations,
                                  usageRows: args.usageRows,
                                  recordOpenOps: args.recordOpenOps))
case .fullpath:
    results.append(try runOneMode(mode: .fullpath,
                                  fileCount: args.fileCount,
                                  iters: args.iterations,
                                  usageRows: args.usageRows,
                                  recordOpenOps: args.recordOpenOps))
case .both:
    results.append(try runOneMode(mode: .compact,
                                  fileCount: args.fileCount,
                                  iters: args.iterations,
                                  usageRows: args.usageRows,
                                  recordOpenOps: args.recordOpenOps))
    results.append(try runOneMode(mode: .fullpath,
                                  fileCount: args.fileCount,
                                  iters: args.iterations,
                                  usageRows: args.usageRows,
                                  recordOpenOps: args.recordOpenOps))
}

print("—")
print("[bench] results:")
for r in results { printRow(r) }

// Comparison block for --mode both
if results.count == 2 {
    let compact = results.first { $0.mode == .compact }!
    let fullpath = results.first { $0.mode == .fullpath }!
    print("—")
    print("[bench] compact vs fullpath delta (compact / fullpath):")
    print(String(format: "  main    %@ / %@  =  %.2fx",
                 DatabaseStats.humanBytes(compact.mainBytes),
                 DatabaseStats.humanBytes(fullpath.mainBytes),
                 Double(compact.mainBytes) / max(Double(fullpath.mainBytes), 1)))
    print(String(format: "  grams+bigrams vs name+name_bigrams+segs:"))
    let fullpathGram = fullpath.fileGramsRows + fullpath.fileBigramsRows
    let compactGram = compact.fileNameGramsRows + compact.fileNameBigramsRows + compact.filePathSegsRows
    print(String(format: "    fullpath: grams+bigrams = %@",
                 DatabaseStats.humanCount(fullpathGram)))
    print(String(format: "    compact:  name_grams+name_bigrams+path_segs = %@  (%.2fx)",
                 DatabaseStats.humanCount(compactGram),
                 Double(compactGram) / max(Double(fullpathGram), 1)))
    print(String(format: "  index time: compact=%.2fs  fullpath=%.2fs  (%.2fx)",
                 compact.indexingTimeSec, fullpath.indexingTimeSec,
                 compact.indexingTimeSec / max(fullpath.indexingTimeSec, 0.001)))
    print(String(format: "  2-char median: compact=%.2fms  fullpath=%.2fms",
                 compact.twoCharMedianMs, fullpath.twoCharMedianMs))
    print(String(format: "  3+char median: compact=%.2fms  fullpath=%.2fms",
                 compact.threePlusCharMedianMs, fullpath.threePlusCharMedianMs))
}

// --- Target enforcement (F1 contract still holds for both modes) ---
if args.enforceTargets {
    var bad = 0
    for r in results {
        if r.twoCharMedianMs > 50  { bad += 1; print("[bench] SLOW: \(r.mode.rawValue) 2-char median \(r.twoCharMedianMs) > 50ms") }
        if r.twoCharP95Ms    > 150 { bad += 1; print("[bench] SLOW: \(r.mode.rawValue) 2-char p95 \(r.twoCharP95Ms) > 150ms") }
        if r.threePlusCharMedianMs > 30 { bad += 1; print("[bench] SLOW: \(r.mode.rawValue) 3+char median \(r.threePlusCharMedianMs) > 30ms") }
        if r.threePlusCharP95Ms    > 100 { bad += 1; print("[bench] SLOW: \(r.mode.rawValue) 3+char p95 \(r.threePlusCharP95Ms) > 100ms") }
    }
    if bad > 0 {
        FileHandle.standardError.write(Data("[bench] \(bad) target miss(es)\n".utf8))
        exit(1)
    }
}
exit(0)
