import Foundation

/// L3 — pure formatter for the menubar status item's tooltip and the
/// status-only entries in its dropdown menu. Lives in the Core module
/// (no AppKit) so the smoke test can pin format invariants without
/// spinning the GUI.
///
/// Design constraints:
///   - Read-only: takes a `Database` handle and a precomputed indexing
///     state string from the caller. Never mutates settings.
///   - Resilient: every sub-probe is wrapped in `do/catch`; a single
///     bad column never collapses the snapshot. Failed sub-probes
///     surface as "—" or short fallback labels in the menu, never as a
///     thrown error to AppDelegate.
///   - Tight: tooltip stays under ~6 lines (each ~60 chars) to feel
///     native; menu items stay one line each. We deliberately do NOT
///     duplicate the K3 Diagnostics.snapshot full text — that lives
///     behind "复制诊断信息" for triage. The menubar is for quick
///     status, not bug-report triage.
public enum MenubarStatus {
    /// What the caller passes in. The `indexingDescription` is the
    /// short form already shown in the existing 索引：... menu item
    /// (e.g. "空闲" or "索引中 · 3/5 roots") — we keep that wording
    /// stable for L1/L2 visual continuity.
    public struct Snapshot: Equatable, Sendable {
        public let buildSummary: String     // e.g. "SwiftSeek 1.0-K2 commit=5ff1334 build=2026-04-26"
        public let indexingDescription: String // e.g. "空闲" / "索引中 · 3/5 roots"
        public let indexModeLabel: String   // "Compact" / "Full path" / "—"
        public let rootsLabel: String       // e.g. "5 个（4 启用，1 不健康）" or "暂无 root"
        public let dbSizeLabel: String      // e.g. "DB 大小：1.2 GB" or "DB 大小：—"

        public init(buildSummary: String,
                    indexingDescription: String,
                    indexModeLabel: String,
                    rootsLabel: String,
                    dbSizeLabel: String) {
            self.buildSummary = buildSummary
            self.indexingDescription = indexingDescription
            self.indexModeLabel = indexModeLabel
            self.rootsLabel = rootsLabel
            self.dbSizeLabel = dbSizeLabel
        }
    }

    /// Compose a snapshot from a live Database. The indexing
    /// description is the only piece that the caller (AppDelegate)
    /// has authoritative state for — we don't peek at
    /// RebuildCoordinator from Core, we accept its rendered string.
    public static func snapshot(database: Database,
                                indexingDescription: String) -> Snapshot {
        // build identity: BuildInfo never throws.
        let summary = BuildInfo.summary

        // index mode: fall back to "—" on read failure rather than
        // showing a misleading default — a corrupt setting shouldn't
        // make the menu lie about which mode is active.
        let modeLabel: String
        if let mode = try? database.getIndexMode() {
            switch mode {
            case .compact: modeLabel = "Compact"
            case .fullpath: modeLabel = "Full path"
            }
        } else {
            modeLabel = "—"
        }

        // roots summary: total + enabled count, with a separate
        // "unhealthy" tail when applicable so users notice broken
        // permission / volume / missing-path roots from the menubar
        // without having to open Settings → 索引.
        let rootsLabel: String
        if let rows = try? database.listRoots() {
            rootsLabel = formatRoots(rows: rows, database: database)
        } else {
            rootsLabel = "读取 roots 失败"
        }

        // DB size: just the main file. WAL/SHM are noise for a quick
        // glance; full breakdown lives in Diagnostics.snapshot.
        let stats = database.computeStats()
        let dbSizeLabel: String
        if stats.mainFileBytes >= 0 {
            dbSizeLabel = "DB 大小：\(DatabaseStats.humanBytes(stats.mainFileBytes))"
        } else {
            dbSizeLabel = "DB 大小：—"
        }

        return Snapshot(
            buildSummary: summary,
            indexingDescription: indexingDescription,
            indexModeLabel: modeLabel,
            rootsLabel: rootsLabel,
            dbSizeLabel: dbSizeLabel
        )
    }

    /// Compose a roots label that reads "N 个（M 启用，K 不健康）"
    /// when there are unhealthy roots, or "N 个（M 启用）" when all
    /// enabled roots are healthy, or "暂无 root" for an empty list.
    /// Unhealthy = `RootHealth` is `.offline` / `.volumeOffline` /
    /// `.unavailable`. We treat `.paused` as enabled-but-disabled by
    /// the user, not unhealthy (the user did that on purpose).
    public static func formatRoots(rows: [RootRow], database: Database) -> String {
        if rows.isEmpty { return "暂无 root" }
        let total = rows.count
        let enabled = rows.filter { $0.enabled }.count
        // Only enabled roots count as "should-be-working"; counting
        // unhealthy on disabled rows would noise up the menu.
        var unhealthy = 0
        for row in rows where row.enabled {
            let report = database.computeRootHealthReport(for: row)
            switch report.health {
            case .offline, .volumeOffline, .unavailable:
                unhealthy += 1
            case .ready, .indexing, .paused:
                break
            }
        }
        if unhealthy > 0 {
            return "\(total) 个（\(enabled) 启用，\(unhealthy) 不健康）"
        } else {
            return "\(total) 个（\(enabled) 启用）"
        }
    }

    /// Multi-line tooltip text. Order matches the menu order so a
    /// user who can read either spot sees the same story. Newlines
    /// are real `\n`; AppKit renders them in the tooltip popup.
    public static func tooltipText(snapshot: Snapshot) -> String {
        return """
        \(snapshot.buildSummary)
        索引：\(snapshot.indexingDescription)
        模式：\(snapshot.indexModeLabel)
        roots：\(snapshot.rootsLabel)
        \(snapshot.dbSizeLabel)
        """
    }
}
