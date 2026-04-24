# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H5`
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint`
- 当前轨道任务书：`docs/everything_usage_taskbook.md`
- 当前差距清单：`docs/everything_usage_gap.md`
- H5 实测报告：`docs/everything_usage_bench.md`

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
- `Sources/SwiftSeekSmokeTest/main.swift` 现已包含 H1 + H2 + H3 + H4 共 23 条 usage 相关 smoke，`swift run --disable-sandbox SwiftSeekSmokeTest` 本轮实测 `161/161` 通过。

## 当前阶段：`H5` - benchmark 与轨道收口

### 当前阶段目标
对 `everything-usage` 做最终性能与体验收口，证明 usage join、recordOpen、recent/frequent 与 H4 的隐私控制不会破坏大库体验，并给出可复现 benchmark 证据。

### 当前阶段必须做
- 给出 100k / 500k 规模下 usage 轨道关键路径 benchmark。
- 覆盖普通搜索 + usage join、`recent:` / `frequent:`、`recordOpen` 写入耗时。
- benchmark 方法、fixture、命令、环境前提可复现，不写空泛结论。
- 更新 README / known_issues / manual_test / usage 轨道文档，使 Codex 可据此判断 `PROJECT COMPLETE`。
- 验证 H1-H4 已通过能力在 benchmark 轮没有回退。

### 当前阶段禁止事项
- 不新增系统级 usage 导入、其他 App 历史、private API、系统隐私扫描。
- 不借 benchmark 扩 scope 到全文搜索、AI 语义搜索或大规模 UI 改造。
- 不改写 H1-H4 已通过的语义合同，除非是 benchmark 暴露出的真实 blocker 修复。

### 当前阶段完成判定标准
1. benchmark 覆盖 usage 轨道核心路径，且数据可复现。
2. benchmark 结果足以判断 usage 功能未把搜索体验带崩。
3. `swift build --disable-sandbox` 与 `swift run --disable-sandbox SwiftSeekSmokeTest` 继续通过。
4. README / known_issues / manual_test / usage 轨道文档同步到可交付状态。
5. 当前轨道已无阻塞级缺口，Codex 可以据此判断是否 `PROJECT COMPLETE`。

## 当前最新 Codex 结论
- `everything-usage / H1` 已于 2026-04-24 在提交 `4e48f45` 通过验收。
- `everything-usage / H2` 已于 2026-04-24 在提交 `b05a216` 通过验收。
- `everything-usage / H3` 已于 2026-04-24 在提交 `28ab4c9` 通过验收。
- `everything-usage / H4` 已于 2026-04-24 在提交 `fa801af` 通过验收。
- 当前待实现阶段切换为 `H5`。
- H4 通过边界：包含 usage history 开关、清空入口、`recordOpen` gated 行为、`file_usage` stats 暴露、维护页隐私说明，以及 smoke `161/161`；不包含 benchmark 与轨道最终收口。

## 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 新轨道必须使用新的 Codex 验收 session。
- 不得继续混用已归档 `everything-footprint` 的 session。
