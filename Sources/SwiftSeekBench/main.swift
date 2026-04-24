// F1 perf probe. Stands up an in-memory-ish fixture DB with ~10k files,
// runs warm 2-char and 3+-char queries through SearchEngine, and prints
// median / p95 timings. Output is human-readable and stable enough for a
// smoke test to parse if it wants to.
//
// Usage:
//   swift run SwiftSeekBench               # default: 10_000 files, 50 warm iters
//   swift run SwiftSeekBench --files 20000 --iters 100
//
// Intentionally not a ship binary (driven manually / from CI). Output goes
// to stdout; exit code is 0 on success, 2 on arg parse failure, 1 if any
// timing exceeds the documented F1 target band.

import Foundation
import SwiftSeekCore

// stderr is unbuffered by default; stdout is line-buffered when connected
// to a terminal but fully buffered when redirected. Force line buffering on
// stdout so benchmark lines stream rather than accumulate.
setlinebuf(stdout)

struct BenchArgs {
    var fileCount: Int = 10_000
    var iterations: Int = 50
    var enforceTargets: Bool = false  // opt-in: fail on timing regression
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
        case "-h", "--help":
            print("""
            SwiftSeekBench — F1 perf probe
            usage:
              swift run SwiftSeekBench [--files N] [--iters N] [--enforce-targets]
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

// Build a fixture DB on a scratch path. Deleted at exit.
let scratchDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("swiftseek-bench-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: scratchDir,
                                         withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratchDir) }

// Populate a synthetic file tree: deterministic names, some overlap so
// 2-char queries return realistic candidate counts.
let words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta",
             "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi",
             "rho", "sigma", "tau", "phi", "chi", "psi", "omega",
             "docs", "notes", "ideas", "todo", "readme", "config", "test",
             "source", "build", "output", "sample", "example", "tmp"]
let exts = ["txt", "md", "swift", "h", "c", "json", "yaml", "log"]

let dbURL = scratchDir.appendingPathComponent("bench.sqlite3")
let db = try Database.open(at: dbURL)
try db.migrate()

// Register a single root so the engine's root filter lets everything through.
_ = try db.registerRoot(path: scratchDir.path)

print("[bench] building \(args.fileCount) synthetic files in \(scratchDir.path)")
let buildStart = Date()
var rows: [FileRow] = []
rows.reserveCapacity(args.fileCount)
for i in 0..<args.fileCount {
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
try db.insertFiles(rows)
let buildElapsed = Date().timeIntervalSince(buildStart)
print(String(format: "[bench] built + indexed in %.2fs", buildElapsed))

// Warm the hot path and the caches.
let engine = SearchEngine(database: db)

func warmUp() {
    for q in ["al", "be", "alp", "beta"] {
        _ = try? engine.search(q)
    }
}

func timedSearch(_ q: String, iterations: Int) -> (median: Double, p95: Double) {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let t0 = Date()
        _ = try? engine.search(q)
        samples.append(Date().timeIntervalSince(t0) * 1000) // ms
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
    return (median, p95)
}

print("[bench] warming up…")
warmUp()
// Second warm to let the prepared-statement cache populate.
warmUp()

struct Sample {
    let label: String
    let query: String
    let median: Double
    let p95: Double
    /// Documented target ceilings for the hot path. See
    /// docs/everything_performance_taskbook.md §F1 "验收标准".
    let medianTargetMs: Double
    let p95TargetMs: Double
}

var failed = 0
var samples: [Sample] = []

// 2-char cases
for q in ["al", "be", "do"] {
    let (med, p95) = timedSearch(q, iterations: args.iterations)
    samples.append(Sample(label: "warm 2-char", query: q,
                          median: med, p95: p95,
                          medianTargetMs: 50, p95TargetMs: 150))
}
// 3+ char cases (trigram path)
for q in ["alpha", "beta", "docs", "alpha beta"] {
    let (med, p95) = timedSearch(q, iterations: args.iterations)
    samples.append(Sample(label: "warm 3+char", query: q,
                          median: med, p95: p95,
                          medianTargetMs: 30, p95TargetMs: 100))
}

print("[bench] results (\(args.iterations) iters/query, \(args.fileCount) files):")
func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return s + String(repeating: " ", count: width - s.count)
}
print("\(pad("label", 14)) \(pad("query", 14)) \(pad("med-ms", 10)) \(pad("p95-ms", 10))  target")
for s in samples {
    let medStr = String(format: "%.2f", s.median)
    let p95Str = String(format: "%.2f", s.p95)
    let ok = s.median <= s.medianTargetMs && s.p95 <= s.p95TargetMs
    let mark = ok ? "ok" : "SLOW"
    let target = "med<=\(Int(s.medianTargetMs)) p95<=\(Int(s.p95TargetMs))"
    print("\(pad(s.label, 14)) \(pad(s.query, 14)) \(pad(medStr, 10)) \(pad(p95Str, 10))  \(target)  [\(mark)]")
    if !ok { failed += 1 }
}

// Cache observability.
print("[bench] SearchEngine stmt cache: hits=\(engine.stmtCacheHits) misses=\(engine.stmtCacheMisses)")
print("[bench] Database roots cache: hits=\(db.rootsCacheHits) misses=\(db.rootsCacheMisses)")

if args.enforceTargets && failed > 0 {
    FileHandle.standardError.write(Data("[bench] \(failed) sample(s) missed target\n".utf8))
    exit(1)
}
exit(0)
