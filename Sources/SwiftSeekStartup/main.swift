import Foundation
import SwiftSeekCore

// Non-GUI startup check — mirrors exactly what AppDelegate.applicationDidFinishLaunching
// does for the Core portion, without requiring WindowServer / AppKit.
//
// Usage:
//   swift run --disable-sandbox SwiftSeekStartup
//       → uses default ~/Library/Application Support/SwiftSeek/index.sqlite3
//
//   swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-check.sqlite3
//       → uses the specified path (useful in Codex workspace-write sandbox where
//         ~/Library is not writable; /tmp is always writable)
//
// Prints: SwiftSeek: database ready at <path> schema=<N>
//         SwiftSeek: startup check PASS
// Exit 0 on success, 1 on failure.

var dbOverridePath: String? = nil
var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    if arg == "--db", let next = args.first {
        dbOverridePath = next
        args = args.dropFirst()
    }
}

do {
    let dbURL: URL
    if let override = dbOverridePath {
        dbURL = URL(fileURLWithPath: override)
        // Ensure parent directory exists.
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    } else {
        let paths = try AppPaths.ensureSupportDirectory()
        dbURL = paths.databaseURL
    }

    let db = try Database.open(at: dbURL)
    try db.migrate()
    let schema = db.schemaVersion
    db.close()

    print("SwiftSeek: database ready at \(dbURL.path) schema=\(schema)")

    guard schema == Schema.currentVersion else {
        fputs("SwiftSeek: FAIL schema=\(schema) expected=\(Schema.currentVersion)\n", stderr)
        exit(1)
    }
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        fputs("SwiftSeek: FAIL sqlite file not present at \(dbURL.path)\n", stderr)
        exit(1)
    }

    // Prove SearchEngine can be constructed and queried (what SearchViewController does).
    let db2 = try Database.open(at: dbURL)
    defer { db2.close() }
    let engine = SearchEngine(database: db2)
    _ = try engine.search("startup-check")

    print("SwiftSeek: startup check PASS")
    exit(0)
} catch {
    fputs("SwiftSeek: startup check FAIL \(error)\n", stderr)
    exit(1)
}
