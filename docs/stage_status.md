# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H3`
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
- `Sources/SwiftSeekSmokeTest/main.swift` 现已包含 H1 + H2 共 12 条 usage 相关 smoke，`swift run --disable-sandbox SwiftSeekSmokeTest` 本轮实测 `150/150` 通过。

## 当前阶段：`H3` - 最近打开 / 常用项体验

### 当前阶段目标
补齐 `recent:` / `frequent:` 或等价入口，让用户能直接回到最近或高频目标，同时保持普通搜索语义稳定不被污染。

### 当前阶段必须做
- 提供 `recent:` 或等价最近打开入口。
- 提供 `frequent:` 或等价常用项入口。
- recent 按 `lastOpenedAt DESC` 返回，frequent 按 `openCount DESC` 返回。
- 普通 query 不被 recent/frequent 模式污染。
- 若实现空查询展示，行为必须可解释、可验证。

### 当前阶段禁止事项
- 不做设置页“关闭记录 / 清空历史”。
- 不做 usage benchmark。
- 不做复杂仪表盘或大范围 UI 重写。
- 不读取 macOS 全局启动次数或系统最近项目。
- 不使用 private API。
- 不扫描系统隐私数据。
- 不上传、不同步、不做遥测。

### 当前阶段完成判定标准
1. `recent:` 或等价入口能返回最近打开项。
2. `frequent:` 或等价入口能返回高频项。
3. 普通搜索不受 recent/frequent 模式污染。
4. 若有空查询展示，行为是可解释和可验证的。
5. 文档明确 recent/frequent 只来自 SwiftSeek 内部行为，不承诺 macOS 全局历史。

## 当前最新 Codex 结论
- `everything-usage / H1` 已于 2026-04-24 在提交 `4e48f45` 通过验收。
- `everything-usage / H2` 已于 2026-04-24 在提交 `b05a216` 通过验收。
- 当前待实现阶段切换为 `H3`。
- H2 通过边界：仅包含 usage join、score tie-break、`openCount/lastOpenedAt` 排序键、结果列、列宽/排序持久化、smoke 与文档收口；不包含 recent/frequent、history 开关/清空、usage benchmark。

## 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 新轨道必须使用新的 Codex 验收 session。
- 不得继续混用已归档 `everything-footprint` 的 session。
