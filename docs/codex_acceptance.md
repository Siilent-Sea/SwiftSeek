# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: REJECT**
TRACK: everything-footprint
STAGE: G1
ROUND: 0
DATE: 2026-04-24
SESSION_ID: pending-new-track-session

### Summary
用户基于真实使用反馈发起新轨道 `everything-footprint`。历史 `v1-baseline`、`everything-alignment`、`everything-performance` 均已归档，其中 `everything-performance` 已拿到 `PROJECT COMPLETE`，但该结论只覆盖搜索性能和 Everything-like 落地，不覆盖 500k+ 文件规模下 DB footprint、迁移和维护体验。

当前代码审计确认：
- schema v4 同时存在 `file_grams` 与 `file_bigrams`。
- trigram / bigram 都来自 `nameLower + pathLower`，完整路径滑窗会显著放大大库行数。
- v2/v4 migration backfill 在 `Database.migrate()` 的单个事务内执行，且先全量读取 `files` 行到内存。
- App 内没有 DB size / WAL size / table stats / avg grams per file / root attribution 的清晰展示。
- App 内没有 checkpoint / optimize / VACUUM 的安全维护入口。

### Blockers / Required fixes
1. G1 尚未实现 DB stats 能力。
2. G1 尚未实现 CLI / bench DB stats 入口。
3. G1 尚未实现设置 / 维护页简版 stats。
4. G1 尚未实现 checkpoint / optimize / VACUUM 安全入口与 VACUUM 风险确认。
5. G1 尚未补充相关测试和手测记录。

### Non-blocking notes
1. 本轮只完成新轨道立项、差距文档、任务书和状态切换。
2. 不应把 VACUUM / checkpoint 当作根治方案；根治方向应在 G2-G4 通过 compact index 设计和实现推进。

## 当前轨道阶段
- 当前活跃轨道：`everything-footprint`
- 当前阶段：`G1`
- 当前任务书：`docs/next_stage.md`
- 完整阶段计划：`docs/everything_footprint_taskbook.md`
- 差距清单：`docs/everything_footprint_gap.md`

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24

## 轨道切换说明
`everything-footprint` 必须使用新的 Codex 验收 session。不得混用已归档 `everything-performance` 的 session id。
