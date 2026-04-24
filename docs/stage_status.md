# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：**无**（`everything-footprint` 已于 2026-04-24 `PROJECT COMPLETE`，round 3，session `019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`）
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint`
- 新轨道启动由用户发起

## 已归档轨道

### `v1-baseline`
- `PROJECT COMPLETE` 2026-04-23，P0-P6，SwiftSeek v1 基线能力完成。

### `everything-alignment`
- `PROJECT COMPLETE` 2026-04-24，E1-E5，Everything-like 体验第一轮对齐完成。

### `everything-performance`
- `PROJECT COMPLETE` 2026-04-24，F1-F5，搜索热路径 / ranking / 结果视图 / DSL / RootHealth / 索引自动化一轮性能与落地收口。

### `everything-footprint`
- `PROJECT COMPLETE` 2026-04-24，G1-G5，session `019dbdf8-b2c9-7c03-b316-dbbf7040d5d9`。
- G1 round 2 PASS — DB 体积观测 + checkpoint / optimize / VACUUM 维护入口（GUI + CLI）
- G2 round 2 PASS — Schema v5 compact proposal 冻结合同
- G3 round 2 PASS — Schema v5 + 分流 indexer/search + MigrationCoordinator 后台分批回填
- G4 round 2 PASS — 索引模式 UI + 维护页 compact 回填按钮
- G5 round 3 PROJECT COMPLETE — 500k 实测 + reopen/migrate 计时 + 最终文档收口
- 500k 实测亮点（release，2026-04-24）：
  - main DB：compact **1.07 GB** vs fullpath **3.46 GB**（0.31×，3.2× 更小，与用户 586k=3.4GB 吻合）
  - 索引行数：compact 23.0M vs fullpath 118.9M（0.19×，5.2× 更少）
  - 首次全量索引：compact 44.87s vs fullpath 197.62s（0.23×，4.4× 更快）
  - reopen time 0.001s / migrate time 0.000s（G3 CREATE-only 承诺验证）
- 文档位置：
  - 任务书：`docs/everything_footprint_taskbook.md`
  - 差距清单：`docs/everything_footprint_gap.md`
  - G2 冻结合同：`docs/everything_footprint_v5_proposal.md`
  - G5 实测报告：`docs/everything_footprint_bench.md`
  - 最终验收记录：`docs/codex_acceptance.md`

## 下一步
- 新轨道启动由用户发起
- 历史轨道 session 保留在 `docs/agent-state/codex-acceptance-session.json` 的 `archived_tracks` 数组，不混用
