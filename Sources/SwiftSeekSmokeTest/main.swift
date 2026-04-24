import Foundation
import SwiftSeekCore
#if canImport(AppKit)
import AppKit
#endif

struct SmokeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class SmokeReporter {
    private(set) var passed = 0
    private(set) var failed = 0
    private var failures: [String] = []

    func check(_ name: String, _ block: () throws -> Void) {
        do {
            try block()
            passed += 1
            print("  PASS  \(name)")
        } catch {
            failed += 1
            failures.append("\(name): \(error)")
            print("  FAIL  \(name) -> \(error)")
        }
    }

    func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw SmokeFailure(message: message())
        }
    }

    func summary() -> Int32 {
        print("---")
        print("Smoke total: \(passed + failed)  pass: \(passed)  fail: \(failed)")
        return failed == 0 ? 0 : 1
    }
}

func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftSeekSmoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

let reporter = SmokeReporter()

print("SwiftSeek smoke test (P0 + P1 + P2 + P3 + P4 + P4-startup + P5 + E1 + E2 + E3 + E4 + E5 + F1 + F2 + F3 + F4 + G1 + G3 + G4 + H1 + H2 + H3 + H4 + J1 + J2 + J3 + J4 + J5 + J6)")
print("schema version: \(Schema.currentVersion)")
print("---")

reporter.check("AppPaths.ensureSupportDirectory creates nested dir") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let nested = root.appendingPathComponent("a/b/c")
    let paths = try AppPaths.ensureSupportDirectory(override: nested)
    var isDir: ObjCBool = false
    try reporter.require(
        FileManager.default.fileExists(atPath: paths.supportDirectory.path, isDirectory: &isDir),
        "support directory missing"
    )
    try reporter.require(isDir.boolValue, "support path not a directory")
    try reporter.require(paths.databaseURL.lastPathComponent == AppPaths.databaseFileName,
                         "database filename mismatch")
}

reporter.check("Database.open creates sqlite file") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let paths = try AppPaths.ensureSupportDirectory(override: root)
    try reporter.require(!FileManager.default.fileExists(atPath: paths.databaseURL.path),
                         "db should not exist yet")
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try reporter.require(FileManager.default.fileExists(atPath: paths.databaseURL.path),
                         "db file not created")
}

reporter.check("Database.migrate creates required tables") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let paths = try AppPaths.ensureSupportDirectory(override: root)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    for name in ["meta", "files", "roots", "excludes"] {
        try reporter.require(try db.tableExists(name), "missing table \(name)")
    }
}

reporter.check("Database.migrate sets user_version") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let paths = try AppPaths.ensureSupportDirectory(override: root)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "schemaVersion=\(db.schemaVersion) expected=\(Schema.currentVersion)")
    let v = try db.readUserVersion()
    try reporter.require(v == Schema.currentVersion,
                         "user_version=\(v) expected=\(Schema.currentVersion)")
}

reporter.check("Database.migrate is idempotent") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let paths = try AppPaths.ensureSupportDirectory(override: root)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.migrate()
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "idempotent migrate changed version")
}

reporter.check("Database persists schema across reopen") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let paths = try AppPaths.ensureSupportDirectory(override: root)
    do {
        let db = try Database.open(at: paths.databaseURL)
        try db.migrate()
        db.close()
    }
    let db2 = try Database.open(at: paths.databaseURL)
    defer { db2.close() }
    try db2.migrate()
    try reporter.require(db2.schemaVersion == Schema.currentVersion,
                         "reopened schema version wrong")
    try reporter.require(try db2.tableExists("files"),
                         "reopened db missing files table")
}

func makeSampleTree() throws -> (root: URL, expectedRows: Int) {
    let root = try makeTempDir()
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("sub1/sub2"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("empty-dir"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("中文目录"),
                           withIntermediateDirectories: true)
    try "a".write(to: root.appendingPathComponent("a.txt"),
                  atomically: true, encoding: .utf8)
    try "b".write(to: root.appendingPathComponent("sub1/b.txt"),
                  atomically: true, encoding: .utf8)
    try "c".write(to: root.appendingPathComponent("sub1/sub2/c.txt"),
                  atomically: true, encoding: .utf8)
    try "cn".write(to: root.appendingPathComponent("中文目录/文件.txt"),
                   atomically: true, encoding: .utf8)
    try "space".write(to: root.appendingPathComponent("with space.txt"),
                      atomically: true, encoding: .utf8)
    // 1 root + 3 subdirs + 5 files = 9, plus sub1 and sub1/sub2 counted once each
    // Counted: root, a.txt, empty-dir, sub1, sub1/b.txt, sub1/sub2, sub1/sub2/c.txt,
    //          with space.txt, 中文目录, 中文目录/文件.txt = 10
    return (root, 10)
}

reporter.check("Indexer.indexRoot inserts all entries under sample tree") {
    let dbRoot = try makeTempDir()
    defer { cleanup(dbRoot) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbRoot)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let (sample, expected) = try makeSampleTree()
    defer { cleanup(sample) }

    let indexer = Indexer(database: db)
    let stats = try indexer.indexRoot(sample, options: .init(batchSize: 100, progressEvery: 100))
    try reporter.require(!stats.cancelled, "unexpected cancellation")
    try reporter.require(stats.scanned == expected,
                         "scanned=\(stats.scanned) expected=\(expected)")
    try reporter.require(stats.inserted == expected,
                         "inserted=\(stats.inserted) expected=\(expected)")

    let filesCount = try db.countRows(in: "files")
    try reporter.require(filesCount == Int64(expected),
                         "files count=\(filesCount) expected=\(expected)")
    let rootsCount = try db.countRows(in: "roots")
    try reporter.require(rootsCount == 1, "roots count=\(rootsCount) expected=1")

    let canonical = Indexer.canonicalize(path: sample.path)
    try reporter.require(try db.fileExists(path: canonical),
                         "root row missing at \(canonical)")
    try reporter.require(try db.fileExists(path: canonical + "/中文目录/文件.txt"),
                         "CJK file row missing")
    try reporter.require(try db.fileExists(path: canonical + "/with space.txt"),
                         "spaced file row missing")
}

reporter.check("Indexer.indexRoot respects cancellation token") {
    let dbRoot = try makeTempDir()
    defer { cleanup(dbRoot) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbRoot)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let big = try makeTempDir()
    defer { cleanup(big) }
    for i in 0..<30 {
        let d = big.appendingPathComponent("dir\(i)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for j in 0..<20 {
            try "x".write(to: d.appendingPathComponent("f\(j).txt"),
                          atomically: true, encoding: .utf8)
        }
    }

    let token = CancellationToken()
    token.cancel()

    let indexer = Indexer(database: db)
    let stats = try indexer.indexRoot(big,
                                      options: .init(batchSize: 50, progressEvery: 50),
                                      cancel: token)
    try reporter.require(stats.cancelled, "expected cancelled=true")
    try reporter.require(stats.scanned < 30 * 20 + 30 + 1,
                         "cancelled run scanned full tree: \(stats.scanned)")
}

reporter.check("Pre-cancelled indexer flushes no rows (no ghost writes)") {
    let dbRoot = try makeTempDir()
    defer { cleanup(dbRoot) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbRoot)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let (sample, _) = try makeSampleTree()
    defer { cleanup(sample) }

    let token = CancellationToken()
    token.cancel()

    let indexer = Indexer(database: db)
    let stats = try indexer.indexRoot(sample,
                                      options: .init(batchSize: 100, progressEvery: 100),
                                      cancel: token)
    try reporter.require(stats.cancelled, "expected cancelled=true")
    try reporter.require(stats.inserted == 0,
                         "pre-cancel inserted non-zero: \(stats.inserted)")

    let filesCount = try db.countRows(in: "files")
    try reporter.require(filesCount == 0,
                         "pre-cancel wrote \(filesCount) rows to files table")
}

reporter.check("In-flight cancel never flushes pending partial batch") {
    let dbRoot = try makeTempDir()
    defer { cleanup(dbRoot) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbRoot)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let big = try makeTempDir()
    defer { cleanup(big) }
    for i in 0..<20 {
        let d = big.appendingPathComponent("dir\(i)", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        for j in 0..<60 {
            try "x".write(to: d.appendingPathComponent("f\(j).txt"),
                          atomically: true, encoding: .utf8)
        }
    }
    // Tree size ≈ 1 + 20 + 20*60 = 1221 rows

    let token = CancellationToken()
    let batchSize = 100
    let indexer = Indexer(database: db)

    var progressCalls = 0
    let stats = try indexer.indexRoot(
        big,
        options: .init(batchSize: batchSize, progressEvery: batchSize),
        cancel: token,
        progress: { _ in
            progressCalls += 1
            if progressCalls == 1 {
                // Fires after first batch flush (scanned == 100). Cancel synchronously.
                token.cancel()
            }
        })

    try reporter.require(stats.cancelled, "expected cancelled=true for in-flight cancel")
    try reporter.require(stats.inserted > 0, "no batches flushed before cancel")
    try reporter.require(stats.inserted < 1221,
                         "inserted=\(stats.inserted) equals full tree — cancel not observed")
    // inserted must be exact multiple of batchSize — any partial tail would violate this.
    try reporter.require(stats.inserted % batchSize == 0,
                         "inserted=\(stats.inserted) not a multiple of batchSize=\(batchSize); partial batch leaked past cancel")

    let filesCount = try db.countRows(in: "files")
    try reporter.require(Int64(stats.inserted) == filesCount,
                         "stats.inserted=\(stats.inserted) disagrees with files=\(filesCount)")
}

reporter.check("Indexer clears previous rows under same root on re-index") {
    let dbRoot = try makeTempDir()
    defer { cleanup(dbRoot) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbRoot)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let (sample, _) = try makeSampleTree()
    defer { cleanup(sample) }

    let indexer = Indexer(database: db)
    _ = try indexer.indexRoot(sample)
    let first = try db.countRows(in: "files")

    let extra = sample.appendingPathComponent("added-after.txt")
    try "new".write(to: extra, atomically: true, encoding: .utf8)

    _ = try indexer.indexRoot(sample)
    let second = try db.countRows(in: "files")

    try reporter.require(second == first + 1,
                         "re-index row count mismatch first=\(first) second=\(second)")
}

// MARK: - P2 search fixture

func withP2Fixture(_ body: (Database, String) throws -> Void) throws {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // P2 fixture originally asserts v4 full-path substring semantics
    // (plain queries can recall path-only hits like `/extras-with-alpha/README.md`).
    // G3 changed the new-DB default to compact. Keep these P2 regressions
    // meaningful by opting into fullpath mode explicitly before indexing.
    try db.setIndexMode(.fullpath)

    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    for d in ["docs", "beta", "extras-with-alpha"] {
        try fm.createDirectory(at: root.appendingPathComponent(d),
                               withIntermediateDirectories: true)
    }
    let files = [
        "alpha.txt",
        "alphabet.txt",
        "docs/alpha-notes.md",
        "beta/alpha report.txt",
        "extras-with-alpha/README.md",
        "中文文档.md"
    ]
    for f in files {
        try "".write(to: root.appendingPathComponent(f),
                     atomically: true, encoding: .utf8)
    }
    let indexer = Indexer(database: db)
    _ = try indexer.indexRoot(root)
    let canonical = Indexer.canonicalize(path: root.path)
    try body(db, canonical)
}

reporter.check("SearchEngine.normalize trims, lowercases, collapses whitespace") {
    try reporter.require(SearchEngine.normalize("  Hello   World  ") == "hello world",
                         "expected 'hello world'")
    try reporter.require(SearchEngine.normalize("") == "",
                         "empty input must yield empty")
    try reporter.require(SearchEngine.normalize("\tALPHA\n BETA ") == "alpha beta",
                         "tabs/newlines not normalized")
    try reporter.require(SearchEngine.normalize("中 文") == "中 文",
                         "non-ASCII collapse broken")
}

// NOTE: Post-E1 score bands are base tier (1000/800/500/200) + E1 bonuses
// (+50 basename, +30 token-boundary, +40 path-segment, +80 extension, +100
// multi-token all-in-basename). Tests below assert exact post-E1 scores.

reporter.check("P2 filename prefix match beats path-only hit") {
    try withP2Fixture { db, _ in
        let engine = SearchEngine(database: db)
        let results = try engine.search("alp")
        try reporter.require(!results.isEmpty, "no results for alp")
        let first = results.first!
        try reporter.require(first.path.hasSuffix("/alpha.txt"),
                             "first result not alpha.txt: \(first.path)")
        // alpha.txt: prefix(800) + basename(50) + boundary(30) = 880
        try reporter.require(first.score == 880, "first score=\(first.score) expected 880")
        let readme = results.first(where: { $0.path.hasSuffix("/extras-with-alpha/README.md") })
        try reporter.require(readme != nil,
                             "expected path-only extras-with-alpha/README.md in results")
        // extras-with-alpha/README.md: path-only(200) + boundary(30) = 230
        // ("alp" is preceded by "-" in "extras-with-alpha", a boundary char)
        try reporter.require(readme!.score == 230,
                             "extras-with-alpha/README.md score=\(readme!.score) expected 230")
        let readmeIdx = results.firstIndex(where: { $0.path == readme!.path })!
        for r in results.prefix(readmeIdx) {
            // Everything above path-only hit must still come from base >= 500
            try reporter.require(r.score >= 500,
                                 "score \(r.score) ordered before path-only hit")
        }
    }
}

reporter.check("P2 path-only query returns only matching descendant") {
    try withP2Fixture { db, _ in
        let engine = SearchEngine(database: db)
        let results = try engine.search("docs/alpha")
        try reporter.require(results.count == 1,
                             "expected 1 got \(results.count)")
        let r = results[0]
        try reporter.require(r.path.hasSuffix("/docs/alpha-notes.md"),
                             "wrong result: \(r.path)")
        // path-only(200) + boundary(30) = 230
        try reporter.require(r.score == 230,
                             "score=\(r.score) expected 230 (path-only + boundary)")
    }
}

reporter.check("P2 3-gram candidate retrieval finds 'pha'") {
    try withP2Fixture { db, _ in
        let engine = SearchEngine(database: db)
        let results = try engine.search("pha")
        let paths = results.map { $0.path }
        try reporter.require(paths.contains(where: { $0.hasSuffix("/alpha.txt") }),
                             "missing alpha.txt")
        try reporter.require(paths.contains(where: { $0.hasSuffix("/alphabet.txt") }),
                             "missing alphabet.txt")
        try reporter.require(paths.contains(where: { $0.hasSuffix("/docs/alpha-notes.md") }),
                             "missing docs/alpha-notes.md")
        try reporter.require(paths.contains(where: { $0.hasSuffix("/beta/alpha report.txt") }),
                             "missing 'beta/alpha report.txt'")
        try reporter.require(paths.contains(where: { $0.hasSuffix("/extras-with-alpha/README.md") }),
                             "missing path-only extras-with-alpha/README.md")
        for r in results {
            if r.path.hasSuffix("/extras-with-alpha/README.md") {
                // extras-with-alpha/README.md: path-only(200) + boundary(30 —
                // "pha" ends alpha which is followed by "/") = 230
                try reporter.require(r.score == 230,
                                     "README score=\(r.score) expected 230")
            } else {
                // "pha" in name (e.g. "alpha.txt" / "alphabet.txt" / "alpha-notes.md"
                // / "alpha report.txt"): contains(500) + basename(50) +
                // boundary(30 — followed by "." / "-" / " ") = 580. Except
                // "alphabet.txt" which has "pha" sandwiched by "l" and "b" (no
                // boundary) → 550.
                let expected = r.path.hasSuffix("/alphabet.txt") ? 550 : 580
                try reporter.require(r.score == expected,
                                     "expected \(expected) for \(r.path), got \(r.score)")
            }
        }
    }
}

reporter.check("P2 ranking sorts shorter path first within same score") {
    try withP2Fixture { db, _ in
        let engine = SearchEngine(database: db)
        let results = try engine.search("alp")
        // After E1 all filename-prefix hits become prefix(800) + basename(50) +
        // boundary(30) = 880 (the "alp" is always at name start, which is
        // preceded by "/" in the path).
        let top = results.filter { $0.score == 880 }
        try reporter.require(top.count >= 4,
                             "expected >=4 top-tier hits, got \(top.count)")
        try reporter.require(top[0].path.hasSuffix("/alpha.txt"),
                             "first top not alpha.txt: \(top[0].path)")
        try reporter.require(top[1].path.hasSuffix("/alphabet.txt"),
                             "second top not alphabet.txt: \(top[1].path)")
        var prev = Int.max
        for r in results {
            try reporter.require(r.score <= prev,
                                 "score rose from \(prev) to \(r.score) at \(r.path)")
            prev = r.score
        }
    }
}

reporter.check("P2 CJK filename query returns correct file") {
    try withP2Fixture { db, _ in
        let engine = SearchEngine(database: db)
        let results = try engine.search("中文")
        try reporter.require(results.count == 1,
                             "expected 1 got \(results.count)")
        let r = results[0]
        try reporter.require(r.path.hasSuffix("/中文文档.md"),
                             "wrong CJK result: \(r.path)")
        // prefix(800) + basename(50) + boundary(30 — start of name) = 880
        try reporter.require(r.score == 880,
                             "CJK score=\(r.score) expected 880")
    }
}

reporter.check("P2 query with space in filename works via gram path") {
    try withP2Fixture { db, _ in
        let engine = SearchEngine(database: db)
        let results = try engine.search("alpha report")
        try reporter.require(results.count == 1,
                             "expected 1 got \(results.count)")
        let r = results[0]
        try reporter.require(r.path.hasSuffix("/beta/alpha report.txt"),
                             "wrong space result: \(r.path)")
        // Multi-token AND: alpha token → prefix(800)+basename(50)+boundary(30)=880;
        // report token → contains(500)+basename(50)+boundary(30)=580; both in
        // basename → multi-token all-in-basename bonus(100). Total 880+580+100=1560
        try reporter.require(r.score == 1560,
                             "multi-token score=\(r.score) expected 1560")
    }
}

reporter.check("P2 v1→v2 migration backfills path_lower and grams so old rows are searchable") {
    let root = try makeTempDir()
    defer { cleanup(root) }
    let dbURL = root.appendingPathComponent("legacy.sqlite3")

    // Hand-build a P1-shaped database (user_version=1, no path_lower, no file_grams).
    let v1SQL = """
    PRAGMA user_version=1;
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        path TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        name_lower TEXT NOT NULL,
        is_dir INTEGER NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        mtime INTEGER NOT NULL DEFAULT 0,
        inode INTEGER,
        volume_id INTEGER
    );
    CREATE INDEX idx_files_name_lower ON files(name_lower);
    CREATE INDEX idx_files_parent ON files(parent_id);
    CREATE TABLE roots (id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE, enabled INTEGER NOT NULL DEFAULT 1);
    CREATE TABLE excludes (id INTEGER PRIMARY KEY AUTOINCREMENT, pattern TEXT NOT NULL UNIQUE);
    INSERT INTO files(path, name, name_lower, is_dir) VALUES ('/legacy/Zeta.TXT', 'Zeta.TXT', 'zeta.txt', 0);
    INSERT INTO files(path, name, name_lower, is_dir) VALUES ('/legacy/OTHER.md', 'OTHER.md', 'other.md', 0);
    """
    do {
        let raw = try Database.open(at: dbURL)
        try raw.exec(v1SQL)
        raw.close()
    }

    // Re-open through the regular API and run migrate().
    let db = try Database.open(at: dbURL)
    defer { db.close() }
    try reporter.require(try db.readUserVersion() == 1,
                         "pre-migrate user_version not 1")
    try db.migrate()
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "post-migrate schemaVersion=\(db.schemaVersion)")
    try reporter.require(try db.tableExists("file_grams"),
                         "file_grams table not created")

    let gramCount = try db.scalarInt("SELECT COUNT(*) FROM file_grams;") ?? 0
    try reporter.require(gramCount > 0, "grams not backfilled (count=\(gramCount))")

    let engine = SearchEngine(database: db)
    let zeta = try engine.search("zeta")
    try reporter.require(zeta.count == 1 && zeta[0].path == "/legacy/Zeta.TXT",
                         "legacy row not searchable via grams: \(zeta)")
    // zeta on zeta.txt: prefix(800)+basename(50)+boundary(30 — start of name) = 880
    try reporter.require(zeta[0].score == 880,
                         "legacy score=\(zeta[0].score) expected 880")
}

// MARK: - P3 incremental update

func withP3Fixture(_ body: (Database, Indexer, String) throws -> Void) throws {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("sub"),
                           withIntermediateDirectories: true)
    try "i1".write(to: root.appendingPathComponent("initial.txt"),
                   atomically: true, encoding: .utf8)
    try "s1".write(to: root.appendingPathComponent("sub/inner.txt"),
                   atomically: true, encoding: .utf8)

    let indexer = Indexer(database: db)
    _ = try indexer.indexRoot(root)
    let canonical = Indexer.canonicalize(path: root.path)
    try body(db, indexer, canonical)
}

reporter.check("P3 EventQueue debounces multiple enqueues into one batch") {
    let sem = DispatchSemaphore(value: 0)
    let state = NSLock()
    var received: Set<String> = []
    var batches = 0
    let q = EventQueue(options: .init(debounce: 0.1, label: "smoke.q1")) { batch in
        state.lock()
        received = batch
        batches += 1
        state.unlock()
        sem.signal()
    }
    q.enqueue("/tmp/a")
    q.enqueue("/tmp/b")
    q.enqueue("/tmp/a")
    q.enqueue(["/tmp/c", "/tmp/b"])
    let waitRC = sem.wait(timeout: .now() + .seconds(2))
    try reporter.require(waitRC == .success, "no batch emitted before timeout")
    // Give any extra spurious batches a small window to fire, then lock + check.
    Thread.sleep(forTimeInterval: 0.15)
    state.lock()
    let finalBatches = batches
    let finalReceived = received
    state.unlock()
    try reporter.require(finalBatches == 1,
                         "expected exactly 1 batch, got \(finalBatches)")
    try reporter.require(finalReceived == ["/tmp/a", "/tmp/b", "/tmp/c"],
                         "batch content mismatch: \(finalReceived)")
    q.stop()
}

reporter.check("P3 Indexer.coalescePrefixes drops descendants of dir inputs") {
    let input: Set<String> = [
        "/root",
        "/root/a.txt",
        "/root/sub",
        "/root/sub/b.txt",
        "/other",
        "/other2/deep/nested"
    ]
    let kept = Indexer.coalescePrefixes(input)
    // Expected: "/root" swallows /root/*, "/other", "/other2/deep/nested" stand alone.
    try reporter.require(kept == ["/other", "/other2/deep/nested", "/root"],
                         "coalesce wrong: \(kept)")
    // Siblings with a shared unrelated prefix must not be coalesced.
    let siblings: Set<String> = ["/a/foo", "/a/foobar"]
    let kept2 = Indexer.coalescePrefixes(siblings)
    try reporter.require(kept2 == ["/a/foo", "/a/foobar"],
                         "foobar should not be dropped by foo: \(kept2)")
}

reporter.check("P3 rescanPaths adds newly created file so search finds it") {
    try withP3Fixture { db, indexer, root in
        let newURL = URL(fileURLWithPath: root + "/new-alpha.txt")
        try "x".write(to: newURL, atomically: true, encoding: .utf8)
        let stats = try indexer.rescanPaths([newURL.path])
        try reporter.require(stats.upserted >= 1,
                             "no upsert: \(stats)")
        let engine = SearchEngine(database: db)
        let hits = try engine.search("new-alpha")
        try reporter.require(hits.contains(where: { $0.path == newURL.path }),
                             "new file missing from search: \(hits.map(\.path))")
    }
}

reporter.check("P3 rescanPaths removes deleted file row") {
    try withP3Fixture { db, indexer, root in
        let victim = root + "/initial.txt"
        try reporter.require(try db.fileExists(path: victim),
                             "precondition: initial.txt should be indexed")
        try FileManager.default.removeItem(atPath: victim)
        let stats = try indexer.rescanPaths([victim])
        try reporter.require(stats.deleted == 1,
                             "deleted count=\(stats.deleted) expected 1")
        try reporter.require(!(try db.fileExists(path: victim)),
                             "deleted path still in DB")
        let engine = SearchEngine(database: db)
        let hits = try engine.search("initial")
        try reporter.require(!hits.contains(where: { $0.path == victim }),
                             "deleted path still searchable")
    }
}

reporter.check("P3 rescanPaths handles rename: old path gone, new path present") {
    try withP3Fixture { db, indexer, root in
        let fm = FileManager.default
        let oldPath = root + "/initial.txt"
        let newPath = root + "/renamed-beta.txt"
        try fm.moveItem(atPath: oldPath, toPath: newPath)
        // Real FSEvents would deliver both paths; simulate that here.
        _ = try indexer.rescanPaths([oldPath, newPath])

        try reporter.require(!(try db.fileExists(path: oldPath)),
                             "old path still present after rename")
        try reporter.require(try db.fileExists(path: newPath),
                             "new path missing after rename")
        let engine = SearchEngine(database: db)
        let renamedHits = try engine.search("renamed-beta")
        try reporter.require(renamedHits.contains(where: { $0.path == newPath }),
                             "renamed file not searchable: \(renamedHits.map(\.path))")
    }
}

reporter.check("P3 rescanPaths on deleted directory prunes all descendants") {
    try withP3Fixture { db, indexer, root in
        let subDir = root + "/sub"
        try reporter.require(try db.fileExists(path: subDir + "/inner.txt"),
                             "precondition: sub/inner.txt must be indexed")
        try FileManager.default.removeItem(atPath: subDir)
        let stats = try indexer.rescanPaths([subDir])
        try reporter.require(stats.deleted >= 2,
                             "expected >=2 rows deleted (dir + inner), got \(stats.deleted)")
        try reporter.require(!(try db.fileExists(path: subDir)),
                             "sub dir still present")
        try reporter.require(!(try db.fileExists(path: subDir + "/inner.txt")),
                             "descendant still present")
    }
}

reporter.check("P3 rescanPaths on modified file re-upserts (mtime refreshed)") {
    try withP3Fixture { db, indexer, root in
        let target = root + "/initial.txt"
        // Force a detectable mtime change by writing a larger body + sleeping 1s.
        Thread.sleep(forTimeInterval: 1.05)
        try "this is a much longer body than the old one".write(
            toFile: target, atomically: true, encoding: .utf8
        )
        let before = try db.scalarInt("SELECT mtime FROM files WHERE path = '\(target)';") ?? -1
        _ = try indexer.rescanPaths([target])
        let after = try db.scalarInt("SELECT mtime FROM files WHERE path = '\(target)';") ?? -1
        try reporter.require(after > before,
                             "mtime not refreshed: before=\(before) after=\(after)")
        let size = try db.scalarInt("SELECT size FROM files WHERE path = '\(target)';") ?? -1
        try reporter.require(size > 2,
                             "size not refreshed: \(size)")
    }
}

reporter.check("P3 IncrementalWatcher + EventQueue detect real FS events end-to-end") {
    try withP3Fixture { db, indexer, root in
        // Run FSEvents + polling in parallel. Either backend surfacing the
        // change satisfies the end-to-end pipeline; in macOS sandboxes that
        // deny the FSEvents mach service (notably `codex exec` workspace-write)
        // polling becomes the active producer. EventQueue de-dupes by path so
        // double-delivery is harmless.
        let sem = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var batchCount = 0
        let q = EventQueue(options: .init(debounce: 0.1, label: "smoke.p3.e2e")) { batch in
            do { _ = try indexer.rescanPaths(batch) } catch { }
            lock.lock()
            batchCount += 1
            lock.unlock()
            sem.signal()
        }
        let watcher = IncrementalWatcher(
            roots: [root],
            eventQueue: q,
            options: .init(latency: 0.05, useFileEvents: true)
        )
        let fsStarted = watcher.start()
        let polling = PollingWatcher(
            roots: [root],
            eventQueue: q,
            options: .init(interval: 0.3, label: "smoke.p3.poll")
        )
        polling.start()
        try reporter.require(polling.isRunning, "polling watcher not running after start()")
        // Brief settle window so FSEvents (when available) is active before we
        // write the probe file.
        Thread.sleep(forTimeInterval: 0.25)

        let newURL = URL(fileURLWithPath: root + "/live-added.txt")
        try "live".write(to: newURL, atomically: true, encoding: .utf8)

        // Up to 8s for at least one batch. FSEvents path is sub-second when it
        // works; polling path fires on its 0.3s interval. Longer window is
        // purely defensive against loaded CI.
        let waitRC = sem.wait(timeout: .now() + .seconds(8))
        try reporter.require(waitRC == .success,
                             "no batch received within 8s (fsStarted=\(fsStarted))")

        // Absorb any trailing batches for the same event before asserting.
        Thread.sleep(forTimeInterval: 0.4)

        let engine = SearchEngine(database: db)
        let hits = try engine.search("live-added")
        try reporter.require(hits.contains(where: { $0.path == newURL.path }),
                             "new file not searchable via watcher pipeline (fsStarted=\(fsStarted)): \(hits.map(\.path))")
        lock.lock()
        let finalBatches = batchCount
        lock.unlock()
        try reporter.require(finalBatches >= 1,
                             "expected >=1 batches, got \(finalBatches)")

        watcher.stop()
        polling.stop()
        q.stop()
        try reporter.require(!watcher.isRunning, "watcher still running after stop()")
        try reporter.require(!polling.isRunning, "polling watcher still running after stop()")
    }
}

reporter.check("P3 PollingWatcher alone detects create/modify/delete without FSEvents") {
    try withP3Fixture { db, indexer, root in
        let sem = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var batches: [Set<String>] = []
        let q = EventQueue(options: .init(debounce: 0.1, label: "smoke.p3.poll-only")) { batch in
            do { _ = try indexer.rescanPaths(batch) } catch { }
            lock.lock()
            batches.append(batch)
            lock.unlock()
            sem.signal()
        }
        let polling = PollingWatcher(
            roots: [root],
            eventQueue: q,
            options: .init(interval: 0.25, label: "smoke.p3.poll-only-watcher")
        )
        polling.start()
        defer { polling.stop(); q.stop() }

        let added = URL(fileURLWithPath: root + "/poll-added.txt")
        try "x".write(to: added, atomically: true, encoding: .utf8)
        try reporter.require(sem.wait(timeout: .now() + .seconds(5)) == .success,
                             "polling did not emit batch for create within 5s")
        Thread.sleep(forTimeInterval: 0.3)
        let engine = SearchEngine(database: db)
        try reporter.require(try engine.search("poll-added").contains(where: { $0.path == added.path }),
                             "new file not searchable after polling convergence")

        try FileManager.default.removeItem(at: added)
        try reporter.require(sem.wait(timeout: .now() + .seconds(5)) == .success,
                             "polling did not emit batch for delete within 5s")
        Thread.sleep(forTimeInterval: 0.3)
        try reporter.require(try engine.search("poll-added").isEmpty,
                             "deleted file still searchable")
        lock.lock()
        let count = batches.count
        lock.unlock()
        try reporter.require(count >= 2, "expected >=2 polling batches, got \(count)")
    }
}

reporter.check("P3 IncrementalWatcher.start returns false for non-existent root") {
    let q = EventQueue(options: .init(debounce: 0.1, label: "smoke.p3.badroot")) { _ in }
    defer { q.stop() }
    let bogus = "/tmp/swiftseek-does-not-exist-\(UUID().uuidString)"
    let w = IncrementalWatcher(roots: [bogus], eventQueue: q)
    let ok = w.start()
    // FSEventStreamCreate accepts non-existent paths; Start may succeed but
    // never deliver. What we assert is only that start()'s return now
    // faithfully reflects FSEventStreamStart's actual result AND that stop()
    // is safe even when start "succeeded" against a ghost path.
    w.stop()
    try reporter.require(!w.isRunning, "watcher still running after stop() (ok=\(ok))")
}

// MARK: - P4 keyboard selection state machine

reporter.check("P4 KeyboardSelection: empty result set clamps currentIndex to -1") {
    var s = KeyboardSelection()
    try reporter.require(s.currentIndex == -1, "initial currentIndex=\(s.currentIndex)")
    s.moveDown(); s.moveDown()
    try reporter.require(s.currentIndex == -1,
                         "empty set moveDown left currentIndex=\(s.currentIndex)")
    s.moveUp()
    try reporter.require(s.currentIndex == -1,
                         "empty set moveUp left currentIndex=\(s.currentIndex)")
}

reporter.check("P4 KeyboardSelection: first moveDown enters index 0 when count>0") {
    var s = KeyboardSelection()
    s.setResultCount(3)
    try reporter.require(s.currentIndex == 0,
                         "setResultCount did not auto-snap to 0: \(s.currentIndex)")
    s.moveDown()
    try reporter.require(s.currentIndex == 1, "moveDown->1 got \(s.currentIndex)")
    s.moveDown()
    try reporter.require(s.currentIndex == 2, "moveDown->2 got \(s.currentIndex)")
}

reporter.check("P4 KeyboardSelection: moveDown at last wraps when wrap=true") {
    var s = KeyboardSelection()
    s.setResultCount(3)
    s.setIndex(2)
    s.moveDown()
    try reporter.require(s.currentIndex == 0, "wrap-forward failed: \(s.currentIndex)")
    s.moveUp()
    try reporter.require(s.currentIndex == 2, "wrap-backward failed: \(s.currentIndex)")
}

reporter.check("P4 KeyboardSelection: wrap=false clamps at boundaries") {
    var s = KeyboardSelection()
    s.wrap = false
    s.setResultCount(3)
    s.setIndex(2)
    s.moveDown()
    try reporter.require(s.currentIndex == 2, "clamp-down failed: \(s.currentIndex)")
    s.setIndex(0)
    s.moveUp()
    try reporter.require(s.currentIndex == 0, "clamp-up failed: \(s.currentIndex)")
}

reporter.check("P4 KeyboardSelection: setResultCount re-clamps stale index") {
    var s = KeyboardSelection()
    s.setResultCount(10)
    s.setIndex(8)
    s.setResultCount(3)
    try reporter.require(s.currentIndex == 2,
                         "re-clamp to last valid index failed: \(s.currentIndex)")
    s.setResultCount(0)
    try reporter.require(s.currentIndex == -1,
                         "drop-to-empty did not reset index: \(s.currentIndex)")
}

reporter.check("P4 KeyboardSelection: moveToFirst/moveToLast jump to edges") {
    var s = KeyboardSelection()
    s.setResultCount(5)
    s.setIndex(2)
    s.moveToLast()
    try reporter.require(s.currentIndex == 4, "moveToLast: \(s.currentIndex)")
    s.moveToFirst()
    try reporter.require(s.currentIndex == 0, "moveToFirst: \(s.currentIndex)")
}

reporter.check("P4 ResultTarget equality respects path + isDirectory") {
    let a = ResultTarget(path: "/tmp/foo", isDirectory: false)
    let b = ResultTarget(path: "/tmp/foo", isDirectory: false)
    let c = ResultTarget(path: "/tmp/foo", isDirectory: true)
    try reporter.require(a == b, "identical targets not equal")
    try reporter.require(a != c, "isDirectory flag ignored in equality")
}

// MARK: - P4 startup path (mirrors AppDelegate.applicationDidFinishLaunching Core portion)

reporter.check("P4 startup: AppPaths + Database.open + migrate reaches latest schema (AppDelegate path)") {
    // Exercises exactly the code path AppDelegate runs before constructing
    // SearchWindowController — proves the Core startup succeeds in any env.
    let root = try makeTempDir()
    defer { cleanup(root) }
    let paths = try AppPaths.ensureSupportDirectory(override: root)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "schema=\(db.schemaVersion) expected=\(Schema.currentVersion)")
    try reporter.require(FileManager.default.fileExists(atPath: paths.databaseURL.path),
                         "sqlite file missing at \(paths.databaseURL.path)")
    // Prove SearchEngine can be constructed with this DB (what SearchViewController does).
    let engine = SearchEngine(database: db)
    let hits = try engine.search("anything")
    // Empty index → no results, but no throw → engine init + search path work.
    try reporter.require(hits.isEmpty, "empty DB should return no hits, got \(hits.count)")
}

reporter.check("P4 SearchEngine round-trip: index file then search from same DB (SearchViewController path)") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    let root = try makeTempDir()
    defer { cleanup(root) }
    try "hello".write(to: root.appendingPathComponent("hello-world.txt"),
                      atomically: true, encoding: .utf8)
    let indexer = Indexer(database: db)
    _ = try indexer.indexRoot(root)

    // SearchEngine(database:) is what SearchViewController constructs.
    let engine = SearchEngine(database: db)
    let hits = try engine.search("hello-world")
    try reporter.require(!hits.isEmpty, "indexed file not found via SearchEngine")
    try reporter.require(hits[0].path.hasSuffix("/hello-world.txt"),
                         "wrong result: \(hits[0].path)")
}

// MARK: - P5 settings / roots / excludes / hidden files / rebuild / diagnostics

func withP5Fixture(_ body: (Database) throws -> Void) throws {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try body(db)
}

reporter.check("P5 schema migration reaches current version and creates `settings` table") {
    try withP5Fixture { db in
        try reporter.require(db.schemaVersion == Schema.currentVersion,
                             "schema=\(db.schemaVersion) expected=\(Schema.currentVersion)")
        try reporter.require(try db.tableExists("settings"),
                             "settings table missing")
        // G3+: fresh DB seeds `index_mode=compact` in v5 migration, so
        // the settings table is no longer empty. Assert on absence of
        // user-facing settings instead of raw row count.
        let unexpected = try db.scalarInt("""
            SELECT COUNT(*) FROM settings
            WHERE key NOT IN ('\(SettingsKey.indexMode)');
        """) ?? -1
        try reporter.require(unexpected == 0,
                             "fresh DB should only have the schema-seeded settings row(s); unexpected=\(unexpected)")
    }
}

reporter.check("P5 roots: add / list / enable toggle / remove persist and cascade files") {
    try withP5Fixture { db in
        let root = try makeTempDir()
        defer { cleanup(root) }
        try "a".write(to: root.appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        let canonical = Indexer.canonicalize(path: root.path)
        let indexer = Indexer(database: db)
        _ = try indexer.indexRoot(root)

        // Round 1: root is registered via indexRoot
        let rootsBefore = try db.listRoots()
        try reporter.require(rootsBefore.count == 1,
                             "expected 1 root got \(rootsBefore.count)")
        try reporter.require(rootsBefore[0].enabled,
                             "fresh root should be enabled")

        // Toggle enabled off
        try db.setRootEnabled(id: rootsBefore[0].id, enabled: false)
        let afterToggle = try db.listRoots()
        try reporter.require(!afterToggle[0].enabled, "toggle didn't persist")

        // Files still present (disable doesn't delete)
        try reporter.require(try db.fileExists(path: canonical + "/a.txt"),
                             "disable should not prune files")

        // Remove root: files cascade
        try db.removeRoot(id: afterToggle[0].id)
        try reporter.require(try db.listRoots().isEmpty, "remove didn't clear roots")
        try reporter.require(!(try db.fileExists(path: canonical + "/a.txt")),
                             "remove didn't cascade files")
    }
}

reporter.check("P5 excludes: first-time indexing skips excluded directory") {
    try withP5Fixture { db in
        let root = try makeTempDir()
        defer { cleanup(root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("keep"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("drop"),
                               withIntermediateDirectories: true)
        try "k".write(to: root.appendingPathComponent("keep/file.txt"),
                      atomically: true, encoding: .utf8)
        try "d".write(to: root.appendingPathComponent("drop/secret.txt"),
                      atomically: true, encoding: .utf8)
        let canonical = Indexer.canonicalize(path: root.path)
        let dropPath = canonical + "/drop"
        _ = try db.addExclude(pattern: dropPath)

        let indexer = Indexer(database: db)
        let stats = try indexer.indexRoot(
            root,
            options: .init(batchSize: 100,
                           progressEvery: 100,
                           clearBeforeIndex: true,
                           excludes: [dropPath],
                           includeHiddenFiles: true)
        )
        try reporter.require(stats.skipped >= 1,
                             "expected drop/ to be skipped (skipped=\(stats.skipped))")
        try reporter.require(try db.fileExists(path: canonical + "/keep/file.txt"),
                             "keep/file.txt should be indexed")
        try reporter.require(!(try db.fileExists(path: canonical + "/drop/secret.txt")),
                             "drop/secret.txt should NOT be indexed")
        let engine = SearchEngine(database: db)
        let hits = try engine.search("secret")
        try reporter.require(hits.isEmpty,
                             "excluded file leaked into search: \(hits.map(\.path))")
    }
}

reporter.check("P5 excludes: adding exclude purges already-indexed subtree via deleteFilesMatchingExclude") {
    try withP5Fixture { db in
        let root = try makeTempDir()
        defer { cleanup(root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("cache"),
                               withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("cache/big.log"),
                      atomically: true, encoding: .utf8)
        try "y".write(to: root.appendingPathComponent("keep.txt"),
                      atomically: true, encoding: .utf8)
        let canonical = Indexer.canonicalize(path: root.path)
        let indexer = Indexer(database: db)
        _ = try indexer.indexRoot(root)

        // Everything indexed (no excludes yet)
        try reporter.require(try db.fileExists(path: canonical + "/cache/big.log"),
                             "precondition: big.log should be indexed")

        // Add exclude and purge
        let cachePath = canonical + "/cache"
        _ = try db.addExclude(pattern: cachePath)
        let removed = try db.deleteFilesMatchingExclude(cachePath)
        try reporter.require(removed >= 2,
                             "expected >=2 rows purged (cache dir + big.log), got \(removed)")
        try reporter.require(!(try db.fileExists(path: canonical + "/cache/big.log")),
                             "big.log still present after exclude purge")
        try reporter.require(try db.fileExists(path: canonical + "/keep.txt"),
                             "keep.txt should survive exclude purge")
    }
}

reporter.check("P5 hidden files: toggle off skips .dot paths, toggle on includes them") {
    try withP5Fixture { db in
        let root = try makeTempDir()
        defer { cleanup(root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".git"),
                               withIntermediateDirectories: true)
        try "cfg".write(to: root.appendingPathComponent(".git/config"),
                        atomically: true, encoding: .utf8)
        try "v".write(to: root.appendingPathComponent("visible.txt"),
                      atomically: true, encoding: .utf8)
        let canonical = Indexer.canonicalize(path: root.path)
        let indexer = Indexer(database: db)

        // Hidden OFF
        _ = try indexer.indexRoot(
            root,
            options: .init(clearBeforeIndex: true,
                           excludes: [],
                           includeHiddenFiles: false)
        )
        try reporter.require(try db.fileExists(path: canonical + "/visible.txt"),
                             "visible.txt should be indexed")
        try reporter.require(!(try db.fileExists(path: canonical + "/.git/config")),
                             "dotfile should be skipped with hidden=OFF")

        // Hidden ON
        _ = try indexer.indexRoot(
            root,
            options: .init(clearBeforeIndex: true,
                           excludes: [],
                           includeHiddenFiles: true)
        )
        try reporter.require(try db.fileExists(path: canonical + "/.git/config"),
                             "dotfile should appear with hidden=ON")
    }
}

reporter.check("P5 settings K/V: hidden-files toggle persists round-trip") {
    try withP5Fixture { db in
        try reporter.require(!(try db.getHiddenFilesEnabled()),
                             "default should be false (unset)")
        try db.setHiddenFilesEnabled(true)
        try reporter.require(try db.getHiddenFilesEnabled(),
                             "setTrue failed to persist")
        try db.setHiddenFilesEnabled(false)
        try reporter.require(!(try db.getHiddenFilesEnabled()),
                             "setFalse failed to persist")
    }
}

reporter.check("P5 RebuildCoordinator: walks enabled roots and stamps last_rebuild_*") {
    try withP5Fixture { db in
        let root1 = try makeTempDir()
        defer { cleanup(root1) }
        try "a".write(to: root1.appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        let root2 = try makeTempDir()
        defer { cleanup(root2) }
        try "b".write(to: root2.appendingPathComponent("b.txt"),
                      atomically: true, encoding: .utf8)
        _ = try db.registerRoot(path: Indexer.canonicalize(path: root1.path))
        _ = try db.registerRoot(path: Indexer.canonicalize(path: root2.path))

        let coord = RebuildCoordinator(database: db)
        let sem = DispatchSemaphore(value: 0)
        var finished: RebuildCoordinator.Summary?
        let started = coord.rebuild(onFinish: { s in
            finished = s
            sem.signal()
        })
        try reporter.require(started, "rebuild not started")
        let waitRC = sem.wait(timeout: .now() + .seconds(10))
        try reporter.require(waitRC == .success, "rebuild did not finish within 10s")
        let s = finished!
        try reporter.require(s.error == nil, "rebuild error: \(s.error!)")
        try reporter.require(s.roots == 2, "roots=\(s.roots)")
        try reporter.require(s.totalInserted >= 4, "inserted=\(s.totalInserted)")

        let lastResult = try db.getSetting(SettingsKey.lastRebuildResult)
        try reporter.require(lastResult == "success",
                             "last_rebuild_result=\(lastResult ?? "nil")")
        let lastAt = try db.getSetting(SettingsKey.lastRebuildAt)
        try reporter.require(lastAt != nil && !lastAt!.isEmpty,
                             "last_rebuild_at not stamped")
        let lastStats = try db.getSetting(SettingsKey.lastRebuildStats) ?? ""
        try reporter.require(lastStats.contains("roots=2"),
                             "last_rebuild_stats=\(lastStats)")
    }
}

reporter.check("P5 RebuildCoordinator: concurrent call returns false (prevents duplicate rebuild)") {
    try withP5Fixture { db in
        // G3: compact mode writes ~10x fewer gram rows per file, so the
        // first rebuild races past 10ms easily. Use fullpath + more
        // files to make the busy window reliably long enough for the
        // race. This test is about the state-lock contract, not mode.
        try db.setIndexMode(.fullpath)
        let root1 = try makeTempDir()
        defer { cleanup(root1) }
        // Fill with many files so first rebuild stays busy long enough for
        // the second call to race it.
        for i in 0..<2000 {
            try "x".write(to: root1.appendingPathComponent("file-with-a-reasonably-long-name-\(i).txt"),
                          atomically: true, encoding: .utf8)
        }
        _ = try db.registerRoot(path: Indexer.canonicalize(path: root1.path))
        let coord = RebuildCoordinator(database: db)

        let firstStarted = coord.rebuild()
        try reporter.require(firstStarted, "first rebuild did not start")
        // Second call races — the internal state lock is held briefly so allow
        // a tiny yield to make this deterministic.
        Thread.sleep(forTimeInterval: 0.001)
        let secondStarted = coord.rebuild()
        try reporter.require(!secondStarted,
                             "second rebuild should be rejected while one is running")
        // Drain: poll state until coordinator returns to idle (at most 10s)
        let deadline = Date().addingTimeInterval(10)
        while coord.isRebuilding && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try reporter.require(!coord.isRebuilding,
                             "coordinator did not return to idle within 10s")
    }
}

reporter.check("P5 ExcludeFilter helper matches exact + descendant, spares siblings with shared prefix") {
    try reporter.require(ExcludeFilter.isExcluded("/tmp/drop", patterns: ["/tmp/drop"]),
                         "exact match missed")
    try reporter.require(ExcludeFilter.isExcluded("/tmp/drop/x.txt", patterns: ["/tmp/drop"]),
                         "descendant missed")
    try reporter.require(!ExcludeFilter.isExcluded("/tmp/dropbox", patterns: ["/tmp/drop"]),
                         "sibling-with-shared-prefix was wrongly matched")
    try reporter.require(!ExcludeFilter.isExcluded("/tmp/other", patterns: ["/tmp/drop"]),
                         "unrelated path was wrongly matched")
}

reporter.check("P5 disabled root: indexed files are not returned by SearchEngine while root is disabled; re-enable restores") {
    try withP5Fixture { db in
        let root = try makeTempDir()
        defer { cleanup(root) }
        try "alpha".write(to: root.appendingPathComponent("alpha.txt"),
                          atomically: true, encoding: .utf8)
        let indexer = Indexer(database: db)
        _ = try indexer.indexRoot(root)

        // Baseline: search finds alpha.txt (root enabled by default)
        let engine = SearchEngine(database: db)
        let beforeHits = try engine.search("alpha")
        try reporter.require(beforeHits.contains(where: { $0.path.hasSuffix("/alpha.txt") }),
                             "precondition: alpha.txt should be searchable when root is enabled")

        // Disable the root
        let roots = try db.listRoots()
        try reporter.require(roots.count == 1, "expected 1 root, got \(roots.count)")
        try db.setRootEnabled(id: roots[0].id, enabled: false)

        let disabledHits = try engine.search("alpha")
        try reporter.require(!disabledHits.contains(where: { $0.path.hasSuffix("/alpha.txt") }),
                             "disabled root still returns hits: \(disabledHits.map(\.path))")

        // Re-enable: results come back (files were not deleted)
        try db.setRootEnabled(id: roots[0].id, enabled: true)
        let reenabledHits = try engine.search("alpha")
        try reporter.require(reenabledHits.contains(where: { $0.path.hasSuffix("/alpha.txt") }),
                             "re-enable did not restore hits")
    }
}

reporter.check("P5 disabled root: excluded path search also hidden (filter applies to all score bands)") {
    try withP5Fixture { db in
        let root = try makeTempDir()
        defer { cleanup(root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("docs"),
                               withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("docs/alpha-notes.md"),
                      atomically: true, encoding: .utf8)
        let indexer = Indexer(database: db)
        _ = try indexer.indexRoot(root)

        let roots = try db.listRoots()
        try db.setRootEnabled(id: roots[0].id, enabled: false)
        let engine = SearchEngine(database: db)
        // path-only match (score 200) should also be gated
        let pathHits = try engine.search("docs/alpha")
        try reporter.require(!pathHits.contains(where: { $0.path.hasSuffix("/docs/alpha-notes.md") }),
                             "path-only hit leaked past disabled-root filter: \(pathHits.map(\.path))")
    }
}

reporter.check("P5 pathUnderAnyRoot helper: exact + descendant, spares siblings with shared prefix and rejects unrelated") {
    try reporter.require(SearchEngine.pathUnderAnyRoot("/a/b", roots: ["/a/b"]),
                         "exact match missed")
    try reporter.require(SearchEngine.pathUnderAnyRoot("/a/b/c", roots: ["/a/b"]),
                         "descendant missed")
    try reporter.require(!SearchEngine.pathUnderAnyRoot("/a/bc", roots: ["/a/b"]),
                         "sibling-with-shared-prefix leaked")
    try reporter.require(!SearchEngine.pathUnderAnyRoot("/x/y", roots: ["/a/b"]),
                         "unrelated path leaked")
    try reporter.require(!SearchEngine.pathUnderAnyRoot("/a/b", roots: []),
                         "empty roots should reject")
}

reporter.check("P5 HiddenPath helper recognises dot components, not mid-name dots") {
    try reporter.require(HiddenPath.isHidden("/Users/x/.git/config"),
                         ".git component missed")
    try reporter.require(HiddenPath.isHidden("/Users/x/.DS_Store"),
                         ".DS_Store missed")
    try reporter.require(!HiddenPath.isHidden("/Users/x/notes.md"),
                         "regular file wrongly called hidden")
    try reporter.require(!HiddenPath.isHidden("/Users/x/foo.bar/baz"),
                         "mid-name dot wrongly called hidden")
}

// MARK: - E1 (everything-alignment): relevance + limit

reporter.check("E1 tokenize splits on whitespace, preserves /") {
    try reporter.require(SearchEngine.tokenize("  foo  bar  ") == ["foo", "bar"],
                         "multi-space split broken")
    try reporter.require(SearchEngine.tokenize("docs/alpha") == ["docs/alpha"],
                         "slashes must stay intra-token")
    try reporter.require(SearchEngine.tokenize("") == [],
                         "empty query must yield no tokens")
    try reporter.require(SearchEngine.tokenize("\tALPHA\nBETA  gamma") == ["alpha", "beta", "gamma"],
                         "tokenize should normalize case and whitespace")
}

reporter.check("E1 multi-word query has AND semantics") {
    // Fixture with: foo-only row, bar-only row, and one row with both.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("sub"),
                           withIntermediateDirectories: true)
    for f in ["foo-alpha.txt", "bar-beta.txt", "sub/foo-bar-report.txt"] {
        try "".write(to: root.appendingPathComponent(f),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("foo bar")
    try reporter.require(hits.count == 1,
                         "AND should match exactly one row, got \(hits.count): \(hits.map(\.path))")
    try reporter.require(hits[0].path.hasSuffix("/sub/foo-bar-report.txt"),
                         "wrong AND hit: \(hits[0].path)")
}

reporter.check("E1 basename bonus: name-match outscores path-only match") {
    // Same base tier (contains vs path-only), bonus pushes name-match above.
    let n1 = SearchEngine.score(query: "foo", nameLower: "myfoobar.txt", pathLower: "/a/myfoobar.txt")
    let n2 = SearchEngine.score(query: "foo", nameLower: "readme.md", pathLower: "/a/foodir/readme.md")
    try reporter.require(n1 > n2,
                         "basename-match should outscore path-only: \(n1) vs \(n2)")
}

reporter.check("E1 token-boundary bonus kicks in at / . - _ space") {
    // "foo" with boundary: preceded by "/" in path and start-of-name.
    let boundary = SearchEngine.score(query: "foo",
                                      nameLower: "foo.txt",
                                      pathLower: "/a/foo.txt")
    // "foo" buried mid-name without any boundary adjacency.
    let noBoundary = SearchEngine.score(query: "foo",
                                        nameLower: "xfoox.txt",
                                        pathLower: "/a/xfoox.txt")
    try reporter.require(boundary > noBoundary,
                         "boundary hit should outscore mid-name hit: \(boundary) vs \(noBoundary)")
}

reporter.check("E1 path-segment bonus rewards exact segment match") {
    // "docs" as exact segment vs contained inside a longer segment.
    let segment = SearchEngine.score(query: "docs",
                                     nameLower: "readme.md",
                                     pathLower: "/a/docs/readme.md")
    let inside = SearchEngine.score(query: "docs",
                                    nameLower: "readme.md",
                                    pathLower: "/a/docs-old/readme.md")
    try reporter.require(segment > inside,
                         "exact segment should outscore contained: \(segment) vs \(inside)")
}

reporter.check("E1 extension bonus rewards matching extension token") {
    // Keep base tier the same (both name-contains, not prefix) so that the
    // only score delta comes from the extension bonus itself.
    //   readme.md → contains(500)+basename(50)+ext(80)+boundary(30)=660
    //   readme.mdx → contains(500)+basename(50)+boundary(30)=580 (ext=mdx, no bonus)
    let extHit = SearchEngine.score(query: "md",
                                    nameLower: "readme.md",
                                    pathLower: "/a/readme.md")
    let noExt = SearchEngine.score(query: "md",
                                   nameLower: "readme.mdx",
                                   pathLower: "/a/readme.mdx")
    try reporter.require(extHit > noExt,
                         "extension match should outscore non-extension: \(extHit) vs \(noExt)")
    try reporter.require(extHit - noExt == 80,
                         "extension bonus should be +80, got delta \(extHit - noExt)")
}

reporter.check("E1 multi-token all-in-basename bonus applies when every token hits basename") {
    // Two tokens both in name vs split across name and path.
    let allName = SearchEngine.scoreTokens(["foo", "bar"],
                                           nameLower: "foo-bar-report.txt",
                                           pathLower: "/a/foo-bar-report.txt")
    let splitAcross = SearchEngine.scoreTokens(["foo", "bar"],
                                               nameLower: "foo-report.txt",
                                               pathLower: "/a/bar/foo-report.txt")
    try reporter.require(allName > splitAcross,
                         "all-in-basename should outscore split match: \(allName) vs \(splitAcross)")
}

reporter.check("E1 search limit setting round-trips through Database settings table") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()

    // Unset → default
    try reporter.require(try db.getSearchLimit() == SearchLimitBounds.defaultValue,
                         "default limit should be \(SearchLimitBounds.defaultValue)")
    // Valid write
    try db.setSearchLimit(250)
    try reporter.require(try db.getSearchLimit() == 250, "round-trip 250 failed")
    // Clamping: above max
    try db.setSearchLimit(99999)
    let high = try db.getSearchLimit()
    try reporter.require(high == SearchLimitBounds.maximum,
                         "upper clamp failed: got \(high)")
    // Clamping: below min
    try db.setSearchLimit(1)
    let low = try db.getSearchLimit()
    try reporter.require(low == SearchLimitBounds.minimum,
                         "lower clamp failed: got \(low)")
}

reporter.check("E1 search limit actually caps returned results") {
    // Fixture: index >30 files, verify a limit of 5 caps the result count.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    for i in 0..<40 {
        try "".write(to: root.appendingPathComponent("alpha-\(i).txt"),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let few = try engine.search("alpha", options: .init(limit: 5))
    try reporter.require(few.count == 5,
                         "limit=5 should cap results, got \(few.count)")
    let many = try engine.search("alpha", options: .init(limit: 100))
    try reporter.require(many.count == 40,
                         "limit=100 should return all 40, got \(many.count)")
}

reporter.check("E1 SearchEngine.Options.limit default is the configured floor, not hardcoded 20") {
    // Regression guard against re-introducing the legacy hardcoded 20.
    let opt = SearchEngine.Options()
    try reporter.require(opt.limit >= SearchLimitBounds.minimum,
                         "default limit \(opt.limit) below floor \(SearchLimitBounds.minimum)")
    try reporter.require(opt.limit > 20,
                         "default limit \(opt.limit) still hardcoded at the legacy 20")
}

// MARK: - E2 (result view + sort switching)

// Hand-built fixture rows — avoids DB overhead and lets us pin mtime/size.
func makeE2Fixture() -> [SearchResult] {
    return [
        SearchResult(path: "/a/apple.txt",  name: "apple.txt",  isDir: false, size: 100, mtime: 1000, score: 880),
        SearchResult(path: "/a/banana.txt", name: "banana.txt", isDir: false, size:  50, mtime: 2000, score: 600),
        SearchResult(path: "/a/cherry.txt", name: "cherry.txt", isDir: false, size: 300, mtime: 1500, score: 500),
        SearchResult(path: "/b/date.txt",   name: "date.txt",   isDir: false, size: 200, mtime: 3000, score: 880),
    ]
}

reporter.check("E2 default sort is score descending (match native ranking)") {
    let input = makeE2Fixture()
    let out = SearchEngine.sort(input, by: .scoreDescending)
    try reporter.require(out.count == input.count,
                         "sort should preserve cardinality: \(out.count) vs \(input.count)")
    // Score-desc tie-break: shorter path first, then alphabetical. The two
    // 880-score entries are /a/apple.txt (12 chars) and /b/date.txt (11),
    // so date.txt must win the tie.
    try reporter.require(out[0].name == "date.txt",
                         "tie-break: date.txt should win, got \(out[0].name)")
    try reporter.require(out[1].name == "apple.txt",
                         "second should be apple.txt, got \(out[1].name)")
    try reporter.require(out.map(\.score) == [880, 880, 600, 500],
                         "score column order broken: \(out.map(\.score))")
}

reporter.check("E2 sort by name ascending / descending is total and reversible") {
    let input = makeE2Fixture()
    let asc = SearchEngine.sort(input, by: .init(key: .name, ascending: true))
    try reporter.require(asc.map(\.name) == ["apple.txt", "banana.txt", "cherry.txt", "date.txt"],
                         "name asc order broken: \(asc.map(\.name))")
    let desc = SearchEngine.sort(input, by: .init(key: .name, ascending: false))
    try reporter.require(desc.map(\.name) == ["date.txt", "cherry.txt", "banana.txt", "apple.txt"],
                         "name desc order broken: \(desc.map(\.name))")
}

reporter.check("E2 sort by mtime descending places newest first") {
    let input = makeE2Fixture()
    let out = SearchEngine.sort(input, by: .init(key: .mtime, ascending: false))
    try reporter.require(out.map(\.mtime) == [3000, 2000, 1500, 1000],
                         "mtime desc order broken: \(out.map(\.mtime))")
}

reporter.check("E2 sort by size ascending places smallest first") {
    let input = makeE2Fixture()
    let out = SearchEngine.sort(input, by: .init(key: .size, ascending: true))
    try reporter.require(out.map(\.size) == [50, 100, 200, 300],
                         "size asc order broken: \(out.map(\.size))")
}

reporter.check("E2 sort is reversible: switching away and back to default restores ranking") {
    let input = makeE2Fixture()
    let defaultOrder = SearchEngine.sort(input, by: .scoreDescending)
    let viaName = SearchEngine.sort(input, by: .init(key: .name, ascending: true))
    let backToDefault = SearchEngine.sort(viaName, by: .scoreDescending)
    try reporter.require(backToDefault == defaultOrder,
                         "default order not restored after re-sort")
}

reporter.check("E2 sort handles equal primary keys with deterministic tie-break (shorter path, then alphabetical)") {
    // Two rows with identical score + mtime + size: order must come from
    // the path tie-break rule (shorter path wins, then alphabetical).
    let input: [SearchResult] = [
        SearchResult(path: "/a/longer/zzz.txt", name: "zzz.txt", isDir: false, size: 0, mtime: 0, score: 500),
        SearchResult(path: "/a/z.txt",          name: "z.txt",   isDir: false, size: 0, mtime: 0, score: 500),
        SearchResult(path: "/a/y.txt",          name: "y.txt",   isDir: false, size: 0, mtime: 0, score: 500),
    ]
    let out = SearchEngine.sort(input, by: .scoreDescending)
    // Shortest paths first: /a/y.txt and /a/z.txt both have length 8.
    // Alphabetical tie-break → y before z. Longer /a/longer/zzz.txt last.
    try reporter.require(out.map(\.path) == ["/a/y.txt", "/a/z.txt", "/a/longer/zzz.txt"],
                         "tie-break order broken: \(out.map(\.path))")
}

reporter.check("E2 sort by name is case-insensitive") {
    // Ensure "Apple" and "apple" sort together even if one is uppercased.
    let input: [SearchResult] = [
        SearchResult(path: "/a/Banana.txt", name: "Banana.txt", isDir: false, size: 0, mtime: 0, score: 500),
        SearchResult(path: "/a/apple.txt",  name: "apple.txt",  isDir: false, size: 0, mtime: 0, score: 500),
    ]
    let out = SearchEngine.sort(input, by: .init(key: .name, ascending: true))
    try reporter.require(out[0].name == "apple.txt",
                         "case-insensitive asc broken: \(out.map(\.name))")
}

// MARK: - E3 (query filter syntax)

reporter.check("E3 parser: plain-only query has no filters") {
    let p = SearchEngine.parseQuery("foo bar")
    try reporter.require(p.plainTokens == ["foo", "bar"],
                         "plain tokens wrong: \(p.plainTokens)")
    try reporter.require(p.filters.isEmpty,
                         "empty query should have no filters")
}

reporter.check("E3 parser: ext:md extracts single extension") {
    let p = SearchEngine.parseQuery("ext:md alpha")
    try reporter.require(p.plainTokens == ["alpha"],
                         "plain tokens wrong: \(p.plainTokens)")
    try reporter.require(p.filters.extensions == ["md"],
                         "ext filter wrong: \(p.filters.extensions)")
}

reporter.check("E3 parser: ext:md,txt,pdf extracts multi-extensions") {
    let p = SearchEngine.parseQuery("ext:md,txt,pdf")
    try reporter.require(p.filters.extensions == ["md", "txt", "pdf"],
                         "multi ext broken: \(p.filters.extensions)")
}

reporter.check("E3 parser: kind:file and kind:dir recognised, unknown kind dropped silently") {
    let p1 = SearchEngine.parseQuery("kind:file")
    try reporter.require(p1.filters.kinds == [.file],
                         "kind:file broken")
    let p2 = SearchEngine.parseQuery("kind:dir")
    try reporter.require(p2.filters.kinds == [.dir],
                         "kind:dir broken")
    let p3 = SearchEngine.parseQuery("kind:foobar")
    try reporter.require(p3.filters.kinds.isEmpty,
                         "unknown kind should be dropped silently, not accepted")
}

reporter.check("E3 parser: path:foo adds a path-only token") {
    let p = SearchEngine.parseQuery("path:docs alpha")
    try reporter.require(p.plainTokens == ["alpha"],
                         "plain token leaked path filter: \(p.plainTokens)")
    try reporter.require(p.filters.pathTokens == ["docs"],
                         "path filter broken: \(p.filters.pathTokens)")
}

reporter.check("E3 parser: root:/x trims trailing slash") {
    let p1 = SearchEngine.parseQuery("root:/a/b/c")
    try reporter.require(p1.filters.rootRestriction == "/a/b/c",
                         "root filter without slash broken: \(String(describing: p1.filters.rootRestriction))")
    let p2 = SearchEngine.parseQuery("root:/a/b/c/")
    try reporter.require(p2.filters.rootRestriction == "/a/b/c",
                         "root filter trailing slash should be stripped: \(String(describing: p2.filters.rootRestriction))")
}

reporter.check("E3 parser: hidden:true / false accepts common aliases") {
    for raw in ["hidden:true", "hidden:yes", "hidden:1", "hidden:on"] {
        let p = SearchEngine.parseQuery(raw)
        try reporter.require(p.filters.hiddenMode == .requireHidden,
                             "hidden positive alias failed for \(raw)")
    }
    for raw in ["hidden:false", "hidden:no", "hidden:0", "hidden:off"] {
        let p = SearchEngine.parseQuery(raw)
        try reporter.require(p.filters.hiddenMode == .requireVisible,
                             "hidden negative alias failed for \(raw)")
    }
    let bogus = SearchEngine.parseQuery("hidden:maybe")
    try reporter.require(bogus.filters.hiddenMode == .unspecified,
                         "bogus hidden value should stay unspecified")
}

reporter.check("E3 parser: unknown key:value stays as plain token") {
    // Parser must not silently adopt unknown keys as filters — they go to
    // plain tokens so the user sees exactly what the engine interprets.
    let p = SearchEngine.parseQuery("foo:bar baz")
    try reporter.require(p.filters.isEmpty,
                         "unknown filter key was incorrectly adopted")
    try reporter.require(p.plainTokens == ["foo:bar", "baz"],
                         "plain fallback broken: \(p.plainTokens)")
}

reporter.check("E3 parser: empty filter value is ignored, not an error") {
    let p = SearchEngine.parseQuery("ext: alpha")
    try reporter.require(p.filters.extensions.isEmpty,
                         "empty ext value should be ignored")
    try reporter.require(p.plainTokens == ["alpha"],
                         "partial-type ext token leaked: \(p.plainTokens)")
}

reporter.check("E3 filter predicate: ext filter keeps only matching extension") {
    let f = QueryFilters(extensions: ["md"])
    try reporter.require(SearchEngine.matches(nameLower: "readme.md",
                                              pathLower: "/a/readme.md",
                                              path: "/a/readme.md",
                                              isDir: false, filters: f),
                         "md file should match ext:md")
    try reporter.require(!SearchEngine.matches(nameLower: "readme.txt",
                                               pathLower: "/a/readme.txt",
                                               path: "/a/readme.txt",
                                               isDir: false, filters: f),
                         "txt file should not match ext:md")
    try reporter.require(!SearchEngine.matches(nameLower: "mdfile",
                                               pathLower: "/a/mdfile",
                                               path: "/a/mdfile",
                                               isDir: false, filters: f),
                         "no-extension file should not match ext:md")
}

reporter.check("E3 filter predicate: kind:dir admits only directories") {
    let f = QueryFilters(kinds: [.dir])
    try reporter.require(SearchEngine.matches(nameLower: "docs",
                                              pathLower: "/a/docs",
                                              path: "/a/docs",
                                              isDir: true, filters: f),
                         "dir should match kind:dir")
    try reporter.require(!SearchEngine.matches(nameLower: "a.txt",
                                               pathLower: "/a/a.txt",
                                               path: "/a/a.txt",
                                               isDir: false, filters: f),
                         "file should not match kind:dir")
}

reporter.check("E3 filter predicate: root:/a/b restricts to that subtree") {
    let f = QueryFilters(rootRestriction: "/a/b")
    try reporter.require(SearchEngine.matches(nameLower: "x.txt",
                                              pathLower: "/a/b/x.txt",
                                              path: "/a/b/x.txt",
                                              isDir: false, filters: f),
                         "descendant should match root restriction")
    try reporter.require(SearchEngine.matches(nameLower: "b",
                                              pathLower: "/a/b",
                                              path: "/a/b",
                                              isDir: true, filters: f),
                         "root itself should match")
    try reporter.require(!SearchEngine.matches(nameLower: "x.txt",
                                               pathLower: "/a/bb/x.txt",
                                               path: "/a/bb/x.txt",
                                               isDir: false, filters: f),
                         "sibling-with-shared-prefix must not leak")
    try reporter.require(!SearchEngine.matches(nameLower: "x.txt",
                                               pathLower: "/other/x.txt",
                                               path: "/other/x.txt",
                                               isDir: false, filters: f),
                         "unrelated path must not match")
}

reporter.check("E3 filter predicate: hidden:true admits only hidden paths") {
    let f = QueryFilters(hiddenMode: .requireHidden)
    try reporter.require(SearchEngine.matches(nameLower: "config",
                                              pathLower: "/a/.git/config",
                                              path: "/a/.git/config",
                                              isDir: false, filters: f),
                         ".git path should match hidden:true")
    try reporter.require(!SearchEngine.matches(nameLower: "readme.md",
                                               pathLower: "/a/readme.md",
                                               path: "/a/readme.md",
                                               isDir: false, filters: f),
                         "visible path should not match hidden:true")
}

reporter.check("E3 filter predicate: hidden:false excludes hidden paths") {
    let f = QueryFilters(hiddenMode: .requireVisible)
    try reporter.require(!SearchEngine.matches(nameLower: "config",
                                               pathLower: "/a/.git/config",
                                               path: "/a/.git/config",
                                               isDir: false, filters: f),
                         ".git path should not match hidden:false")
    try reporter.require(SearchEngine.matches(nameLower: "readme.md",
                                              pathLower: "/a/readme.md",
                                              path: "/a/readme.md",
                                              isDir: false, filters: f),
                         "visible path should match hidden:false")
}

reporter.check("E3 end-to-end: ext + plain token combine via AND") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    for f in ["alpha.md", "alpha.txt", "beta.md", "beta.txt"] {
        try "".write(to: root.appendingPathComponent(f), atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("alpha ext:md")
    try reporter.require(hits.count == 1,
                         "expected 1 md+alpha hit, got \(hits.count): \(hits.map(\.path))")
    try reporter.require(hits[0].path.hasSuffix("/alpha.md"),
                         "wrong hit: \(hits[0].path)")
}

reporter.check("E3 end-to-end: filter-only query returns mtime-sorted results") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    for f in ["note.md", "readme.md", "todo.md", "skip.txt"] {
        try "".write(to: root.appendingPathComponent(f), atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("ext:md")
    try reporter.require(hits.count == 3,
                         "expected 3 md results, got \(hits.count): \(hits.map(\.path))")
    for h in hits {
        try reporter.require(h.path.hasSuffix(".md"),
                             "non-md hit leaked: \(h.path)")
    }
}

// MARK: - E4 (index automation + root health)

reporter.check("E4 RootHealth.paused: disabled root flagged paused regardless of disk state") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let realDir = try makeTempDir()
    defer { cleanup(realDir) }
    let rowId = try db.registerRoot(path: realDir.path)
    try db.setRootEnabled(id: rowId, enabled: false)
    let row = try db.listRoots().first { $0.id == rowId }!
    let h = db.computeRootHealth(for: row)
    try reporter.require(h == .paused,
                         "disabled root should report paused, got \(h)")
}

reporter.check("E4 RootHealth.ready: enabled + exists + readable = ready") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let realDir = try makeTempDir()
    defer { cleanup(realDir) }
    _ = try db.registerRoot(path: realDir.path)
    let row = try db.listRoots().first!
    let h = db.computeRootHealth(for: row)
    try reporter.require(h == .ready,
                         "existing enabled root should be ready, got \(h)")
}

reporter.check("E4 RootHealth.offline: enabled + missing path = offline") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Fabricate a path that can't exist: /private/var/tmp/... with a
    // random suffix to simulate an ejected external volume or a moved
    // / deleted directory.
    let ghost = "/private/var/tmp/swiftseek-offline-\(UUID().uuidString)"
    _ = try db.registerRoot(path: ghost)
    let row = try db.listRoots().first!
    let h = db.computeRootHealth(for: row)
    try reporter.require(h == .offline,
                         "missing path should report offline, got \(h)")
}

reporter.check("E4 RootHealth.indexing: pinned via currentlyIndexingPath parameter") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let realDir = try makeTempDir()
    defer { cleanup(realDir) }
    _ = try db.registerRoot(path: realDir.path)
    let row = try db.listRoots().first!
    let h = db.computeRootHealth(for: row, currentlyIndexingPath: row.path)
    try reporter.require(h == .indexing,
                         "active indexing should flip to .indexing, got \(h)")
    // Unrelated active path → still ready.
    let hOther = db.computeRootHealth(for: row, currentlyIndexingPath: "/other")
    try reporter.require(hOther == .ready,
                         "unrelated active path should not flip this row, got \(hOther)")
}

reporter.check("E4 RootHealth.uiLabel contains the right keyword per case") {
    let cases: [(RootHealth, String)] = [
        (.ready, "就绪"),
        (.indexing, "索引中"),
        (.paused, "停用"),
        (.offline, "未挂载"),
        (.unavailable, "不可访问"),
    ]
    for (h, needle) in cases {
        try reporter.require(h.uiLabel.contains(needle),
                             "uiLabel for \(h) missing keyword \(needle): \(h.uiLabel)")
    }
}

reporter.check("E4 RebuildCoordinator.indexOneRoot walks just one path and drives onStateChange") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    for f in ["a.txt", "b.txt"] {
        try "".write(to: root.appendingPathComponent(f), atomically: true, encoding: .utf8)
    }
    _ = try db.registerRoot(path: root.path)
    let coord = RebuildCoordinator(database: db)
    let lock = NSLock()
    nonisolated(unsafe) var states: [RebuildCoordinator.State] = []
    coord.onStateChange = { state in
        lock.lock()
        states.append(state)
        lock.unlock()
    }
    let done = DispatchSemaphore(value: 0)
    let ok = coord.indexOneRoot(path: root.path, onFinish: { _ in done.signal() })
    try reporter.require(ok, "indexOneRoot should accept when idle")
    _ = done.wait(timeout: .now() + 10)
    lock.lock()
    let captured = states
    lock.unlock()
    // Transitions: first .rebuilding (0/1), then .rebuilding (1/1), then .idle
    let hasIdle = captured.contains { if case .idle = $0 { return true }; return false }
    try reporter.require(hasIdle,
                         "should reach .idle after finishing: \(captured)")
    // Verify files got indexed via a search.
    let hits = try SearchEngine(database: db).search("a.txt")
    try reporter.require(!hits.isEmpty,
                         "indexOneRoot did not index files (search returned empty)")
}

reporter.check("E4 RebuildCoordinator.indexOneRoot serial queue: multiple drops all get indexed") {
    // E4 round 2 regression guard: simulates the SettingsWindowController
    // drag-in flow where N roots are added back-to-back and each one
    // should end up indexed, not just the last.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let parent = try makeTempDir()
    defer { cleanup(parent) }
    let fm = FileManager.default
    let rootA = parent.appendingPathComponent("rootA")
    let rootB = parent.appendingPathComponent("rootB")
    let rootC = parent.appendingPathComponent("rootC")
    for r in [rootA, rootB, rootC] {
        try fm.createDirectory(at: r, withIntermediateDirectories: true)
    }
    try "".write(to: rootA.appendingPathComponent("file-a.txt"), atomically: true, encoding: .utf8)
    try "".write(to: rootB.appendingPathComponent("file-b.txt"), atomically: true, encoding: .utf8)
    try "".write(to: rootC.appendingPathComponent("file-c.txt"), atomically: true, encoding: .utf8)
    _ = try db.registerRoot(path: rootA.path)
    _ = try db.registerRoot(path: rootB.path)
    _ = try db.registerRoot(path: rootC.path)
    let coord = RebuildCoordinator(database: db)

    // Serial queue drain: mimic the pendingAutoIndex FIFO from the UI.
    let todo = [rootA.path, rootB.path, rootC.path]
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var pending = todo
    func next() {
        guard !pending.isEmpty else { done.signal(); return }
        let p = pending.removeFirst()
        _ = coord.indexOneRoot(path: p, onFinish: { _ in next() })
    }
    next()
    _ = done.wait(timeout: .now() + 20)

    let engine = SearchEngine(database: db)
    let a = try engine.search("file-a")
    let b = try engine.search("file-b")
    let c = try engine.search("file-c")
    try reporter.require(!a.isEmpty, "rootA auto-index missed (file-a not searchable)")
    try reporter.require(!b.isEmpty, "rootB auto-index missed (file-b not searchable)")
    try reporter.require(!c.isEmpty, "rootC auto-index missed (file-c not searchable)")
}

reporter.check("E4 RebuildCoordinator.currentlyIndexingPath is nil when idle") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let coord = RebuildCoordinator(database: db)
    try reporter.require(coord.currentlyIndexingPath == nil,
                         "idle coordinator should report nil currentlyIndexingPath, got \(String(describing: coord.currentlyIndexingPath))")
}

// MARK: - E5 (hotkey customisation)

reporter.check("E5 HotkeyPresets: default is first entry and round-trips through preset(keyCode:modifiers:)") {
    let d = HotkeyPresets.default
    try reporter.require(!d.label.isEmpty, "default preset has empty label")
    let found = HotkeyPresets.preset(keyCode: d.keyCode, modifiers: d.modifiers)
    try reporter.require(found == d,
                         "preset() should round-trip the default, got \(String(describing: found))")
    try reporter.require(HotkeyPresets.preset(keyCode: 0, modifiers: 0) == nil,
                         "unknown combo should return nil, not silently map to something")
}

reporter.check("E5 HotkeyPresets: at least 3 presets and all share the Space virtual key") {
    try reporter.require(HotkeyPresets.all.count >= 3,
                         "expected >=3 presets, got \(HotkeyPresets.all.count)")
    let space: UInt32 = 49 // kVK_Space
    for p in HotkeyPresets.all {
        try reporter.require(p.keyCode == space,
                             "preset \(p.label) has non-Space keyCode \(p.keyCode)")
    }
}

reporter.check("E5 Database.getHotkey: fresh DB returns the default preset") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let (k, m) = try db.getHotkey()
    let d = HotkeyPresets.default
    try reporter.require(k == d.keyCode && m == d.modifiers,
                         "fresh DB should default to \(d.label), got (\(k), \(m))")
}

reporter.check("E5 Database.setHotkey / getHotkey: round-trip of every preset") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    for preset in HotkeyPresets.all {
        try db.setHotkey(keyCode: preset.keyCode, modifiers: preset.modifiers)
        let (k, m) = try db.getHotkey()
        try reporter.require(k == preset.keyCode && m == preset.modifiers,
                             "round-trip failed for \(preset.label): got (\(k), \(m))")
    }
}

reporter.check("E5 Database.getHotkey: malformed value falls back to default") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Hand-write a malformed value and verify getHotkey returns default
    // instead of crashing or returning garbage.
    try db.setSetting(SettingsKey.hotkeyKeyCode, value: "not-a-number")
    try db.setSetting(SettingsKey.hotkeyModifiers, value: "also-not")
    let (k, m) = try db.getHotkey()
    let d = HotkeyPresets.default
    try reporter.require(k == d.keyCode && m == d.modifiers,
                         "malformed hotkey should fall back to default, got (\(k), \(m))")
}

reporter.check("E3 end-to-end: kind:dir returns only directories") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("docs/notes"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("docs/b.txt"), atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("kind:dir")
    for h in hits {
        try reporter.require(h.isDir,
                             "non-dir leaked through kind:dir: \(h.path)")
    }
    try reporter.require(hits.count >= 2,
                         "expected at least 2 dirs (root + docs + docs/notes), got \(hits.count)")
}

// MARK: - F1 (search hot path performance)

reporter.check("F1 schema: fresh DB reaches current version and has file_bigrams table") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Schema version moves across tracks (F1→4, G3→5). Assert via
    // Schema.currentVersion so this test stays green across bumps.
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "expected \(Schema.currentVersion), got \(db.schemaVersion)")
    try reporter.require(try db.tableExists("file_bigrams"),
                         "file_bigrams table missing")
}

reporter.check("F1 Gram.bigrams: returns 2-grams for 2+ char input, empty for 1 char") {
    let b = Gram.bigrams(of: "alpha")
    try reporter.require(b == ["al", "lp", "ph", "ha"],
                         "bigrams(alpha) wrong: \(b.sorted())")
    try reporter.require(Gram.bigrams(of: "a").isEmpty,
                         "1-char input must yield no bigrams")
    let twoChar = Gram.bigrams(of: "ab")
    try reporter.require(twoChar == ["ab"],
                         "2-char input exactly one bigram: got \(twoChar)")
}

reporter.check("F1 Indexer populates file_bigrams when inserting files (fullpath mode)") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath) // G3: explicitly ask for file_bigrams
    let root = try makeTempDir()
    defer { cleanup(root) }
    try "".write(to: root.appendingPathComponent("alpha.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let count = try db.scalarInt("SELECT COUNT(*) FROM file_bigrams;") ?? 0
    try reporter.require(count > 0,
                         "file_bigrams empty after index (count=\(count))")
}

reporter.check("F1 v3 → v4 migration backfills file_bigrams for pre-existing rows") {
    // Build a v3-shaped DB with rows, then re-open through the regular
    // API so migrate() bumps to v4 and populates file_bigrams.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let dbURL = dbDir.appendingPathComponent("legacy-v3.sqlite3")
    // Step 1: open and migrate to v3 baseline, then force user_version
    // to 3 so the next open treats this as pre-F1.
    do {
        let db = try Database.open(at: dbURL)
        // Apply v1-v3 manually so we bypass the v4 trigger.
        try db.exec("""
        CREATE TABLE files (id INTEGER PRIMARY KEY, parent_id INTEGER,
          path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, name_lower TEXT NOT NULL,
          path_lower TEXT NOT NULL DEFAULT '',
          is_dir INTEGER NOT NULL, size INTEGER NOT NULL DEFAULT 0,
          mtime INTEGER NOT NULL DEFAULT 0, inode INTEGER, volume_id INTEGER);
        CREATE INDEX idx_files_name_lower ON files(name_lower);
        CREATE INDEX idx_files_parent ON files(parent_id);
        CREATE INDEX idx_files_path_lower ON files(path_lower);
        CREATE TABLE roots (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
          enabled INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE excludes (id INTEGER PRIMARY KEY, pattern TEXT NOT NULL UNIQUE);
        CREATE TABLE file_grams (file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
          gram TEXT NOT NULL, PRIMARY KEY(file_id, gram)) WITHOUT ROWID;
        CREATE INDEX idx_file_grams_gram ON file_grams(gram);
        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO files(path, path_lower, name, name_lower, is_dir)
          VALUES ('/legacy/Alpha.TXT', '/legacy/alpha.txt', 'Alpha.TXT', 'alpha.txt', 0);
        PRAGMA user_version=3;
        """)
        db.close()
    }
    // Step 2: reopen → migrate should jump 3 → 4 and call backfillFileBigrams.
    let db = try Database.open(at: dbURL)
    defer { db.close() }
    try db.migrate()
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "v3 → current migration did not land, got \(db.schemaVersion)")
    let bgCount = try db.scalarInt("SELECT COUNT(*) FROM file_bigrams;") ?? 0
    try reporter.require(bgCount > 0,
                         "bigrams not backfilled after migration (count=\(bgCount))")
    // G3 upgrade path: a v3 DB upgrading through v4 to current should
    // land at fullpath mode (to preserve existing capability).
    let mode = try db.getSetting(SettingsKey.indexMode)
    try reporter.require(mode == IndexMode.fullpath.rawValue,
                         "v3→current upgrade should default to fullpath mode (got \(String(describing: mode)))")
}

reporter.check("F1 2-char query goes through the bigram index path, not %LIKE% scan") {
    // Build a tiny fixture under a deterministic root name so path bigrams
    // don't leak unrelated hits. makeTempDir() appends a UUID whose hex
    // digits frequently include "ab" / other query fragments, so we need
    // our own name here.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let fm = FileManager.default
    let stableRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("f1-bigram-root-qz-\(Int(Date().timeIntervalSince1970))")
    try fm.createDirectory(at: stableRoot, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: stableRoot) }
    for f in ["zx-notes.txt", "yx-report.txt", "wx-log.txt"] {
        try "".write(to: stableRoot.appendingPathComponent(f),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(stableRoot)
    let engine = SearchEngine(database: db)
    // Query "zx" appears only in zx-notes.txt (no other file name or path
    // contains "zx" because the stable root is "f1-bigram-root-qz-<ts>").
    let hits = try engine.search("zx")
    let names = hits.map { $0.name }.sorted()
    try reporter.require(names == ["zx-notes.txt"],
                         "2-char 'zx' should return only zx-notes.txt, got \(names)")
}

reporter.check("F1 SearchEngine stmt cache: repeat query hits the cache") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    for i in 0..<20 {
        try "".write(to: root.appendingPathComponent("alpha\(i).txt"),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    _ = try engine.search("alpha")
    let missesAfterFirst = engine.stmtCacheMisses
    for _ in 0..<10 {
        _ = try engine.search("alpha")
    }
    try reporter.require(engine.stmtCacheMisses == missesAfterFirst,
                         "stmt cache did not absorb repeat queries: misses went from \(missesAfterFirst) to \(engine.stmtCacheMisses)")
    try reporter.require(engine.stmtCacheHits >= 10,
                         "stmt cache hits=\(engine.stmtCacheHits) after 10 repeats")
}

reporter.check("F1 Database roots cache: hits second call, invalidates on registerRoot") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    _ = try db.listRoots()                      // miss
    let missBase = db.rootsCacheMisses
    _ = try db.listRoots()                      // should hit
    _ = try db.listRoots()                      // should hit
    try reporter.require(db.rootsCacheMisses == missBase,
                         "second listRoots should not miss; misses went from \(missBase) to \(db.rootsCacheMisses)")
    try reporter.require(db.rootsCacheHits >= 2,
                         "expected >=2 cache hits, got \(db.rootsCacheHits)")
    // register bumps the miss counter next time through
    let someDir = try makeTempDir()
    defer { cleanup(someDir) }
    _ = try db.registerRoot(path: someDir.path)
    _ = try db.listRoots()                      // must miss (invalidated)
    try reporter.require(db.rootsCacheMisses == missBase + 1,
                         "registerRoot should invalidate roots cache")
}

reporter.check("F1 Database settings cache: invalidates on setSetting for same key") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // First read: misses (key absent → cached as nil).
    try reporter.require((try db.getSetting("k1")) == nil, "fresh key must be nil")
    // Second read: hits cache, still nil.
    try reporter.require((try db.getSetting("k1")) == nil, "cached-nil read broke")
    // Write then read: must see the new value, not stale nil.
    try db.setSetting("k1", value: "v1")
    let afterV1 = try db.getSetting("k1")
    try reporter.require(afterV1 == "v1",
                         "stale cache after setSetting: got \(String(describing: afterV1))")
    // Overwrite then read: new value again.
    try db.setSetting("k1", value: "v2")
    try reporter.require((try db.getSetting("k1")) == "v2",
                         "stale cache after overwrite")
}

// MARK: - F2 (real relevance + GUI/CLI limit parity)

reporter.check("F2 ranking matrix: baseline query 'alpha' over a standard fixture (fullpath mode)") {
    // Lock down the current scoring contract as a single regression
    // matrix. Every row asserts an exact expected post-E1/F1 score for a
    // specific `alpha` hit. Adjusting scoring rules requires updating
    // this matrix deliberately, not silently.
    // G3: this matrix assumes v4 fullpath semantics (plain `alpha` recalls
    // extras-with-alpha/README.md via path match). Explicit opt-in.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    for d in ["docs", "beta", "extras-with-alpha"] {
        try fm.createDirectory(at: root.appendingPathComponent(d),
                               withIntermediateDirectories: true)
    }
    for f in ["alpha.txt", "alphabet.txt",
              "docs/alpha-notes.md",
              "beta/alpha report.txt",
              "extras-with-alpha/README.md"] {
        try "".write(to: root.appendingPathComponent(f),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("alpha")
    var byName: [String: Int] = [:]
    for h in hits { byName[h.name] = h.score }

    // Each expectation is a (name, score) pair; include a per-row comment
    // so anyone reading the smoke output can reconstruct the bonus math.
    let expected: [(name: String, score: Int, why: String)] = [
        // alpha.txt: prefix(800)+basename(50)+boundary(30) = 880
        // (query "alpha" is a prefix of name "alpha.txt" but not an exact
        // match — that's why we use 800 not 1000, and why no segment bonus.)
        ("alpha.txt", 880, "prefix + basename + boundary"),
        // alphabet.txt: prefix(800)+basename(50)+boundary(30) = 880
        ("alphabet.txt", 880, "prefix + basename + boundary"),
        // alpha-notes.md: prefix(800)+basename(50)+boundary(30) = 880
        ("alpha-notes.md", 880, "prefix + basename + boundary"),
        // alpha report.txt: prefix(800)+basename(50)+boundary(30) = 880
        ("alpha report.txt", 880, "prefix + basename + boundary"),
        // README.md: path-only(200)+boundary(30) = 230 (alpha in extras-with-alpha)
        ("README.md", 230, "path-only + boundary"),
    ]
    for e in expected {
        guard let got = byName[e.name] else {
            try reporter.require(false, "missing \(e.name) in results")
            continue
        }
        try reporter.require(got == e.score,
                             "\(e.name) score=\(got) expected=\(e.score) (\(e.why))")
    }
}

reporter.check("F2 ranking matrix: multi-word AND bonuses stack as documented") {
    // Verify multi-token AND all-in-basename bonus (+100) lands on top
    // of per-token base+bonuses, matching the E1 contract.
    let nameBoth = "foo-bar.txt"
    let pathBoth = "/a/foo-bar.txt"
    let s = SearchEngine.scoreTokens(["foo", "bar"],
                                     nameLower: nameBoth,
                                     pathLower: pathBoth)
    // foo: prefix(800)+basename(50)+boundary(30) = 880
    // bar: contains(500)+basename(50)+boundary(30) = 580
    // both in name → +100
    // total = 1560
    try reporter.require(s == 1560,
                         "multi-token score=\(s) expected 1560")

    // Split: foo in name, bar in path only
    let s2 = SearchEngine.scoreTokens(["foo", "bar"],
                                      nameLower: "foo-report.txt",
                                      pathLower: "/a/bar/foo-report.txt")
    // foo: prefix(800)+basename(50)+boundary(30) = 880
    // bar: path-only(200)+segment(40)+boundary(30) = 270
    // not all-in-name, no +100
    // total = 1150
    try reporter.require(s2 == 1150,
                         "split-path multi-token score=\(s2) expected 1150")
    try reporter.require(s > s2,
                         "all-in-basename should outscore split: \(s) vs \(s2)")
}

reporter.check("F2 CLI default limit: uses DB's search_limit when --limit is omitted") {
    // Mirrors what SwiftSeekSearch/main.swift does when parsed.limitOverride is nil.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Fresh DB → default.
    let l0 = try db.getSearchLimit()
    try reporter.require(l0 == SearchLimitBounds.defaultValue,
                         "fresh DB CLI default should equal SearchLimitBounds.defaultValue (\(SearchLimitBounds.defaultValue)), got \(l0)")
    // Persisted change → CLI sees it.
    try db.setSearchLimit(250)
    let l1 = try db.getSearchLimit()
    try reporter.require(l1 == 250,
                         "persisted 250 should be CLI default, got \(l1)")
    // Explicit --limit still overrides at the caller level (simulate via
    // the pattern used in main.swift: if override nil, read from DB).
    let overrideValue: Int? = 7
    let effective = overrideValue ?? l1
    try reporter.require(effective == 7,
                         "explicit override should win over DB default")
}

reporter.check("F2 CLI default limit change is reflected in the very next search call") {
    // End-to-end: raising the limit in settings must make the engine
    // return more results on the next call. Previously the GUI cached
    // limit per run; F1 settings cache is invalidated on setSetting so
    // the new value is observed immediately.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    for i in 0..<30 {
        try "".write(to: root.appendingPathComponent("alpha-\(i).txt"),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    // Use values above SearchLimitBounds.minimum (20) so the clamp
    // doesn't swallow the intended change.
    try db.setSearchLimit(22)
    let fewLimit = try db.getSearchLimit()
    try reporter.require(fewLimit == 22,
                         "setSearchLimit(22) should round-trip, got \(fewLimit)")
    let few = try engine.search("alpha",
                                options: .init(limit: fewLimit))
    try reporter.require(few.count == 22,
                         "limit=22 should cap at 22 (got \(few.count))")
    try db.setSearchLimit(28)
    let manyLimit = try db.getSearchLimit()
    try reporter.require(manyLimit == 28,
                         "setSearchLimit(28) should round-trip, got \(manyLimit)")
    let many = try engine.search("alpha",
                                 options: .init(limit: manyLimit))
    try reporter.require(many.count == 28,
                         "limit=28 should cap at 28 (got \(many.count))")
}

// MARK: - F3 (result view density + sort persistence + column widths)

reporter.check("F3 sort order persistence: fresh DB returns scoreDescending") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let o = try db.getResultSortOrder()
    try reporter.require(o == .scoreDescending,
                         "fresh DB should default to scoreDescending, got \(o)")
}

reporter.check("F3 sort order persistence: round-trip every SearchSortKey") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let cases: [SearchSortOrder] = [
        .init(key: .score, ascending: false),
        .init(key: .score, ascending: true),
        .init(key: .name, ascending: true),
        .init(key: .name, ascending: false),
        .init(key: .path, ascending: true),
        .init(key: .mtime, ascending: false),
        .init(key: .size, ascending: true),
    ]
    for order in cases {
        try db.setResultSortOrder(order)
        let got = try db.getResultSortOrder()
        try reporter.require(got == order,
                             "round-trip failed for \(order): got \(got)")
    }
}

reporter.check("F3 sort order persistence: malformed or missing row falls back to scoreDescending") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Writing garbage directly via the raw settings API (bypassing the
    // typed wrapper) must not make the reader crash — it should treat
    // it as "no valid setting" and return the default.
    try db.setSetting(SettingsKey.resultSortKey, value: "bogus-key")
    try db.setSetting(SettingsKey.resultSortAscending, value: "not-a-bool")
    let got = try db.getResultSortOrder()
    try reporter.require(got == .scoreDescending,
                         "malformed rows should fall back to scoreDescending, got \(got)")
}

reporter.check("F3 column width persistence: missing = nil, round-trip per key") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let keys = [
        SettingsKey.resultColumnWidthName,
        SettingsKey.resultColumnWidthPath,
        SettingsKey.resultColumnWidthMtime,
        SettingsKey.resultColumnWidthSize,
    ]
    for k in keys {
        try reporter.require((try db.getResultColumnWidth(key: k)) == nil,
                             "fresh DB should return nil for \(k)")
    }
    for (i, k) in keys.enumerated() {
        let w = Double(100 + i * 50)
        try db.setResultColumnWidth(key: k, width: w)
        let got = try db.getResultColumnWidth(key: k) ?? -1
        try reporter.require(got == w,
                             "round-trip failed for \(k): \(got) vs \(w)")
    }
}

// MARK: - F4 (DSL path:/root:/hidden: + RootHealth surfacing)

reporter.check("F4 path:-only filter-only query returns the right files (uses gram path, not bounded scan)") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("notes-dir"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("other"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("notes-dir/a.txt"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("notes-dir/b.txt"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("other/c.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("path:notes-dir")
    let names = Set(hits.map { $0.name })
    // Must include both files under notes-dir/ plus the notes-dir
    // directory itself.
    try reporter.require(names.contains("a.txt"),
                         "a.txt missing: \(names)")
    try reporter.require(names.contains("b.txt"),
                         "b.txt missing: \(names)")
    // Must NOT include the other subtree.
    try reporter.require(!names.contains("c.txt"),
                         "c.txt leaked through path: filter: \(names)")
}

reporter.check("F4 path:-only + ext: combination applies both filters") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("notes-dir"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("notes-dir/a.md"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("notes-dir/b.txt"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("other.md"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("path:notes-dir ext:md")
    let names = Set(hits.map { $0.name })
    try reporter.require(names == ["a.md"],
                         "expected only a.md, got \(names)")
}

reporter.check("F4 ext:-only filter candidate path stays under 200ms on a 1k fixture (linear scan acceptable)") {
    // Codex F4 round 1 flagged that we had overclaimed ext: as
    // "B-tree indexable" — the leading '%' means SQLite falls back to
    // a linear scan. This smoke is the concrete evidence that even
    // as a linear scan, the ext: hot path is well under the 200ms
    // "high-frequency scenario" ceiling we document.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    var rows: [FileRow] = []
    for i in 0..<1000 {
        let ext = (i % 3 == 0) ? "md" : ((i % 3 == 1) ? "txt" : "swift")
        let name = "note-\(i).\(ext)"
        let path = "\(root.path)/\(name)"
        rows.append(FileRow(
            path: path,
            pathLower: path.lowercased(),
            name: name,
            nameLower: name.lowercased(),
            isDir: false,
            size: Int64(10 * i),
            mtime: Int64(1_700_000_000 + i)
        ))
    }
    try db.insertFiles(rows)
    _ = try db.registerRoot(path: root.path)
    let engine = SearchEngine(database: db)
    // Warm the stmt cache.
    _ = try engine.search("ext:md")
    _ = try engine.search("ext:md")
    // Measure median of 11 runs.
    var samples: [Double] = []
    for _ in 0..<11 {
        let t0 = Date()
        _ = try engine.search("ext:md")
        samples.append(Date().timeIntervalSince(t0) * 1000)
    }
    samples.sort()
    let median = samples[samples.count / 2]
    try reporter.require(median < 200,
                         "ext:md median \(median)ms exceeded 200ms ceiling (regression?)")
}

reporter.check("F4 RootHealth surfaces in the empty-state suffix logic (via computeRootHealth)") {
    // We can't render the actual AppKit label from smoke, but the
    // key contract is that computeRootHealth classifies offline and
    // unavailable roots correctly. Smoke already covers all 5 states
    // individually in F4 of the previous stage set (E4); here we
    // verify the SearchViewController-style summary that F4 adds:
    // a roots list with a mix of healthy + degraded produces at
    // least one degraded flag. This is a pure helper test so the
    // UI layer only has to handle display.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let goodRoot = try makeTempDir()
    defer { cleanup(goodRoot) }
    let ghost = "/private/var/tmp/f4-offline-\(UUID().uuidString)"
    _ = try db.registerRoot(path: goodRoot.path)
    _ = try db.registerRoot(path: ghost)
    let rows = try db.listRoots()
    var statuses: [RootHealth] = []
    for r in rows {
        statuses.append(db.computeRootHealth(for: r))
    }
    try reporter.require(statuses.contains(.ready),
                         "expected at least one .ready, got \(statuses)")
    try reporter.require(statuses.contains(.offline),
                         "expected at least one .offline (ghost path), got \(statuses)")
}

reporter.check("F1 warm 2-char search timing under generous CI bound (200ms median)") {
    // Looser than the documented 50ms target so this smoke test remains
    // reliable across sandbox / slow CI / debug build conditions. The
    // documented tight target is enforced by SwiftSeekBench --enforce-targets.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    // ~500 files — small enough that the DB-insert loop doesn't dominate
    // the smoke run, large enough that a %LIKE% regression is visible.
    var rows: [FileRow] = []
    for i in 0..<500 {
        let name = "alpha-\(i).txt"
        let path = "\(root.path)/\(name)"
        rows.append(FileRow(
            path: path,
            pathLower: path.lowercased(),
            name: name,
            nameLower: name.lowercased(),
            isDir: false,
            size: 0,
            mtime: 0
        ))
    }
    try db.insertFiles(rows)
    _ = try db.registerRoot(path: root.path)
    let engine = SearchEngine(database: db)
    _ = try engine.search("al")      // warm
    _ = try engine.search("al")      // warm
    var samples: [Double] = []
    for _ in 0..<21 {
        let t0 = Date()
        _ = try engine.search("al")
        samples.append(Date().timeIntervalSince(t0) * 1000)
    }
    samples.sort()
    let median = samples[samples.count / 2]
    try reporter.require(median < 200,
                         "2-char median \(median)ms exceeded 200ms ceiling (regression?)")
}

// MARK: - G1 (DB footprint observability + maintenance entries)

reporter.check("G1 computeStats on fresh DB: known tables all row-count=0, no crash") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let s = db.computeStats()
    try reporter.require(s.filesRowCount == 0,
                         "fresh files should be 0, got \(s.filesRowCount)")
    try reporter.require(s.fileGramsRowCount == 0,
                         "fresh file_grams should be 0, got \(s.fileGramsRowCount)")
    try reporter.require(s.fileBigramsRowCount == 0,
                         "fresh file_bigrams should be 0, got \(s.fileBigramsRowCount)")
    try reporter.require(s.rootsRowCount == 0, "fresh roots should be 0")
    try reporter.require(s.excludesRowCount == 0, "fresh excludes should be 0")
    // G3+: the v5 migration seeds settings(index_mode), so a "fresh" DB
    // now has at least that row. Assert on "no user-driven settings"
    // rather than raw count so a future seeded default doesn't break this.
    try reporter.require(s.settingsRowCount >= 0, "settings row count readable")
    try reporter.require(s.settingsRowCount <= 2,
                         "fresh DB should have at most schema-seeded settings, got \(s.settingsRowCount)")
    try reporter.require(s.pageCount > 0, "page_count should be positive")
    try reporter.require(s.pageSize > 0, "page_size should be positive")
    try reporter.require(s.mainFileBytes > 0, "main file should exist")
    try reporter.require(s.avgGramsPerFile == nil, "avg grams should be nil when files=0")
    try reporter.require(s.avgBigramsPerFile == nil, "avg bigrams should be nil when files=0")
}

reporter.check("G1 computeStats averages: per-file grams/bigrams match row counts (fullpath mode)") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath) // G3: exercise the file_grams/file_bigrams path explicitly
    let root = try makeTempDir()
    defer { cleanup(root) }
    for f in ["alpha.txt", "beta.md", "gamma.swift"] {
        try "".write(to: root.appendingPathComponent(f),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let s = db.computeStats()
    try reporter.require(s.filesRowCount > 0,
                         "files should be >0 after index")
    try reporter.require(s.fileGramsRowCount > 0, "grams should be >0")
    try reporter.require(s.fileBigramsRowCount > 0, "bigrams should be >0")
    let expectedAvgG = Double(s.fileGramsRowCount) / Double(s.filesRowCount)
    let expectedAvgB = Double(s.fileBigramsRowCount) / Double(s.filesRowCount)
    try reporter.require(s.avgGramsPerFile == expectedAvgG,
                         "avgGrams mismatch: \(String(describing: s.avgGramsPerFile)) vs \(expectedAvgG)")
    try reporter.require(s.avgBigramsPerFile == expectedAvgB,
                         "avgBigrams mismatch: \(String(describing: s.avgBigramsPerFile)) vs \(expectedAvgB)")
}

reporter.check("G1 computeStats: WAL / SHM byte fields present and sane") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Writing a row forces a WAL file to appear.
    _ = try db.registerRoot(path: "/tmp/\(UUID().uuidString)")
    let s = db.computeStats()
    // WAL path either exists with a size, or is -1 (not present yet on
    // some platforms). Both are acceptable — the important property is
    // that the call does not crash and returns a valid Int64.
    try reporter.require(s.walFileBytes >= -1,
                         "walFileBytes must be -1 or non-negative, got \(s.walFileBytes)")
    try reporter.require(s.shmFileBytes >= -1,
                         "shmFileBytes must be -1 or non-negative, got \(s.shmFileBytes)")
}

reporter.check("G1 computeStats: missing-table fallback returns -1 instead of crashing") {
    // Simulate a partially-broken DB (v3 schema without file_bigrams).
    // We can't easily drop the table mid-flight; instead, build a new
    // DB manually at v3 and confirm computeStats handles the missing
    // file_bigrams table gracefully.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let dbURL = dbDir.appendingPathComponent("partial.sqlite3")
    do {
        let db = try Database.open(at: dbURL)
        try db.exec("""
        CREATE TABLE files (id INTEGER PRIMARY KEY, parent_id INTEGER,
          path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
          name_lower TEXT NOT NULL, path_lower TEXT NOT NULL DEFAULT '',
          is_dir INTEGER NOT NULL, size INTEGER NOT NULL DEFAULT 0,
          mtime INTEGER NOT NULL DEFAULT 0, inode INTEGER, volume_id INTEGER);
        CREATE TABLE roots (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
          enabled INTEGER NOT NULL DEFAULT 1);
        PRAGMA user_version=3;
        """)
        db.close()
    }
    // Open raw (no migrate) so file_bigrams never gets created.
    let db = try Database.open(at: dbURL)
    defer { db.close() }
    let s = db.computeStats()
    try reporter.require(s.fileBigramsRowCount == -1,
                         "missing file_bigrams should return -1, got \(s.fileBigramsRowCount)")
    try reporter.require(s.filesRowCount == 0,
                         "existing files table should still be countable")
    try reporter.require(s.excludesRowCount == -1,
                         "missing excludes table should return -1")
    try reporter.require(s.settingsRowCount == -1,
                         "missing settings table should return -1")
}

reporter.check("G1 runMaintenance: checkpoint / optimize succeed on fresh DB") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let r1 = db.runMaintenance(.checkpoint)
    try reporter.require(r1.error == nil,
                         "checkpoint should succeed, got \(r1.error ?? "?")")
    let r2 = db.runMaintenance(.optimize)
    try reporter.require(r2.error == nil,
                         "optimize should succeed, got \(r2.error ?? "?")")
}

reporter.check("G1 runMaintenance: vacuum succeeds on a small DB (core path)") {
    // Verifies that the Core-level VACUUM helper works. The UI-layer
    // confirmation dialog is covered by manual test 33f.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    try "".write(to: root.appendingPathComponent("a.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let r = db.runMaintenance(.vacuum)
    try reporter.require(r.error == nil,
                         "vacuum on small DB should succeed, got \(r.error ?? "?")")
}

reporter.check("G1 humanBytes / humanCount / humanAvg render — for missing values") {
    try reporter.require(DatabaseStats.humanBytes(-1) == "—",
                         "humanBytes(-1) should be '—'")
    try reporter.require(DatabaseStats.humanCount(-1) == "—",
                         "humanCount(-1) should be '—'")
    try reporter.require(DatabaseStats.humanAvg(nil) == "—",
                         "humanAvg(nil) should be '—'")
    // Real values render reasonably.
    try reporter.require(DatabaseStats.humanBytes(1024 * 1024).contains("MB")
                         || DatabaseStats.humanBytes(1024 * 1024).contains("KB"),
                         "1 MB should produce MB-ish string")
    try reporter.require(DatabaseStats.humanAvg(3.141) == "3.14",
                         "humanAvg(3.141) should be '3.14'")
}

// MARK: - G3 (schema v5 + compact index + MigrationCoordinator)

reporter.check("G3 schema v5: fresh DB has compact tables + migration_progress") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // H1 bumped currentVersion to 6; G3's compact tables still exist
    // from v5 — we just need a DB that's migrated past v5.
    try reporter.require(db.schemaVersion >= 5,
                         "fresh DB should be at least v5, got \(db.schemaVersion)")
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "fresh DB should reach currentVersion \(Schema.currentVersion), got \(db.schemaVersion)")
    for table in ["file_name_grams", "file_name_bigrams", "file_path_segments", "migration_progress"] {
        try reporter.require(try db.tableExists(table),
                             "\(table) missing after v5 migration")
    }
}

reporter.check("G3 index mode: fresh DB default = compact, v4 upgrade default = fullpath") {
    // fresh
    let freshDir = try makeTempDir()
    defer { cleanup(freshDir) }
    do {
        let paths = try AppPaths.ensureSupportDirectory(override: freshDir)
        let db = try Database.open(at: paths.databaseURL)
        defer { db.close() }
        try db.migrate()
        try reporter.require(try db.getIndexMode() == .compact,
                             "fresh DB should default to compact")
    }
    // Pre-existing v4 DB
    let v4Dir = try makeTempDir()
    defer { cleanup(v4Dir) }
    let v4URL = v4Dir.appendingPathComponent("legacy-v4.sqlite3")
    do {
        let db = try Database.open(at: v4URL)
        // Build a minimal v4-shaped schema and stamp user_version=4.
        try db.exec("""
        CREATE TABLE files (id INTEGER PRIMARY KEY, parent_id INTEGER,
          path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
          name_lower TEXT NOT NULL, path_lower TEXT NOT NULL DEFAULT '',
          is_dir INTEGER NOT NULL, size INTEGER NOT NULL DEFAULT 0,
          mtime INTEGER NOT NULL DEFAULT 0, inode INTEGER, volume_id INTEGER);
        CREATE TABLE roots (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
          enabled INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE excludes (id INTEGER PRIMARY KEY, pattern TEXT NOT NULL UNIQUE);
        CREATE TABLE file_grams (file_id INTEGER, gram TEXT, PRIMARY KEY(file_id, gram)) WITHOUT ROWID;
        CREATE TABLE file_bigrams (file_id INTEGER, gram TEXT, PRIMARY KEY(file_id, gram)) WITHOUT ROWID;
        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        PRAGMA user_version=4;
        """)
        db.close()
    }
    let db = try Database.open(at: v4URL)
    defer { db.close() }
    try db.migrate()
    try reporter.require(db.schemaVersion == Schema.currentVersion,
                         "v4 upgrade should reach currentVersion \(Schema.currentVersion), got \(db.schemaVersion)")
    let upgradedMode = try db.getIndexMode()
    try reporter.require(upgradedMode == .fullpath,
                         "v4 upgrade should default to fullpath, got \(upgradedMode)")
}

reporter.check("G3 compact indexer: writes name-grams + path-segments, not file_grams/file_bigrams") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Fresh DB → compact by default; index a small tree.
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("docs"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("alpha.md"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("docs/beta.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)

    let nameGrams = try db.countRows(in: "file_name_grams")
    let nameBigrams = try db.countRows(in: "file_name_bigrams")
    let pathSegs = try db.countRows(in: "file_path_segments")
    let oldGrams = try db.countRows(in: "file_grams")
    let oldBigrams = try db.countRows(in: "file_bigrams")

    try reporter.require(nameGrams > 0, "compact name_grams not populated")
    try reporter.require(nameBigrams > 0, "compact name_bigrams not populated")
    try reporter.require(pathSegs > 0, "compact path_segments not populated")
    try reporter.require(oldGrams == 0,
                         "compact mode leaked into file_grams (count=\(oldGrams))")
    try reporter.require(oldBigrams == 0,
                         "compact mode leaked into file_bigrams (count=\(oldBigrams))")
}

reporter.check("G3 search compact: plain query 'alpha' hits basename, not path-substring") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    // Layout matches proposal §5.1 negative example:
    //   /ROOT/myproj-old/a.txt  — plain "myproj" must NOT hit this file
    //   /ROOT/alpha.md          — plain "alpha" must hit via basename
    try fm.createDirectory(at: root.appendingPathComponent("myproj-old"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("alpha.md"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("myproj-old/a.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let alphaHits = try engine.search("alpha")
    try reporter.require(alphaHits.contains(where: { $0.name == "alpha.md" }),
                         "basename 'alpha' hit missing: \(alphaHits.map(\.name))")
    let myprojHits = try engine.search("myproj")
    try reporter.require(!myprojHits.contains(where: { $0.name == "a.txt" }),
                         "path substring 'myproj' leaked into compact results: \(myprojHits.map(\.name))")
}

reporter.check("G3 search compact: path:<token> does segment-prefix match, not substring") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("docs"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("docs-old"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("docs/a.txt"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("docs-old/b.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    // path:doc is a prefix of both segment "docs" and "docs-old"; expect both.
    let doc = try engine.search("path:doc")
    try reporter.require(doc.contains(where: { $0.name == "a.txt" }),
                         "path:doc missed a.txt: \(doc.map(\.path))")
    try reporter.require(doc.contains(where: { $0.name == "b.txt" }),
                         "path:doc missed b.txt: \(doc.map(\.path))")
    // path:oj must NOT hit anything (not a segment prefix; compact refuses
    // segment-internal substring matches, see proposal §5.1 negative ex 2).
    let oj = try engine.search("path:oj")
    try reporter.require(!oj.contains(where: { $0.name == "b.txt" }),
                         "path:oj leaked into compact results: \(oj.map(\.path))")
}

reporter.check("G3 MigrationCoordinator: incremental backfill + resume after partial run") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Build a fullpath-indexed fixture to simulate an existing v4 DB user.
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    for i in 0..<12 {
        try "".write(to: root.appendingPathComponent("file-\(i).txt"),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    // Switch to compact: at this point file_name_grams etc are still empty.
    try db.setIndexMode(.compact)
    let pre = try db.countRows(in: "file_name_grams")
    try reporter.require(pre == 0,
                         "file_name_grams should be empty before backfill, got \(pre)")
    // Run coordinator with small batch so we can observe partial progress.
    let coord = MigrationCoordinator(database: db)
    coord.batchSize = 5
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var progressCount = 0
    let kicked = coord.backfillCompact(resume: true,
                                       onProgress: { _ in progressCount += 1 },
                                       onFinish: { _ in done.signal() })
    try reporter.require(kicked, "backfillCompact refused to start")
    _ = done.wait(timeout: .now() + 30)
    let afterGrams = try db.countRows(in: "file_name_grams")
    try reporter.require(afterGrams > 0,
                         "backfill did not write file_name_grams")
    try reporter.require(progressCount >= 1,
                         "progress callback never fired (got \(progressCount))")
    // Verify search works under compact after backfill.
    let engine = SearchEngine(database: db)
    let hits = try engine.search("file-7")
    try reporter.require(hits.contains(where: { $0.name == "file-7.txt" }),
                         "compact search after backfill missed file-7.txt")
}

reporter.check("G3 search compact: multiple path: tokens may satisfy the same segment (AND over tokens, not segments)") {
    // Round-2 regression: earlier HAVING COUNT(DISTINCT segment)
    // required different segments, so `path:doc path:docs` returned
    // zero on a file whose only path segment was "docs". G2 contract
    // (proposal §5.1 "each token must match some segment, multiple
    // tokens can share a segment") demands both tokens be satisfied
    // by the single segment "docs".
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("docs"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("docs/a.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("path:doc path:docs")
    try reporter.require(hits.contains(where: { $0.name == "a.txt" }),
                         "both path tokens should be satisfied by segment 'docs'; got \(hits.map(\.path))")
}

reporter.check("G3 MigrationCoordinator: concurrent call returns false (state flip atomic with idle check)") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    // Enough files to keep the backfill busy long enough for the
    // second call to race it, mirroring P5 concurrent rebuild test.
    for i in 0..<500 {
        try "".write(to: root.appendingPathComponent("file-with-a-reasonably-long-name-\(i).txt"),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    try db.setIndexMode(.compact)
    let coord = MigrationCoordinator(database: db)
    coord.batchSize = 50
    let first = coord.backfillCompact()
    try reporter.require(first, "first backfill did not start")
    // Second call must be rejected even when fired immediately, before
    // the worker queue actually picked up the closure.
    let second = coord.backfillCompact()
    try reporter.require(!second,
                         "concurrent second backfill should return false")
    // Let it drain so we don't leak a running coordinator.
    let deadline = Date().addingTimeInterval(20)
    while coord.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
    try reporter.require(!coord.isRunning,
                         "coordinator did not return to idle within 20s")
}

reporter.check("G3 MigrationCoordinator: last_file_id persisted to migration_progress") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    for i in 0..<6 {
        try "".write(to: root.appendingPathComponent("a-\(i).txt"),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    try db.setIndexMode(.compact)
    let coord = MigrationCoordinator(database: db)
    let done = DispatchSemaphore(value: 0)
    _ = coord.backfillCompact(onFinish: { _ in done.signal() })
    _ = done.wait(timeout: .now() + 10)
    let lastId = coord.readLastFileId()
    try reporter.require(lastId > 0,
                         "migration_progress last_file_id should be > 0, got \(lastId)")
}

// MARK: - G4 (index mode UI + rebuild flow)

reporter.check("G4 index mode setting: compact / fullpath round-trip") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let m1 = try db.getIndexMode()
    try reporter.require(m1 == .fullpath, "fullpath not persisted, got \(m1)")
    try db.setIndexMode(.compact)
    let m2 = try db.getIndexMode()
    try reporter.require(m2 == .compact, "compact not persisted, got \(m2)")
}

reporter.check("G4 compact → fullpath switch after backfill reveals v4 data immediately") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Start as fullpath so v4 tables get written.
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("myproj-old"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("myproj-old/a.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    // Pre-switch: fullpath mode should let plain 'myproj' hit a.txt via path substring.
    let fullpathHits = try engine.search("myproj")
    try reporter.require(fullpathHits.contains(where: { $0.name == "a.txt" }),
                         "fullpath search should hit a.txt via path substring, got \(fullpathHits.map(\.path))")
    // Switch to compact: v4 tables untouched; compact tables empty.
    // Engine should respect mode immediately; plain 'myproj' now misses.
    try db.setIndexMode(.compact)
    let compactHits = try engine.search("myproj")
    try reporter.require(!compactHits.contains(where: { $0.name == "a.txt" }),
                         "compact mode must not leak path substring hits, got \(compactHits.map(\.path))")
    // Switch back to fullpath: hit returns immediately because v4 tables
    // were preserved.
    try db.setIndexMode(.fullpath)
    let hitsAgain = try engine.search("myproj")
    try reporter.require(hitsAgain.contains(where: { $0.name == "a.txt" }),
                         "switching back to fullpath should restore the hit without rebuild")
}

reporter.check("G4 mode switch does not leak pre-switch candidate cache") {
    // If SearchEngine stmtCache held a mode-specific SQL across a
    // mode change, results could be wrong. We don't actually clear
    // the cache on mode change because each mode's query text is
    // distinct (different table names) — so cache entries stay valid
    // per-mode. Verify by switching back and forth and confirming
    // distinct results are consistent.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    try "".write(to: root.appendingPathComponent("hello.txt"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    _ = try engine.search("hello")             // populate stmt cache fullpath branch
    try db.setIndexMode(.compact)
    let hits = try engine.search("hello")      // compact branch fires; stmt cache miss for new SQL
    // Compact name index is empty here (we indexed under fullpath),
    // so we expect 0 results — proving the engine actually consulted
    // the compact tables, not cached fullpath candidates.
    try reporter.require(hits.isEmpty,
                         "compact should return [] when compact tables empty; got \(hits.map(\.name))")
}

// MARK: - H1 usage data model + recordOpen

// Helper: fresh DB + single indexed file; returns (db, fileId, path).
// Wraps the "open/migrate/insert/lookupFileId" dance so the H1 tests
// only talk about the usage behavior they actually exercise.
func makeH1Fixture() throws -> (Database, Int64, String, URL) {
    let dbDir = try makeTempDir()
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    try db.migrate()
    let filesRoot = try makeTempDir()
    let filePath = filesRoot.appendingPathComponent("demo.txt").path
    try "".write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
    let row = FileRow(path: filePath,
                      pathLower: filePath.lowercased(),
                      name: "demo.txt",
                      nameLower: "demo.txt",
                      isDir: false,
                      size: 0,
                      mtime: 0)
    try db.insertFiles([row])
    guard let fileId = try db.lookupFileId(path: filePath) else {
        throw SmokeFailure(message: "H1 fixture: lookupFileId returned nil right after insert")
    }
    return (db, fileId, filePath, dbDir)
}

reporter.check("H1 schema v6 has file_usage table") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // J4 bumped currentVersion to 7; H1 just needs file_usage to exist.
    try reporter.require(Schema.currentVersion >= 6,
                         "Schema.currentVersion should be >= 6 for H1, got \(Schema.currentVersion)")
    try reporter.require(try db.tableExists("file_usage"),
                         "file_usage table missing after v6+ migrate")
    // Initial state: no usage rows on a fresh DB with no .open yet.
    let count = try db.countRows(in: "file_usage")
    try reporter.require(count == 0,
                         "fresh DB should have 0 file_usage rows, got \(count)")
}

reporter.check("H1 getUsageByPath returns nil before any recordOpen") {
    let (db, _, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    let pre = try db.getUsageByPath(path)
    try reporter.require(pre == nil,
                         "usage row should not exist before first recordOpen, got \(String(describing: pre))")
}

reporter.check("H1 recordOpen(path:) first call creates row with open_count=1") {
    let (db, fileId, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    let ok = try db.recordOpen(path: path, now: 1_700_000_000)
    try reporter.require(ok, "recordOpen should return true for indexed path")
    guard let row = try db.getUsageByPath(path) else {
        throw SmokeFailure(message: "usage row missing after first recordOpen")
    }
    try reporter.require(row.fileId == fileId, "fileId mismatch: \(row.fileId) vs \(fileId)")
    try reporter.require(row.openCount == 1, "open_count should be 1, got \(row.openCount)")
    try reporter.require(row.lastOpenedAt == 1_700_000_000,
                         "last_opened_at should be 1_700_000_000, got \(row.lastOpenedAt)")
    try reporter.require(row.updatedAt == 1_700_000_000,
                         "updated_at should be 1_700_000_000, got \(row.updatedAt)")
}

reporter.check("H1 recordOpen repeated accumulates open_count and updates timestamps") {
    let (db, _, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    _ = try db.recordOpen(path: path, now: 1_700_000_000)
    _ = try db.recordOpen(path: path, now: 1_700_000_050)
    _ = try db.recordOpen(path: path, now: 1_700_000_100)
    guard let row = try db.getUsageByPath(path) else {
        throw SmokeFailure(message: "usage row missing after repeated recordOpen")
    }
    try reporter.require(row.openCount == 3, "open_count should be 3, got \(row.openCount)")
    try reporter.require(row.lastOpenedAt == 1_700_000_100,
                         "last_opened_at should track most recent, got \(row.lastOpenedAt)")
    try reporter.require(row.updatedAt == 1_700_000_100,
                         "updated_at should track most recent, got \(row.updatedAt)")
}

reporter.check("H1 recordOpen on unknown path returns false and does not write") {
    let (db, _, _, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    let bogus = "/tmp/definitely-not-indexed-\(UUID().uuidString).txt"
    let ok = try db.recordOpen(path: bogus, now: 1_700_000_000)
    try reporter.require(!ok, "recordOpen should return false for unknown path")
    let count = try db.countRows(in: "file_usage")
    try reporter.require(count == 0,
                         "recordOpen on unknown path must not write; got \(count) rows")
}

reporter.check("H1 usage row cascades on files row delete") {
    let (db, fileId, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    _ = try db.recordOpen(path: path, now: 1_700_000_000)
    try reporter.require(try db.getUsageByFileId(fileId) != nil,
                         "usage row should exist before file delete")
    let removed = try db.deleteFiles(atOrUnderPath: path)
    try reporter.require(removed == 1, "expected 1 file removed, got \(removed)")
    // FOREIGN KEY ON DELETE CASCADE is enabled at Database.open via
    // PRAGMA foreign_keys=ON; the usage row should be gone.
    try reporter.require(try db.getUsageByFileId(fileId) == nil,
                         "usage row should be cascaded away after files row delete")
    let count = try db.countRows(in: "file_usage")
    try reporter.require(count == 0,
                         "file_usage should be empty after cascade, got \(count)")
}

// MARK: - H2 usage-based ranking + result columns

// Helper: build a DB under compact mode with two files so H2 tests can
// exercise the same-score tie-break path end-to-end (engine, not unit).
func makeH2EngineFixture() throws -> (Database, Indexer, SearchEngine, URL, URL) {
    let dbDir = try makeTempDir()
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    try db.migrate()
    let root = try makeTempDir()
    // Identical basenames so scoreTokens produces the same score for
    // both. Different parent directories so paths are distinct.
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("dir-a"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("dir-b"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("dir-a/same-name-file.txt"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("dir-b/same-name-file.txt"),
                 atomically: true, encoding: .utf8)
    let indexer = Indexer(database: db)
    _ = try indexer.indexRoot(root)
    let engine = SearchEngine(database: db)
    return (db, indexer, engine, dbDir, root)
}

reporter.check("H2 SearchResult carries openCount / lastOpenedAt from LEFT JOIN file_usage") {
    let (db, _, engine, dbDir, root) = try makeH2EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // Before any recordOpen, both hits should have openCount=0 / lastOpenedAt=0.
    var hits = try engine.search("same-name-file")
    try reporter.require(hits.count >= 2, "expected 2 hits pre-usage, got \(hits.count)")
    for h in hits {
        try reporter.require(h.openCount == 0,
                             "fresh DB should have openCount 0, got \(h.openCount) on \(h.path)")
        try reporter.require(h.lastOpenedAt == 0,
                             "fresh DB should have lastOpenedAt 0, got \(h.lastOpenedAt) on \(h.path)")
    }
    // Open one of them twice and confirm JOIN surfaces the counts.
    let target = hits[0].path
    _ = try db.recordOpen(path: target, now: 1_700_000_000)
    _ = try db.recordOpen(path: target, now: 1_700_000_100)
    hits = try engine.search("same-name-file")
    guard let updated = hits.first(where: { $0.path == target }) else {
        throw SmokeFailure(message: "previously-opened path missing from second query: \(target)")
    }
    try reporter.require(updated.openCount == 2,
                         "openCount should be 2 after two recordOpens, got \(updated.openCount)")
    try reporter.require(updated.lastOpenedAt == 1_700_000_100,
                         "lastOpenedAt should be the last timestamp 1_700_000_100, got \(updated.lastOpenedAt)")
}

reporter.check("H2 same-score tie-break: higher openCount comes first") {
    let (db, _, engine, dbDir, root) = try makeH2EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // Pre-usage ordering is determined by the short-path/alpha tie-break.
    let preHits = try engine.search("same-name-file")
    try reporter.require(preHits.count >= 2, "expected 2 preHits, got \(preHits.count)")
    try reporter.require(preHits[0].score == preHits[1].score,
                         "expected identical basenames to score identically: \(preHits[0].score) vs \(preHits[1].score)")
    let first = preHits[0].path
    let second = preHits[1].path
    // Give the second hit more opens — it should leapfrog to the top.
    _ = try db.recordOpen(path: second, now: 1_700_000_000)
    _ = try db.recordOpen(path: second, now: 1_700_000_010)
    _ = try db.recordOpen(path: second, now: 1_700_000_020)
    let postHits = try engine.search("same-name-file")
    try reporter.require(postHits[0].path == second,
                         "higher-usage file should lead: got \(postHits[0].path), expected \(second)")
    try reporter.require(postHits[1].path == first,
                         "lower-usage file should follow: got \(postHits[1].path), expected \(first)")
    try reporter.require(postHits[0].score == postHits[1].score,
                         "tie-break is a SAME-score reordering, not a score change: \(postHits[0].score) vs \(postHits[1].score)")
}

reporter.check("H2 tie-break: equal openCount, higher lastOpenedAt wins") {
    let (db, _, engine, dbDir, root) = try makeH2EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    let preHits = try engine.search("same-name-file")
    let first = preHits[0].path
    let second = preHits[1].path
    // Equal openCount (1 each), but `second` opened later.
    _ = try db.recordOpen(path: first,  now: 1_700_000_000)
    _ = try db.recordOpen(path: second, now: 1_700_000_500)
    let hits = try engine.search("same-name-file")
    try reporter.require(hits[0].path == second,
                         "more recent usage should lead on equal openCount: got \(hits[0].path)")
    try reporter.require(hits[0].openCount == hits[1].openCount,
                         "openCount should stay equal: \(hits[0].openCount) vs \(hits[1].openCount)")
}

reporter.check("H2 low-score + high-usage does NOT beat high-score + zero-usage") {
    // Build two results by hand so the score differs. Usage tie-break
    // must not apply across the score boundary — this is the core
    // "不让高 usage 压过高相关" contract from the taskbook.
    let hiScore = SearchResult(path: "/a/hello.txt", name: "hello.txt",
                               isDir: false, size: 0, mtime: 0,
                               score: 1000, openCount: 0, lastOpenedAt: 0)
    let loScore = SearchResult(path: "/b/world.txt", name: "world.txt",
                               isDir: false, size: 0, mtime: 0,
                               score: 500, openCount: 999, lastOpenedAt: 9_999_999_999)
    let sorted = SearchEngine.sort([loScore, hiScore], by: .scoreDescending)
    try reporter.require(sorted.first == hiScore,
                         "high-score zero-usage should still lead high-usage low-score; got first=\(String(describing: sorted.first?.path))")
}

reporter.check("H2 SearchSortKey.openCount / .lastOpenedAt round-trip and sort correctly") {
    // DB round-trip for the sort persistence
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let ocDesc = SearchSortOrder(key: .openCount, ascending: false)
    try db.setResultSortOrder(ocDesc)
    let readBack = try db.getResultSortOrder()
    try reporter.require(readBack == ocDesc,
                         "openCount desc round-trip mismatch: \(readBack) vs \(ocDesc)")
    let loDesc = SearchSortOrder(key: .lastOpenedAt, ascending: true)
    try db.setResultSortOrder(loDesc)
    let loBack = try db.getResultSortOrder()
    try reporter.require(loBack == loDesc,
                         "lastOpenedAt asc round-trip mismatch: \(loBack) vs \(loDesc)")
    // Sort semantics (high openCount first when descending):
    let a = SearchResult(path: "/x/a.txt", name: "a.txt", isDir: false,
                         size: 0, mtime: 0, score: 0,
                         openCount: 10, lastOpenedAt: 100)
    let b = SearchResult(path: "/x/b.txt", name: "b.txt", isDir: false,
                         size: 0, mtime: 0, score: 0,
                         openCount: 1, lastOpenedAt: 200)
    let sortedOC = SearchEngine.sort([b, a], by: SearchSortOrder(key: .openCount, ascending: false))
    try reporter.require(sortedOC.map(\.path) == ["/x/a.txt", "/x/b.txt"],
                         "openCount desc should put a before b, got \(sortedOC.map(\.path))")
    let sortedLOAsc = SearchEngine.sort([b, a], by: SearchSortOrder(key: .lastOpenedAt, ascending: true))
    try reporter.require(sortedLOAsc.map(\.path) == ["/x/a.txt", "/x/b.txt"],
                         "lastOpenedAt asc should put a(100) before b(200), got \(sortedLOAsc.map(\.path))")
}

// MARK: - H3 recent: / frequent: entry points

// Helper: a DB with 3 indexed files; each gets a distinct usage row.
func makeH3Fixture(recordOpens: Bool = true) throws
    -> (Database, SearchEngine, URL, URL, [String]) {
    let dbDir = try makeTempDir()
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    try db.migrate()
    let root = try makeTempDir()
    let names = ["alpha.md", "beta.md", "gamma.txt"]
    for name in names {
        try "".write(to: root.appendingPathComponent(name),
                     atomically: true, encoding: .utf8)
    }
    let indexer = Indexer(database: db)
    _ = try indexer.indexRoot(root)
    // Indexer.canonicalize resolves symlinks (realpath). macOS temp
    // dirs live under `/var/folders/...` which realpath to
    // `/private/var/folders/...`. Use the canonical form so
    // recordOpen(path:) finds the matching files.id.
    let paths_ = names.map { Indexer.canonicalize(path: root.appendingPathComponent($0).path) }
    if recordOpens {
        // alpha.md: opened 5 times, most recent
        // beta.md:  opened 3 times, middle
        // gamma.txt: opened 1 time, earliest
        for _ in 0..<5 { _ = try db.recordOpen(path: paths_[0], now: 1_700_000_300) }
        for _ in 0..<3 { _ = try db.recordOpen(path: paths_[1], now: 1_700_000_200) }
        _ = try db.recordOpen(path: paths_[2], now: 1_700_000_100)
    }
    let engine = SearchEngine(database: db)
    return (db, engine, dbDir, root, paths_)
}

reporter.check("H3 parseQuery recognizes recent: / frequent: bare tokens and strips them") {
    let r1 = SearchEngine.parseQuery("recent:")
    try reporter.require(r1.usageMode == .recent,
                         "recent: should set usageMode=.recent, got \(r1.usageMode)")
    try reporter.require(r1.plainTokens.isEmpty,
                         "recent: should not leak into plainTokens, got \(r1.plainTokens)")
    let f1 = SearchEngine.parseQuery("frequent:")
    try reporter.require(f1.usageMode == .frequent,
                         "frequent: should set usageMode=.frequent, got \(f1.usageMode)")
    // First mode wins on collision.
    let both = SearchEngine.parseQuery("recent: frequent:")
    try reporter.require(both.usageMode == .recent,
                         "first mode wins, got \(both.usageMode)")
    // `recent:foo` (with value) is NOT a mode switch; falls through
    // to plainTokens as a literal `recent:foo` (unknown filter key).
    let withValue = SearchEngine.parseQuery("recent:foo")
    try reporter.require(withValue.usageMode == .normal,
                         "recent:foo is not a mode switch, got \(withValue.usageMode)")
    try reporter.require(withValue.plainTokens == ["recent:foo"],
                         "recent:foo should fall through to plainTokens literally, got \(withValue.plainTokens)")
}

reporter.check("H3 recent: returns files ordered by last_opened_at DESC") {
    let (db, engine, dbDir, root, paths_) = try makeH3Fixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    let hits = try engine.search("recent:")
    try reporter.require(hits.count == 3,
                         "expected 3 recent hits, got \(hits.count): \(hits.map(\.path))")
    try reporter.require(hits.map(\.path) == paths_,
                         "recent ordering wrong. got \(hits.map(\.path)) expected \(paths_)")
}

reporter.check("H3 frequent: returns files ordered by open_count DESC") {
    let (db, engine, dbDir, root, paths_) = try makeH3Fixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    let hits = try engine.search("frequent:")
    try reporter.require(hits.count == 3, "expected 3 frequent hits")
    // alpha (5) > beta (3) > gamma (1) — same ordering as paths_
    // by construction but verify explicitly.
    try reporter.require(hits[0].path == paths_[0] && hits[0].openCount == 5,
                         "alpha should lead at openCount=5, got \(hits[0].path) \(hits[0].openCount)")
    try reporter.require(hits[1].path == paths_[1] && hits[1].openCount == 3,
                         "beta should be middle at openCount=3, got \(hits[1].path) \(hits[1].openCount)")
    try reporter.require(hits[2].path == paths_[2] && hits[2].openCount == 1,
                         "gamma should be last at openCount=1, got \(hits[2].path) \(hits[2].openCount)")
}

reporter.check("H3 usage mode excludes files without a usage row") {
    let (db, engine, dbDir, root, paths_) = try makeH3Fixture(recordOpens: false)
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // No .open recorded yet — every indexed file has no usage row.
    let recent = try engine.search("recent:")
    try reporter.require(recent.isEmpty,
                         "recent: should be empty when no usage rows, got \(recent.map(\.path))")
    let frequent = try engine.search("frequent:")
    try reporter.require(frequent.isEmpty,
                         "frequent: should be empty when no usage rows, got \(frequent.map(\.path))")
    // After one open, exactly one file shows up.
    _ = try db.recordOpen(path: paths_[1], now: 1_700_000_000)
    let recentOne = try engine.search("recent:")
    try reporter.require(recentOne.count == 1 && recentOne.first?.path == paths_[1],
                         "only opened file should appear in recent:, got \(recentOne.map(\.path))")
}

reporter.check("H3 recent: composes with filters (recent: ext:md drops .txt)") {
    let (db, engine, dbDir, root, paths_) = try makeH3Fixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    let hits = try engine.search("recent: ext:md")
    try reporter.require(hits.count == 2,
                         "expected 2 .md recent hits, got \(hits.count): \(hits.map(\.path))")
    // alpha.md (last_opened 300) before beta.md (200); gamma.txt excluded.
    try reporter.require(hits.map(\.path) == [paths_[0], paths_[1]],
                         "recent+ext:md order wrong. got \(hits.map(\.path))")
    for h in hits {
        try reporter.require(h.name.hasSuffix(".md"),
                             "ext:md filter failed, got \(h.name)")
    }
}

reporter.check("H3 normal query path not polluted by recent:/frequent: implementation") {
    // A DB where two files have identical basename but only one has
    // been opened. Normal (no `recent:` prefix) search must still
    // return BOTH — the recent/frequent routing must not leak into
    // non-usage queries.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("a"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("b"),
                           withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("a/todo.md"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("b/todo.md"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    // Open only one of them. Path canonicalized to match what the
    // indexer stored (realpath resolves /var/folders -> /private/var/folders).
    let openedPath = Indexer.canonicalize(path: root.appendingPathComponent("a/todo.md").path)
    _ = try db.recordOpen(path: openedPath, now: 1_700_000_000)
    // Normal query returns BOTH — usage has only a tie-break role.
    let normalHits = try engine.search("todo")
    try reporter.require(normalHits.count == 2,
                         "normal query should still return both files; got \(normalHits.count): \(normalHits.map(\.path))")
    // The opened file leads because of H2 tie-break.
    try reporter.require(normalHits[0].path == openedPath,
                         "H2 tie-break should keep opened file first, got \(normalHits[0].path)")
    // `recent:` query returns ONLY the opened file.
    let recentHits = try engine.search("recent:")
    try reporter.require(recentHits.count == 1 && recentHits[0].path == openedPath,
                         "recent: should only return opened file; got \(recentHits.map(\.path))")
}

// MARK: - H4 usage history privacy controls

reporter.check("H4 usage history toggle defaults to on + round-trips") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Fresh DB: unset setting → default true.
    try reporter.require(try db.isUsageHistoryEnabled(),
                         "fresh DB should default to enabled")
    try db.setUsageHistoryEnabled(false)
    try reporter.require(try !db.isUsageHistoryEnabled(),
                         "expected disabled after setUsageHistoryEnabled(false)")
    try db.setUsageHistoryEnabled(true)
    try reporter.require(try db.isUsageHistoryEnabled(),
                         "expected enabled after setUsageHistoryEnabled(true)")
}

reporter.check("H4 recordOpen is a no-op while history recording is disabled") {
    let (db, fileId, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    try db.setUsageHistoryEnabled(false)
    let ok = try db.recordOpen(path: path, now: 1_700_000_000)
    try reporter.require(!ok, "recordOpen should return false while disabled")
    try reporter.require(try db.getUsageByFileId(fileId) == nil,
                         "usage row should NOT exist after disabled recordOpen")
    let remaining = try db.countRows(in: "file_usage")
    try reporter.require(remaining == 0,
                         "file_usage should remain empty, got \(remaining)")
    // Re-enable → write works again.
    try db.setUsageHistoryEnabled(true)
    let ok2 = try db.recordOpen(path: path, now: 1_700_000_100)
    try reporter.require(ok2, "recordOpen should return true after re-enabling")
    try reporter.require(try db.getUsageByFileId(fileId)?.openCount == 1,
                         "openCount should be 1 after re-enable + one open")
}

reporter.check("H4 clearFileUsage empties the table and returns rows removed") {
    let (db, _, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    _ = try db.recordOpen(path: path, now: 1_700_000_000)
    _ = try db.recordOpen(path: path, now: 1_700_000_100)
    try reporter.require(try db.countRows(in: "file_usage") == 1,
                         "precondition: one usage row present")
    let removed = try db.clearFileUsage()
    try reporter.require(removed == 1,
                         "clearFileUsage should return 1 (rows deleted), got \(removed)")
    try reporter.require(try db.countRows(in: "file_usage") == 0,
                         "file_usage should be empty after clear")
    // Clear does NOT flip the recording toggle.
    try reporter.require(try db.isUsageHistoryEnabled(),
                         "clear should not flip the recording toggle; history should still be enabled")
}

reporter.check("H4 clear makes recent: / frequent: immediately return empty") {
    let (db, engine, dbDir, root, _) = try makeH3Fixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // Sanity: recent: returns 3 before clear.
    try reporter.require(try engine.search("recent:").count == 3,
                         "precondition: 3 recent hits")
    let removed = try db.clearFileUsage()
    try reporter.require(removed == 3,
                         "expected 3 rows cleared, got \(removed)")
    try reporter.require(try engine.search("recent:").isEmpty,
                         "recent: should be empty after clear")
    try reporter.require(try engine.search("frequent:").isEmpty,
                         "frequent: should be empty after clear")
}

reporter.check("H4 DatabaseStats.fileUsageRowCount reflects current state") {
    let (db, _, path, dbDir) = try makeH1Fixture()
    defer { db.close(); cleanup(dbDir) }
    let preStats = db.computeStats()
    try reporter.require(preStats.fileUsageRowCount == 0,
                         "fresh DB should show fileUsageRowCount=0, got \(preStats.fileUsageRowCount)")
    _ = try db.recordOpen(path: path, now: 1_700_000_000)
    let midStats = db.computeStats()
    try reporter.require(midStats.fileUsageRowCount == 1,
                         "after one recordOpen fileUsageRowCount should be 1, got \(midStats.fileUsageRowCount)")
    _ = try db.clearFileUsage()
    let postStats = db.computeStats()
    try reporter.require(postStats.fileUsageRowCount == 0,
                         "after clear fileUsageRowCount should be 0, got \(postStats.fileUsageRowCount)")
}

// MARK: - J3 parser + wildcard / phrase / OR / NOT syntax

// Helper: fullpath-mode fixture with a small set of files so J3
// semantic tests (wildcard / phrase / OR / NOT) can exercise
// end-to-end without hand-rolling Row structs. Fullpath keeps
// path substring active so we can confirm "NOT across name and
// path" works.
func makeJ3EngineFixture() throws -> (Database, SearchEngine, URL, URL, [String: String]) {
    let dbDir = try makeTempDir()
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    let fm = FileManager.default
    // Directory layout:
    //   root/proj/alpha.md
    //   root/proj/beta.txt
    //   root/notes/foo bar.md      (literal space; phrase test)
    //   root/notes/fooxbar.md      (no space; phrase should miss)
    //   root/scratch/report-2024.log
    try fm.createDirectory(at: root.appendingPathComponent("proj"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("notes"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(at: root.appendingPathComponent("scratch"),
                           withIntermediateDirectories: true)
    var expected: [String: String] = [:]
    let files: [(String, String)] = [
        ("proj/alpha.md",        "proj-alpha"),
        ("proj/beta.txt",        "proj-beta"),
        ("notes/foo bar.md",     "phrase-match"),
        ("notes/fooxbar.md",     "phrase-miss"),
        ("scratch/report-2024.log", "report"),
    ]
    for (rel, tag) in files {
        let p = root.appendingPathComponent(rel)
        try "".write(to: p, atomically: true, encoding: .utf8)
        let canonical = Indexer.canonicalize(path: p.path)
        expected[tag] = canonical
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    return (db, engine, dbDir, root, expected)
}

reporter.check("J3 parser: wildcard preserved in plainTokens") {
    let p = SearchEngine.parseQuery("foo* f?o")
    try reporter.require(p.plainTokens == ["foo*", "f?o"],
                         "wildcard tokens should stay in plainTokens verbatim, got \(p.plainTokens)")
    try reporter.require(p.excludedTokens.isEmpty, "no negation expected")
    try reporter.require(p.orGroups.isEmpty, "no OR expected")
    try reporter.require(p.phraseTokens.isEmpty, "no phrase expected")
}

reporter.check("J3 parser: quoted phrase is captured; whitespace preserved") {
    let p = SearchEngine.parseQuery("\"foo bar\" baz")
    try reporter.require(p.phraseTokens == ["foo bar"],
                         "phrase should be 'foo bar' without quotes, got \(p.phraseTokens)")
    try reporter.require(p.plainTokens == ["baz"],
                         "bare token should still be in plainTokens, got \(p.plainTokens)")
}

reporter.check("J3 parser: NOT tokens strip !/- prefix") {
    let p = SearchEngine.parseQuery("foo !bar -qux")
    try reporter.require(p.plainTokens == ["foo"],
                         "plainTokens wrong: \(p.plainTokens)")
    try reporter.require(Set(p.excludedTokens) == Set(["bar", "qux"]),
                         "excludedTokens wrong: \(p.excludedTokens)")
}

reporter.check("J3 parser: NOT phrase keeps whitespace") {
    let p = SearchEngine.parseQuery("!\"foo bar\" alpha")
    try reporter.require(p.excludedPhrases == ["foo bar"],
                         "excludedPhrases wrong: \(p.excludedPhrases)")
    try reporter.require(p.plainTokens == ["alpha"],
                         "plainTokens wrong: \(p.plainTokens)")
}

reporter.check("J3 parser: OR groups split on | (>= 2 alts, no filter keys)") {
    let p = SearchEngine.parseQuery("foo|bar qux")
    try reporter.require(p.orGroups.count == 1, "expected 1 OR group, got \(p.orGroups)")
    try reporter.require(p.orGroups[0] == ["foo", "bar"],
                         "OR group wrong: \(p.orGroups[0])")
    try reporter.require(p.plainTokens == ["qux"],
                         "plainTokens wrong: \(p.plainTokens)")
}

reporter.check("J3 parser: | inside a filter-looking alt stays literal") {
    let p = SearchEngine.parseQuery("foo|ext:md")
    try reporter.require(p.orGroups.isEmpty,
                         "should not split when a filter key would be on the RHS")
    try reporter.require(p.plainTokens == ["foo|ext:md"],
                         "should fall back to literal token, got \(p.plainTokens)")
}

reporter.check("J3 parser: filter + usage + mixed syntax coexist") {
    let p = SearchEngine.parseQuery("ext:md recent: \"foo bar\" !draft alpha|beta")
    try reporter.require(p.filters.extensions == ["md"],
                         "ext filter dropped: \(p.filters.extensions)")
    try reporter.require(p.usageMode == .recent,
                         "recent: not picked up: \(p.usageMode)")
    try reporter.require(p.phraseTokens == ["foo bar"], "phrase wrong: \(p.phraseTokens)")
    try reporter.require(p.excludedTokens == ["draft"], "NOT wrong: \(p.excludedTokens)")
    try reporter.require(p.orGroups == [["alpha", "beta"]], "OR wrong: \(p.orGroups)")
    try reporter.require(p.plainTokens.isEmpty, "unexpected plainTokens: \(p.plainTokens)")
}

reporter.check("J3 parser: bare !/- with empty remainder is ignored") {
    let p = SearchEngine.parseQuery("foo - ! bar")
    try reporter.require(p.plainTokens == ["foo", "bar"],
                         "bare !/- should be dropped, got \(p.plainTokens)")
    try reporter.require(p.excludedTokens.isEmpty,
                         "nothing should have been negated: \(p.excludedTokens)")
}

reporter.check("J3 parser: empty phrase \"\" is ignored") {
    let p = SearchEngine.parseQuery("foo \"\" bar")
    try reporter.require(p.plainTokens == ["foo", "bar"],
                         "empty phrase should be dropped, got \(p.plainTokens)")
    try reporter.require(p.phraseTokens.isEmpty,
                         "empty phrase should not be captured: \(p.phraseTokens)")
}

reporter.check("J3 wildcardAnchor: longest literal run") {
    try reporter.require(SearchEngine.wildcardAnchor("foo") == "foo",
                         "no wildcard → full text")
    try reporter.require(SearchEngine.wildcardAnchor("foo*bar") == "foo" || SearchEngine.wildcardAnchor("foo*bar") == "bar",
                         "either side is acceptable (same length 3)")
    try reporter.require(SearchEngine.wildcardAnchor("f?oob*ar") == "oob",
                         "longest run wins: got \(SearchEngine.wildcardAnchor("f?oob*ar"))")
    try reporter.require(SearchEngine.wildcardAnchor("***") == "",
                         "pure wildcards → empty anchor")
    try reporter.require(SearchEngine.wildcardAnchor("?") == "",
                         "single wildcard → empty anchor")
}

reporter.check("J3 tokenMatchesWildcard: wildcard and literal coverage") {
    // No wildcard — plain contains semantics.
    try reporter.require(SearchEngine.tokenMatchesWildcard("foo", in: "foobar"),
                         "'foo' should match 'foobar'")
    try reporter.require(!SearchEngine.tokenMatchesWildcard("baz", in: "foobar"),
                         "'baz' should NOT match 'foobar'")
    // `*` matches zero or more characters.
    try reporter.require(SearchEngine.tokenMatchesWildcard("foo*", in: "foobar"),
                         "'foo*' should match 'foobar'")
    try reporter.require(SearchEngine.tokenMatchesWildcard("*bar", in: "foobar"),
                         "'*bar' should match 'foobar'")
    try reporter.require(SearchEngine.tokenMatchesWildcard("f*r", in: "foobar"),
                         "'f*r' should match 'foobar'")
    // `?` matches exactly one character.
    try reporter.require(SearchEngine.tokenMatchesWildcard("f?o", in: "foo"),
                         "'f?o' should match 'foo'")
    try reporter.require(SearchEngine.tokenMatchesWildcard("f?o", in: "fao"),
                         "'f?o' should match 'fao'")
    try reporter.require(!SearchEngine.tokenMatchesWildcard("f?o", in: "fo"),
                         "'?' requires exactly 1 char; 'fo' should miss")
    // Regex specials inside wildcard pattern must be escaped.
    try reporter.require(SearchEngine.tokenMatchesWildcard("a.b", in: "xa.bx"),
                         "'.' should be literal, not regex any-char")
    try reporter.require(!SearchEngine.tokenMatchesWildcard("a.b", in: "axbx"),
                         "'a.b' should NOT match 'axbx' (dot is literal)")
}

reporter.check("J3 search: wildcard matches expected files") {
    let (db, engine, dbDir, root, expected) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // `alph*` matches alpha.md only.
    let a = try engine.search("alph*")
    try reporter.require(a.map(\.path).contains(expected["proj-alpha"]!),
                         "alph* missed alpha.md: \(a.map(\.path))")
    try reporter.require(!a.map(\.path).contains(expected["proj-beta"]!),
                         "alph* should not match beta.txt")
    // `?eta*` matches beta.txt (single char + rest anything)
    let b = try engine.search("?eta*")
    try reporter.require(b.map(\.path).contains(expected["proj-beta"]!),
                         "?eta* missed beta.txt: \(b.map(\.path))")
}

reporter.check("J3 search: quoted phrase requires whitespace literally") {
    let (db, engine, dbDir, root, expected) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    let hits = try engine.search("\"foo bar\"")
    let paths = hits.map(\.path)
    try reporter.require(paths.contains(expected["phrase-match"]!),
                         "phrase \"foo bar\" missed `notes/foo bar.md`: \(paths)")
    try reporter.require(!paths.contains(expected["phrase-miss"]!),
                         "phrase should NOT match `fooxbar.md`: \(paths)")
}

reporter.check("J3 search: OR returns union, not AND") {
    let (db, engine, dbDir, root, expected) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // `alpha|beta` should match both proj/alpha.md and proj/beta.txt.
    let hits = try engine.search("alpha|beta")
    let paths = Set(hits.map(\.path))
    try reporter.require(paths.contains(expected["proj-alpha"]!),
                         "OR missed alpha.md: \(paths)")
    try reporter.require(paths.contains(expected["proj-beta"]!),
                         "OR missed beta.txt: \(paths)")
}

reporter.check("J3 search: NOT excludes a file") {
    let (db, engine, dbDir, root, expected) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // `md -alpha` → md files but not alpha. Hits beta.txt? No, it's .txt.
    // Use `proj -alpha` in fullpath mode: matches beta.txt (path has 'proj')
    // but not alpha.md.
    let hits = try engine.search("proj -alpha")
    let paths = hits.map(\.path)
    try reporter.require(paths.contains(expected["proj-beta"]!),
                         "NOT should keep beta.txt: \(paths)")
    try reporter.require(!paths.contains(expected["proj-alpha"]!),
                         "NOT should exclude alpha.md: \(paths)")
}

reporter.check("J3 search: NOT phrase excludes literal space") {
    let (db, engine, dbDir, root, expected) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // All .md in /notes except the one with "foo bar" phrase.
    let hits = try engine.search("notes !\"foo bar\"")
    let paths = hits.map(\.path)
    try reporter.require(paths.contains(expected["phrase-miss"]!),
                         "NOT phrase should keep fooxbar.md: \(paths)")
    try reporter.require(!paths.contains(expected["phrase-match"]!),
                         "NOT phrase should exclude `foo bar.md`: \(paths)")
}

reporter.check("J3 search: wildcard + filter + usage mode compose") {
    let (db, engine, dbDir, root, expected) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // Open beta.txt so recent: shows it.
    _ = try db.recordOpen(path: expected["proj-beta"]!, now: 1_700_000_000)
    let hits = try engine.search("recent: *ta* ext:txt")
    try reporter.require(hits.count == 1 && hits[0].path == expected["proj-beta"]!,
                         "expected only beta.txt via recent+wildcard+ext: \(hits.map(\.path))")
}

reporter.check("J3 round 2: pure-OR finds matches past bounded-scan window") {
    // Regression for Codex J3 round 1 REJECT: `alpha|beta` was
    // falling through to filterOnlyCandidates() which only
    // scanned the first `candidatePool` rows of `files`. Build a
    // fixture > candidatePool with the only OR-hit placed well
    // past that window and confirm the fix retrieves it.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    // Default Options.limit=100, candidateMultiplier=4 -> pool=400.
    // Create 600 files; place the target at index 550 (well past 400).
    let total = 600
    let targetIdx = 550
    for i in 0..<total {
        let name = (i == targetIdx) ? "beta_target_unique.md" : "filler_\(i).txt"
        try "".write(to: root.appendingPathComponent(name),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    // Pure-OR with one alt nonexistent, the other pointing at the
    // far-end target. Without J3 round 2 fix this would miss.
    let hits = try engine.search("nonexistentxyz|beta_target_unique")
    let names = hits.map(\.name)
    try reporter.require(names.contains("beta_target_unique.md"),
                         "pure-OR must find row at index \(targetIdx) past bounded window; got first 5 = \(names.prefix(5))")
    // Also confirm negative alt alone doesn't yield false positives.
    let emptyHits = try engine.search("nonexistentxyz|alsonothere")
    try reporter.require(emptyHits.isEmpty,
                         "OR with no matches anywhere must return []; got \(emptyHits.count)")
}

reporter.check("J3 round 3: OR with pure-wildcard alt matches all (*|foo)") {
    // *|foo: `*` should semantically match every file; unioned with
    // `foo` → result should include at least one file that doesn't
    // contain "foo", proving the wildcard alt actually contributed.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    let fm = FileManager.default
    try "".write(to: root.appendingPathComponent("foo-target.md"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("unrelated.txt"),
                 atomically: true, encoding: .utf8)
    try "".write(to: root.appendingPathComponent("another.log"),
                 atomically: true, encoding: .utf8)
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("*|foo")
    let names = Set(hits.map(\.name))
    try reporter.require(names.contains("foo-target.md"),
                         "foo alt should hit foo-target.md, got \(names)")
    // Critical: wildcard alt must also contribute — at least ONE file
    // whose name does not contain 'foo' must be present.
    let nonFoo = names.filter { !$0.contains("foo") }
    try reporter.require(!nonFoo.isEmpty,
                         "wildcard alt `*` must contribute files that don't contain 'foo'; got names=\(names)")
}

reporter.check("J3 round 3: pure-wildcard OR returns bounded scan (*|?)") {
    // Both alts are pure wildcards. orUnionCandidates should fall
    // into the bounded-scan branch and return at least some rows,
    // not an empty set.
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try db.setIndexMode(.fullpath)
    let root = try makeTempDir()
    defer { cleanup(root) }
    for name in ["alpha.md", "beta.txt", "gamma.log"] {
        try "".write(to: root.appendingPathComponent(name),
                     atomically: true, encoding: .utf8)
    }
    _ = try Indexer(database: db).indexRoot(root)
    let engine = SearchEngine(database: db)
    let hits = try engine.search("*|?")
    try reporter.require(hits.count >= 3,
                         "pure-wildcard OR should include all 3 files, got \(hits.count): \(hits.map(\.name))")
}

reporter.check("J3 search: illegal syntax doesn't crash, degrades to plain") {
    let (db, engine, dbDir, root, _) = try makeJ3EngineFixture()
    defer { db.close(); cleanup(dbDir); cleanup(root) }
    // Unterminated phrase — parser auto-closes; query still runs.
    _ = try engine.search("\"foo bar")
    // Just `|` — falls through as literal 1-char token.
    _ = try engine.search("|")
    // Just `*` — pure wildcard; falls back to filterOnly bounded scan.
    _ = try engine.search("*")
    // Double NOT — second `!` becomes part of the excluded term.
    _ = try engine.search("!!foo")
    // Empty OR + filter combo.
    _ = try engine.search("alpha|| ext:md")
}

// MARK: - J6 settings tab memory + launch-at-login intent

reporter.check("J6 getSettingsTabIndex default 0 + round-trip") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try reporter.require(try db.getSettingsTabIndex() == 0,
                         "fresh DB should return 0")
    try db.setSettingsTabIndex(2)
    try reporter.require(try db.getSettingsTabIndex() == 2,
                         "round-trip 2")
    try db.setSettingsTabIndex(0)
    try reporter.require(try db.getSettingsTabIndex() == 0,
                         "back to 0")
    // Negative should clamp to 0.
    try db.setSettingsTabIndex(-5)
    try reporter.require(try db.getSettingsTabIndex() == 0,
                         "negative clamped to 0")
}

reporter.check("J6 getLaunchAtLoginRequested default false + round-trip") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    try reporter.require(try !db.getLaunchAtLoginRequested(),
                         "fresh DB should default false")
    try db.setLaunchAtLoginRequested(true)
    try reporter.require(try db.getLaunchAtLoginRequested(),
                         "round-trip true")
    try db.setLaunchAtLoginRequested(false)
    try reporter.require(try !db.getLaunchAtLoginRequested(),
                         "round-trip false")
}

// MARK: - J5 path helpers (context menu primitives)

reporter.check("J5 PathHelpers.fileName: last component of typical path") {
    try reporter.require(PathHelpers.fileName(of: "/foo/bar/baz.txt") == "baz.txt",
                         "/foo/bar/baz.txt -> baz.txt")
    try reporter.require(PathHelpers.fileName(of: "/foo/bar/") == "bar",
                         "trailing slash stripped first: /foo/bar/ -> bar")
    try reporter.require(PathHelpers.fileName(of: "/") == "/",
                         "root unchanged: / -> /")
    try reporter.require(PathHelpers.fileName(of: "") == "",
                         "empty -> empty")
    try reporter.require(PathHelpers.fileName(of: "lone.md") == "lone.md",
                         "relative with no slash: lone.md -> lone.md")
    try reporter.require(PathHelpers.fileName(of: "中文文件.pdf") == "中文文件.pdf",
                         "unicode filename preserved")
}

reporter.check("J5 PathHelpers.parentFolder: deletingLastPathComponent") {
    try reporter.require(PathHelpers.parentFolder(of: "/foo/bar/baz.txt") == "/foo/bar",
                         "/foo/bar/baz.txt -> /foo/bar")
    try reporter.require(PathHelpers.parentFolder(of: "/foo/bar/") == "/foo",
                         "trailing slash stripped then parent: /foo/bar/ -> /foo")
    try reporter.require(PathHelpers.parentFolder(of: "/baz.txt") == "/",
                         "/baz.txt -> /")
    try reporter.require(PathHelpers.parentFolder(of: "") == "",
                         "empty -> empty")
    // NSString.deletingLastPathComponent on a relative file like
    // "foo.md" returns "" — which we intentionally surface so the
    // GUI can warn rather than silently copy "".
    let rel = PathHelpers.parentFolder(of: "foo.md")
    try reporter.require(rel == "" || rel == ".",
                         "relative no-slash path parent: got `\(rel)`; empty or . acceptable")
}

// MARK: - J4 search history + saved filters

func makeJ4DB() throws -> (Database, URL) {
    let dbDir = try makeTempDir()
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    try db.migrate()
    return (db, dbDir)
}

reporter.check("J4 schema v7: query_history + saved_filters present") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    try reporter.require(Schema.currentVersion >= 7,
                         "Schema.currentVersion should be >= 7 for J4, got \(Schema.currentVersion)")
    try reporter.require(try db.tableExists("query_history"),
                         "query_history missing after v7 migrate")
    try reporter.require(try db.tableExists("saved_filters"),
                         "saved_filters missing after v7 migrate")
    try reporter.require(try db.countRows(in: "query_history") == 0,
                         "query_history should start empty")
    try reporter.require(try db.countRows(in: "saved_filters") == 0,
                         "saved_filters should start empty")
}

reporter.check("J4 queryHistoryEnabled defaults to on + round-trips") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    try reporter.require(try db.isQueryHistoryEnabled(),
                         "fresh DB should default to enabled")
    try db.setQueryHistoryEnabled(false)
    try reporter.require(try !db.isQueryHistoryEnabled(),
                         "disabled after set(false)")
    try db.setQueryHistoryEnabled(true)
    try reporter.require(try db.isQueryHistoryEnabled(),
                         "enabled after set(true)")
}

reporter.check("J4 recordQueryHistory creates + UPSERTs by query") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    let ok1 = try db.recordQueryHistory("alpha", now: 1_700_000_000)
    try reporter.require(ok1, "first record should return true")
    let ok2 = try db.recordQueryHistory("alpha", now: 1_700_000_050)
    try reporter.require(ok2, "second record should also return true (UPSERT)")
    let recent = try db.listRecentQueries(limit: 10)
    try reporter.require(recent.count == 1,
                         "dedup on query: expected 1 row, got \(recent.count)")
    try reporter.require(recent[0].query == "alpha" && recent[0].useCount == 2,
                         "expected alpha/useCount=2, got \(recent[0])")
    try reporter.require(recent[0].lastUsedAt == 1_700_000_050,
                         "lastUsedAt should track latest, got \(recent[0].lastUsedAt)")
}

reporter.check("J4 recordQueryHistory rejects empty/whitespace + honors disabled toggle") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    try reporter.require(!(try db.recordQueryHistory("")),
                         "empty query should return false")
    try reporter.require(!(try db.recordQueryHistory("   \n")),
                         "whitespace-only query should return false")
    try db.setQueryHistoryEnabled(false)
    try reporter.require(!(try db.recordQueryHistory("alpha")),
                         "disabled toggle should reject")
    try reporter.require(try db.countRows(in: "query_history") == 0,
                         "no rows should have been written")
}

reporter.check("J4 listRecentQueries is ordered by last_used_at DESC") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    _ = try db.recordQueryHistory("alpha",   now: 1_700_000_100)
    _ = try db.recordQueryHistory("beta",    now: 1_700_000_300)  // newest
    _ = try db.recordQueryHistory("gamma",   now: 1_700_000_200)
    let recent = try db.listRecentQueries(limit: 10)
    try reporter.require(recent.map(\.query) == ["beta", "gamma", "alpha"],
                         "recent order wrong: \(recent.map(\.query))")
}

reporter.check("J4 clearQueryHistory empties the table; returns pre-delete count") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    _ = try db.recordQueryHistory("a", now: 1_700_000_000)
    _ = try db.recordQueryHistory("b", now: 1_700_000_100)
    let removed = try db.clearQueryHistory()
    try reporter.require(removed == 2, "expected 2 rows cleared, got \(removed)")
    try reporter.require(try db.countRows(in: "query_history") == 0,
                         "table should be empty")
}

reporter.check("J4 saveFilter / list / remove round-trip") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    try reporter.require(try db.saveFilter(name: "weekly", query: "ext:md recent:", now: 1_700_000_000),
                         "saveFilter should return true")
    try reporter.require(try db.saveFilter(name: "zeta-project", query: "path:projects/zeta", now: 1_700_000_050),
                         "second saveFilter should return true")
    let list = try db.listSavedFilters()
    try reporter.require(list.map(\.name) == ["weekly", "zeta-project"],
                         "saved filter order (alpha asc) wrong: \(list.map(\.name))")
    // Update existing by saving again with same name.
    _ = try db.saveFilter(name: "weekly", query: "ext:md frequent:", now: 1_700_000_100)
    let list2 = try db.listSavedFilters()
    try reporter.require(list2.count == 2, "should still be 2 filters after update")
    try reporter.require(list2.first(where: { $0.name == "weekly" })?.query == "ext:md frequent:",
                         "weekly should have new query")
    // Remove
    try reporter.require(try db.removeSavedFilter(name: "weekly"),
                         "remove should return true")
    try reporter.require(!(try db.removeSavedFilter(name: "weekly")),
                         "second remove on same name should return false")
    let final = try db.listSavedFilters()
    try reporter.require(final.map(\.name) == ["zeta-project"],
                         "unexpected filters after remove: \(final.map(\.name))")
}

reporter.check("J4 saveFilter rejects empty name or empty query") {
    let (db, dbDir) = try makeJ4DB()
    defer { db.close(); cleanup(dbDir) }
    try reporter.require(!(try db.saveFilter(name: "", query: "ext:md")),
                         "empty name should be rejected")
    try reporter.require(!(try db.saveFilter(name: "ok", query: "")),
                         "empty query should be rejected")
    try reporter.require(!(try db.saveFilter(name: "   ", query: "ext:md")),
                         "whitespace-only name should be rejected")
    try reporter.require(try db.countRows(in: "saved_filters") == 0,
                         "no rows should have been written")
}

// MARK: - J2 result column width reset + usage visibility

reporter.check("J2 resetResultColumnWidths clears all 6 persisted widths") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Seed all 6 width keys.
    let keys = [
        SettingsKey.resultColumnWidthName,
        SettingsKey.resultColumnWidthPath,
        SettingsKey.resultColumnWidthMtime,
        SettingsKey.resultColumnWidthSize,
        SettingsKey.resultColumnWidthOpenCount,
        SettingsKey.resultColumnWidthLastOpened,
    ]
    for k in keys {
        try db.setResultColumnWidth(key: k, width: 33)
    }
    for k in keys {
        let v = try db.getResultColumnWidth(key: k)
        try reporter.require(v == 33, "precondition: \(k) should be 33 before reset, got \(String(describing: v))")
    }
    let removed = try db.resetResultColumnWidths()
    try reporter.require(removed == 6, "expected 6 keys removed, got \(removed)")
    for k in keys {
        let v = try db.getResultColumnWidth(key: k)
        try reporter.require(v == nil,
                             "\(k) should return nil after reset, got \(String(describing: v))")
    }
}

reporter.check("J2 resetResultColumnWidths is idempotent when nothing was persisted") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    // Fresh DB: no width keys present.
    let removed = try db.resetResultColumnWidths()
    try reporter.require(removed == 0, "fresh DB reset should remove 0 keys, got \(removed)")
    // Calling again is still a no-op.
    let removedAgain = try db.resetResultColumnWidths()
    try reporter.require(removedAgain == 0, "second reset should still remove 0, got \(removedAgain)")
}

reporter.check("J2 resetResultColumnWidths does not touch sort-order keys") {
    let dbDir = try makeTempDir()
    defer { cleanup(dbDir) }
    let paths = try AppPaths.ensureSupportDirectory(override: dbDir)
    let db = try Database.open(at: paths.databaseURL)
    defer { db.close() }
    try db.migrate()
    let sortOrder = SearchSortOrder(key: .openCount, ascending: false)
    try db.setResultSortOrder(sortOrder)
    try db.setResultColumnWidth(key: SettingsKey.resultColumnWidthName, width: 99)
    _ = try db.resetResultColumnWidths()
    let sortBack = try db.getResultSortOrder()
    try reporter.require(sortBack == sortOrder,
                         "sort order should survive column width reset: got \(sortBack), expected \(sortOrder)")
}

// MARK: - J1 settings window lifecycle (hide-only close pattern)

#if canImport(AppKit)
/// Stand-in for SettingsWindowController's hide-only behaviour. The
/// actual controller lives in the SwiftSeek GUI module which the
/// smoke target does not link against, so we validate the *pattern*
/// here: an NSWindow whose delegate returns false from
/// windowShouldClose and sends orderOut. This is the exact pattern
/// J1 applied to the real settings window.
final class HideOnlyStub: NSObject, NSWindowDelegate {
    private(set) var hideCallCount = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideCallCount += 1
        sender.orderOut(nil)
        return false
    }
}

reporter.check("J1 NSWindow hide-only delegate: close action keeps window alive") {
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                       styleMask: [.titled, .closable],
                       backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    let stub = HideOnlyStub()
    win.delegate = stub
    // Show, then simulate the red-button click.
    win.makeKeyAndOrderFront(nil)
    // performClose(_:) respects windowShouldClose return value.
    win.performClose(nil)
    try reporter.require(stub.hideCallCount == 1,
                         "windowShouldClose should have been invoked exactly once, got \(stub.hideCallCount)")
    // Window must still be allocated and re-showable.
    try reporter.require(win.delegate === stub,
                         "delegate retained after performClose")
    try reporter.require(!win.isVisible,
                         "window should have been hidden (isVisible=false)")
    // Re-show: must succeed without allocating a new controller.
    win.makeKeyAndOrderFront(nil)
    try reporter.require(win.isVisible,
                         "window must be re-showable via makeKeyAndOrderFront after hide-only close")
    // Repeat the close/show loop 10× to match the manual-test
    // contract (J1 validates "10 次不丢 controller / 不失效").
    for i in 0..<10 {
        win.performClose(nil)
        try reporter.require(!win.isVisible,
                             "iteration \(i): window should be hidden after close")
        win.makeKeyAndOrderFront(nil)
        try reporter.require(win.isVisible,
                             "iteration \(i): window should be re-showable")
    }
    try reporter.require(stub.hideCallCount == 11,
                         "expected 11 hide calls (1 + 10), got \(stub.hideCallCount)")
    win.close() // actually release now; isReleasedWhenClosed=false still lets us reuse but test is done
}
#endif

reporter.check("H2 non-score sort keys unaffected by usage tie-break (name regression)") {
    // Two SearchResults with same name (impossible in practice but
    // the test must guarantee usage doesn't leak into `.name` sort):
    // use different names and confirm alpha order holds regardless of
    // openCount.
    let highUsageZ = SearchResult(path: "/a/zebra.txt", name: "zebra.txt",
                                  isDir: false, size: 0, mtime: 0,
                                  score: 100, openCount: 999, lastOpenedAt: 999)
    let noUsageA = SearchResult(path: "/a/apple.txt", name: "apple.txt",
                                isDir: false, size: 0, mtime: 0,
                                score: 100, openCount: 0, lastOpenedAt: 0)
    let sorted = SearchEngine.sort([highUsageZ, noUsageA],
                                   by: SearchSortOrder(key: .name, ascending: true))
    try reporter.require(sorted.map(\.name) == ["apple.txt", "zebra.txt"],
                         "name ascending should be apple then zebra regardless of usage, got \(sorted.map(\.name))")
}

exit(reporter.summary())
