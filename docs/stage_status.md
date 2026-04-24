# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H2`
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
- `Sources/SwiftSeekCore/SearchEngine.swift` 的 `SearchResult` 仍只有 `path`、`name`、`isDir`、`size`、`mtime`、`score`；usage 尚未接入结果和排序。
- 当前结果表仍只有 `name` / `path` / `mtime` / `size` 四列，没有 Run Count / 最近打开列。
- `Sources/SwiftSeekSmokeTest/main.swift` 现已包含 H1 六条 usage smoke，`swift run --disable-sandbox SwiftSeekSmokeTest` 本轮实测 `144/144` 通过。

## 当前阶段：`H2` - Usage-based ranking 与结果列

### 当前阶段目标
让常用项在同等文本相关性下更稳定靠前，并把 Run Count / 最近打开展示到结果表中，但不能破坏基础文本相关性。

### 当前阶段必须做
- `SearchResult` 增加 `open_count` 与 `last_opened_at` 字段。
- `SearchEngine` 查询路径 join usage 数据。
- ranking tie-break 引入 usage，但只在同等文本相关性下生效。
- 结果视图增加打开次数与最近打开列。
- 结果表排序支持 usage / last opened。
- 排序与列宽持久化接入现有 settings。

### 当前阶段禁止事项
- 不做最近打开 / 常用项入口。
- 不做设置页“关闭记录 / 清空历史”。
- 不做 usage benchmark。
- 不读取 macOS 全局启动次数或系统最近项目。
- 不使用 private API。
- 不扫描系统隐私数据。
- 不上传、不同步、不做遥测。

### 当前阶段完成判定标准
1. 搜索结果包含 `open_count` 和 `last_opened_at`。
2. 同 score 结果中高 usage 项靠前。
3. 不同 score 结果中高相关项仍优先。
4. 结果表展示打开次数和最近打开。
5. 用户可按 usage / last opened 排序。
6. 现有 name / path / mtime / size 排序不回退。
7. 文档明确 Run Count / 最近打开只来自 SwiftSeek 内部行为。

## 当前最新 Codex 结论
- `everything-usage / H1` 已于 2026-04-24 在提交 `4e48f45` 通过验收。
- 当前待实现阶段切换为 `H2`。
- H1 通过边界：仅包含 usage 数据模型、`.open` 成功记录、失败不计数、path-miss 日志、级联清理、smoke 与文档收口；不包含 ranking、结果列、recent/frequent、设置页或 benchmark。

## 当前活跃轨道验收会话状态
- 会话状态目录：`docs/agent-state/`
- 新轨道必须使用新的 Codex 验收 session。
- 不得继续混用已归档 `everything-footprint` 的 session。
