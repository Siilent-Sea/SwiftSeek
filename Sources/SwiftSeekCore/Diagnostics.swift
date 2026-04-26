import Foundation

/// K3 — single source of truth for the user-facing diagnostics
/// snapshot. Surfaces build identity (BuildInfo) + DB / index /
/// usage / query history / Launch-at-Login intent in one
/// copyable text block.
///
/// Pure-ish: takes a Database handle and a closure that reports
/// Launch-at-Login system status. AppKit-free so the smoke target
/// can test the format directly without spinning the GUI module.
public enum Diagnostics {
    /// Optional caller-supplied probe of the actual SMAppService
    /// state. The GUI layer wires this to LaunchAtLogin.isRegistered();
    /// smoke tests pass `nil` (which renders as "—" so the report
    /// never lies about Launch-at-Login state in headless contexts).
    public typealias LaunchAtLoginStatusProbe = () -> Bool?

    /// Build the full diagnostics text. Each section catches its
    /// own DB read errors and surfaces them in a trailing block so
    /// one bad subquery never blanks the whole report — the K1
    /// AboutPane error-collection contract preserved.
    public static func snapshot(database: Database,
                                launchAtLoginIntent: Bool? = nil,
                                launchAtLoginSystemStatus: LaunchAtLoginStatusProbe? = nil) -> String {
        var errors: [String] = []
        func safe<T>(_ label: String, default defaultValue: T, _ fn: () throws -> T) -> T {
            do { return try fn() } catch {
                errors.append("\(label): \(error)")
                return defaultValue
            }
        }

        // --- build identity -----------------------------------------
        let identity = """
        SwiftSeek 诊断信息
        版本：\(BuildInfo.appVersion)
        build commit：\(BuildInfo.gitCommit)
        build date：\(BuildInfo.buildDate)
        bundle：\(BuildInfo.bundlePath)
        binary：\(BuildInfo.executablePath)
        """

        // --- DB ----------------------------------------------------
        let dbPath = database.url.path
        let schema = database.schemaVersion
        let stats = database.computeStats()
        let mainBytes = DatabaseStats.humanBytes(stats.mainFileBytes)
        let walBytes = DatabaseStats.humanBytes(stats.walFileBytes)
        let shmBytes = DatabaseStats.humanBytes(stats.shmFileBytes)
        let filesCount = stats.filesRowCount
        let fileUsageCount = stats.fileUsageRowCount
        let queryHistoryCount = safe("countRows(query_history)", default: Int64(-1)) {
            try database.countRows(in: "query_history")
        }
        let savedFiltersCount = safe("countRows(saved_filters)", default: Int64(-1)) {
            try database.countRows(in: "saved_filters")
        }

        // --- settings / index mode ---------------------------------
        let indexMode = safe("getIndexMode", default: "—") { (try database.getIndexMode()).rawValue }
        let hidden = safe("getHiddenFilesEnabled", default: false) { try database.getHiddenFilesEnabled() }
        let usageHistoryEnabled = safe("isUsageHistoryEnabled", default: true) {
            try database.isUsageHistoryEnabled()
        }
        let queryHistoryEnabled = safe("isQueryHistoryEnabled", default: true) {
            try database.isQueryHistoryEnabled()
        }

        // --- roots / excludes --------------------------------------
        let rootsAll = safe("listRoots", default: []) { try database.listRoots() }
        let rootsEnabled = rootsAll.filter { $0.enabled }.count
        let rootsTotal = rootsAll.count
        let excludesCount = safe("listExcludes", default: 0) { try database.listExcludes().count }
        // K5: per-root health detail so bug reports identify which
        // specific root has permission / volume / missing-path
        // issues, not just an aggregate count. Caps at 20 lines so
        // mega-multi-root setups don't drown the diagnostics block.
        let rootHealthLines: [String] = rootsAll.prefix(20).map { row in
            let report = database.computeRootHealthReport(for: row)
            return "  \(report.health.uiLabel)  \(row.path)  — \(report.detail)"
        }
        let rootHealthOverflowSuffix = rootsAll.count > 20
            ? "\n  …（截断；共 \(rootsAll.count) 个 root，仅显示前 20）"
            : ""

        // --- last rebuild ------------------------------------------
        let lastAt = safe("getSetting(lastRebuildAt)", default: "—") {
            (try database.getSetting(SettingsKey.lastRebuildAt)) ?? "—"
        }
        let lastResult = safe("getSetting(lastRebuildResult)", default: "—") {
            (try database.getSetting(SettingsKey.lastRebuildResult)) ?? "—"
        }
        let lastStats = safe("getSetting(lastRebuildStats)", default: "—") {
            (try database.getSetting(SettingsKey.lastRebuildStats)) ?? "—"
        }

        // --- Launch at Login ---------------------------------------
        let lalIntent: String
        if let intent = launchAtLoginIntent {
            lalIntent = intent ? "已勾选（用户希望随登录启动）" : "未勾选"
        } else {
            // Fallback to DB-persisted intent when caller didn't
            // pass live UI state (e.g. smoke).
            let v = safe("getLaunchAtLoginRequested", default: false) {
                try database.getLaunchAtLoginRequested()
            }
            lalIntent = v ? "已勾选（用户希望随登录启动）" : "未勾选"
        }
        let lalSystem: String
        if let probe = launchAtLoginSystemStatus, let live = probe() {
            lalSystem = live ? "已注册（SMAppService.enabled / requiresApproval）" : "未注册（SMAppService.notRegistered）"
        } else if launchAtLoginSystemStatus != nil {
            lalSystem = "—（系统不支持 SMAppService 或查询失败）"
        } else {
            lalSystem = "—（headless 报告，无系统查询）"
        }

        // --- M3 reveal target ---------------------------------------
        // Surfaces the user's current "show file in" target so a
        // bug-report copy makes it obvious whether reveal clicks
        // hit Finder, QSpace, or some custom .app — and which open
        // mode (item vs parent folder) the external app receives.
        let revealTarget = safe("getRevealTarget", default: RevealTarget.defaultTarget) {
            try database.getRevealTarget()
        }
        let revealTypeLabel: String
        switch revealTarget.type {
        case .finder: revealTypeLabel = "Finder（默认）"
        case .customApp: revealTypeLabel = "自定义 App"
        }
        let revealOpenModeLabel: String
        switch revealTarget.openMode {
        case .item: revealOpenModeLabel = "文件本身（item）"
        case .parentFolder: revealOpenModeLabel = "父目录（parentFolder）"
        }
        let revealDisplayName = RevealResolver.displayName(for: revealTarget)
        let revealActionTitle = RevealResolver.actionTitle(for: revealTarget)
        let revealCustomPathLine: String = revealTarget.type == .customApp
            ? (revealTarget.customAppPath.isEmpty
                ? "  自定义 App 路径：（未选择）"
                : "  自定义 App 路径：\(revealTarget.customAppPath)")
            : "  自定义 App 路径：—（Finder 模式）"

        // --- assemble ----------------------------------------------
        var out = """
        \(identity)

        数据库：\(dbPath)
        schema 版本：\(schema)
        main / wal / shm 大小：\(mainBytes) / \(walBytes) / \(shmBytes)
        files 行数：\(filesCount)
        file_usage 行数：\(fileUsageCount)
        query_history 行数：\(queryHistoryCount)
        saved_filters 行数：\(savedFiltersCount)
        索引模式：\(indexMode)
        隐藏文件纳入索引：\(hidden ? "是" : "否")
        usage history 记录开关：\(usageHistoryEnabled ? "开" : "关")
        query history 记录开关：\(queryHistoryEnabled ? "开" : "关")

        roots：总 \(rootsTotal)，启用 \(rootsEnabled)
        roots 健康（K5）：
        \(rootHealthLines.isEmpty ? "  （无 root）" : rootHealthLines.joined(separator: "\n"))\(rootHealthOverflowSuffix)
        excludes：\(excludesCount)

        Launch at Login 用户意图：\(lalIntent)
        Launch at Login 系统状态：\(lalSystem)

        Reveal target（M3）：\(revealTypeLabel)
          显示名称：\(revealDisplayName)
          按钮文案：\(revealActionTitle)
          打开模式：\(revealOpenModeLabel)
        \(revealCustomPathLine)

        上次重建时间：\(lastAt)
        上次重建结果：\(lastResult)
        上次重建摘要：\(lastStats)
        """

        if !errors.isEmpty {
            out += "\n\n诊断读取错误：\n" + errors.joined(separator: "\n")
        }
        return out
    }
}
