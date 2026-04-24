# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H4`
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint`
- 当前轨道任务书：`docs/everything_usage_taskbook.md`
- 当前差距清单：`docs/everything_usage_gap.md`

## 已归档轨道

### `v1-baseline`
- `PROJECT COMPLETE` 2026-04-23，P0-P6，SwiftSeek v1 基线能力完成。

### `everything-alignment`
- `PROJECT COMPLETE` 2026-04-24，E1-E5，Everything-like 体验第一轮对齐完成。

### `everything-performance`
- `PROJECT COMPLETE` 2026-04-24，F1-F5，搜索热路径 / ranking / 结果视图 / DSL / RootHealth / 索引自动化一轮性能与落地收口。

### `everything-footprint`
- `PROJECT COMPLETE` 2026-04-24，G1-G5，session `019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`。
- 范围：DB 体积观测、compact index、Schema v5、分批回填、索引模式 UI、500k benchmark 与最终收口。
- 结论：大库体积、迁移和维护体验已完成一轮收口。
- 新轨道原因：真实 Everything-like 使用体验还缺少使用历史、打开次数、最近打开和 usage-based tie-break；footprint 的完成结论不覆盖 usage 行为数据。

## 当前活跃轨道：`everything-usage`

### 当前轨道目标
在不读取 macOS 全局隐私数据、不承诺系统级启动次数的前提下，让 SwiftSeek 记录和利用“通过 SwiftSeek 打开”的行为数据，使结果排序、结果视图和最近/常用入口更接近 Everything / launcher 混合型文件搜索器体验。

### 最新代码审计结论
- `Sources/SwiftSeekCore/Schema.swift` 当前 schema 为 v6，新增 `file_usage(file_id, open_count, last_opened_at, updated_at)`，以 `files.id` 外键级联删除。
- `Sources/SwiftSeekCore/UsageTypes.swift` 已提供 `UsageRecord`、`lookupFileId(path:)`、`recordOpen(path:)`、`recordOpen(fileId:)`、`getUsageByFileId`、`getUsageByPath`。
- `Sources/SwiftSeek/UI/ResultActionRunner.swift` 的 `.open` 返回 `NSWorkspace.shared.open(url)` 的 Bool。
- `Sources/SwiftSeek/UI/SearchViewController.swift` 的 `openSelected()` 已在 open 成功后记录 usage，失败不加计数。
- `Sources/SwiftSeekCore/SearchEngine.swift` 的 `SearchResult` 已新增 `openCount` / `lastOpenedAt`，所有搜索 SQL 分支统一 `LEFT JOIN file_usage`，`.score` 相等时按 usage 做 tie-break，且新增 `.openCount` / `.lastOpenedAt` 排序键。
- `Sources/SwiftSeek/UI/SearchViewController.swift` 结果表已新增“打开次数”“最近打开”两列，并接好列头排序与列宽持久化。
- `Sources/SwiftSeekCore/SettingsTypes.swift` 已新增 `result_col_width_open_count` / `result_col_width_last_opened`。
- `Sources/SwiftSeekCore/SearchEngine.swift` 已新增 `UsageMode`、`ParsedQuery.usageMode`、`usageCandidates(mode:, limit:)`，显式支持 `recent:` / `frequent:` 查询。
- `Sources/SwiftSeekSmokeTest/main.swift` 现已包含 H1 + H2 + H3 共 18 条 usage 相关 smoke，`swift run --disable-sandbox SwiftSeekSmokeTest` 本轮实测 `156/156` 通过。

## 当前阶段：`H4` - 使用历史管理与隐私控制

### 当前阶段目标
让 usage history 变成可控、可清理、可解释的隐私数据，而不是只能累加不能管理的内部状态。

### 当前阶段必须做
- 设置页增加“记录使用历史”开关与“清空使用历史”入口。
- 开关持久化到 settings。
- 关闭记录后 `.open` 不再写入 usage。
- 清空后 `file_usage` 为空，结果列 / 排序 / recent/frequent 立即反映。
- DB stats 暴露 usage 表行数或体积信息。

### 当前阶段禁止事项
- 不做 usage benchmark。
- 不做复杂隐私面板或大范围 UI 重写。
- 不读取 macOS 全局启动次数或系统最近项目。
- 不使用 private API。
- 不扫描系统隐私数据。
- 不上传、不同步、不做遥测。

### 当前阶段完成判定标准
1. usage history 开关持久化成功。
2. 关闭后 `.open` 不再写入 usage。
3. 清空后 `file_usage` 为空，结果列 / 排序 / recent/frequent 立即反映。
4. DB stats 能展示 usage 表信息。
5. 文档明确关闭/清空与隐私边界。

## 当前最新 Codex 结论
- `everything-usage / H1` 已于 2026-04-24 在提交 `4e48f45` 通过验收。
- `everything-usage / H2` 已于 2026-04-24 在提交 `b05a216` 通过验收。
- `everything-usage / H3` 已于 2026-04-24 在提交 `28ab4c9` 通过验收。
- 当前待实现阶段切换为 `H4`。
- H3 通过边界：仅包含 `recent:` / `frequent:` 显式入口、usage-mode 路由、filter 组合、普通 query 不回退、smoke 与文档收口；不包含 history 开关/清空、usage benchmark。

## 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 新轨道必须使用新的 Codex 验收 session。
- 不得继续混用已归档 `everything-footprint` 的 session。
