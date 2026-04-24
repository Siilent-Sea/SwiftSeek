# SwiftSeek Track Status

本文件只保留当前轨道的当前有效视图。历史 `PROJECT COMPLETE` 只代表对应历史轨道完成，不会自动阻止新轨道继续推进。

## 轨道总览
- 当前活跃轨道：**无**（`everything-ux-parity` 已于 2026-04-25 `PROJECT COMPLETE`，J6 round 1，session `019dc07b-55f0-7712-9d7f-74441d7c81df`）
- 已归档轨道：`v1-baseline` / `everything-alignment` / `everything-performance` / `everything-footprint` / `everything-usage` / `everything-ux-parity`
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
- 500k 实测亮点：compact 1.07 GB vs fullpath 3.46 GB（3.2× 更小），首次索引 44.87s vs 197.62s（4.4× 更快），reopen/migrate ms 级。

### `everything-usage`
- `PROJECT COMPLETE` 2026-04-24，H1-H5，session `019dbe5f-9680-7872-9eac-cc41e5f0f40e`。
- 500k bench 亮点：3+char 加 100k usage JOIN 中位数 94.33ms（+4ms），`recent:` 89.44ms，`frequent:` 16.87ms，`recordOpen` 8μs。

### `everything-ux-parity`
- `PROJECT COMPLETE` 2026-04-25，J1-J6，session `019dc07b-55f0-7712-9d7f-74441d7c81df`。
- J1 round 1 PASS — 设置窗 hide-only close + Dock reopen + 菜单入口稳定
- J2 round 1 PASS — 搜索窗加宽 + 列 tooltip + 重置列宽，Run Count 真正可见
- J3 round 3 PASS — wildcard(`*`/`?`) + phrase(`"..."`) + OR(`|`) + NOT(`!`/`-`)；纯 OR 走 orUnionCandidates 完整检索；OR + 纯 wildcard alt 走 bounded scan union
- J4 round 1 PASS — Schema v7 query_history + saved_filters；隐私开关；搜索窗"最近/收藏"下拉 + 设置页管理
- J5 round 1 PASS — 右键菜单加 Open With… / Copy Name / Copy 完整路径 / Copy 所在文件夹路径；Trash 二次确认；Run Count 隔离仅 Open 计入
- J6 round 1 PROJECT COMPLETE — 首次使用 banner + Launch at Login（SMAppService 公开 API）+ 窗口 frame 记忆 + 设置 tab 记忆 + 最终文档收口
- 文档位置：
  - 任务书：`docs/everything_ux_parity_taskbook.md`
  - 差距清单：`docs/everything_ux_parity_gap.md`
  - 最终验收记录：`docs/codex_acceptance.md`

## 下一步
- 新轨道启动由用户发起
- 历史轨道 session 保留在 `docs/agent-state/codex-acceptance-session.json` 的 `archived_tracks` 数组，不混用

## 当前文档入口
- 历史 UX 差距清单：`docs/everything_ux_parity_gap.md`
- 历史 J1-J6 阶段任务书：`docs/everything_ux_parity_taskbook.md`
- 历史阶段摘要：`docs/next_stage.md`（当前为"无活跃轨道"占位）
