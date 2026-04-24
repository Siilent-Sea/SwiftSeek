# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：**无**（`everything-usage` 已于 2026-04-24 `PROJECT COMPLETE`，H5 round 2，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`）
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage`
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
- 范围：DB 体积观测、compact index、Schema v5、分批回填、索引模式 UI、500k benchmark 与最终收口。
- 500k 实测亮点：compact 1.07 GB vs fullpath 3.46 GB（3.2× 更小），首次索引 44.87s vs 197.62s（4.4× 更快），reopen/migrate ms 级。

### `everything-usage`
- `PROJECT COMPLETE` 2026-04-24，H1-H5，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`。
- H1 round 1 PASS — Schema v6 `file_usage` + `.open` 记录
- H2 round 1 PASS — usage JOIN + 同 score tie-break + 结果表两列 + 排序
- H3 round 1 PASS — `recent:` / `frequent:` 入口 via file_usage INNER JOIN
- H4 round 2 PASS — usage history 隐私开关 + 清空入口 + DBStats 暴露
- H5 round 2 PROJECT COMPLETE — 100k / 500k benchmark + 文档收口
- 500k bench 亮点：3+char 加 100k usage JOIN 中位数 94.33ms（+4ms），`recent:` 89.44ms，`frequent:` 16.87ms，`recordOpen` 8μs。
- 文档位置：
  - 任务书：`docs/everything_usage_taskbook.md`
  - 差距清单：`docs/everything_usage_gap.md`
  - H5 实测报告：`docs/everything_usage_bench.md`
  - 最终验收记录：`docs/codex_acceptance.md`

## 下一步
- 新轨道启动由用户发起
- 历史轨道 session 保留在 `docs/agent-state/codex-acceptance-session.json` 的 `archived_tracks` 数组，不混用
