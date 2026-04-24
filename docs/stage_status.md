# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：`everything-footprint`
- 当前阶段：`G5`（最终 benchmark + 收口；等待 Codex PROJECT COMPLETE 判定）
- 轨道内已通过：G1 / G2 / G3 / G4（均 2026-04-24 round 2 PASS，session `019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`）
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance`（详细见下）
- 当前轨道任务书：`docs/everything_footprint_taskbook.md`
- 当前差距清单：`docs/everything_footprint_gap.md`
- G2 冻结合同：`docs/everything_footprint_v5_proposal.md`
- G5 实测报告：`docs/everything_footprint_bench.md`

## 已归档轨道

### `v1-baseline`
- `PROJECT COMPLETE` 2026-04-23，P0-P6，SwiftSeek v1 基线能力完成。

### `everything-alignment`
- `PROJECT COMPLETE` 2026-04-24，E1-E5，Everything-like 体验第一轮对齐完成。

### `everything-performance`
- `PROJECT COMPLETE` 2026-04-24，F1-F5，搜索热路径 / ranking / 结果视图 / DSL / RootHealth / 索引自动化一轮性能与落地收口。
- 启动新轨道原因：500k+ 文件真实使用暴露了 DB footprint + migration 体积 + 维护体验的新问题，超出上一轨道收尾范围。

## 当前活跃轨道：`everything-footprint`

### 轨道目标
在不推翻 `everything-performance` 搜索速度成果的前提下，让 500k+ 文件规模下 SwiftSeek 具备：
- DB 体积可观测性（G1）
- 安全的 checkpoint / VACUUM / optimize 维护入口（G1）
- 紧凑索引策略 + 可配置（G3/G4）
- 可恢复 / 可分批 / 失败续跑的迁移路径（G3）
- 实测 500k 规模 benchmark 证据（G5）

### 阶段进度

| 阶段 | 范围 | Round | 状态 |
|------|------|-------|------|
| G1 | DB 体积观测 + 维护入口 | 2 | ✅ PASS |
| G2 | Compact index 设计合同 | 2 | ✅ PASS |
| G3 | Schema v5 + 分流 indexer/search + MigrationCoordinator | 2 | ✅ PASS |
| G4 | 索引模式 UI + 维护页回填 | 2 | ✅ PASS |
| G5 | 500k benchmark + 最终收口 | 1 | ⏳ 等待 Codex PROJECT COMPLETE |

### G5 当前状态
- `SwiftSeekBench --mode {compact,fullpath,both}` + startup/migrate 计时（round 2 补齐）
- `docs/everything_footprint_bench.md` 落地 20k 实测 + 500k 实测（G5 round 2 补齐）
- 所有 G1-G4 文档已刷到当前最终口径
- smoke 138/138

### 当前 Codex session
- session id：`019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`
- 恢复：`codex exec resume <session_id>`
- 已归档轨道 session 保留在 `docs/agent-state/codex-acceptance-session.json` 的 `archived_tracks` 数组，不混用
