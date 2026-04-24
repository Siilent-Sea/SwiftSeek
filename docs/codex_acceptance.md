# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: PASS**
TRACK: everything-usage
STAGE: H2
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbe5f-9680-7872-9eac-cc41e5f0f40e

### Summary
`everything-usage / H2` 已通过。提交 `b05a216` 将 usage 数据真正接到搜索结果、score tie-break、结果表排序和列宽持久化：`SearchResult` 新增 `openCount` / `lastOpenedAt`，所有搜索 SQL 统一 `LEFT JOIN file_usage`，`.score` 相等时按 `openCount DESC -> lastOpenedAt DESC -> short-path -> alpha` 打破平手，结果表新增“打开次数”“最近打开”两列，排序键与列宽都能走现有 settings 持久化。

本轮实际验收确认：
- `SearchResult` 新增 `openCount: Int64` / `lastOpenedAt: Int64`，缺失 usage 行时稳定为 0。
- `SearchEngine` 所有候选查询路径都已接 `LEFT JOIN file_usage`，没有遗漏某个 SQL 分支只返回旧字段。
- `SearchEngine.sort` 只在主键 `.score` 且 score 相等时使用 usage tie-break；`.name` / `.path` / `.mtime` / `.size` 保持 F3 旧语义，`.openCount` / `.lastOpenedAt` 也能单独排序。
- `SearchViewController` 新增“打开次数”“最近打开”列、表头排序映射、列宽持久化键；0 值显示为 `—`。
- `swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 实际跑到 `150/150`，H2 新增 6 条 smoke 全绿。

### Blockers / Required fixes
- None

### Non-blocking notes
1. 当前环境默认 `swift build` / `swift run` 会因为模块缓存与 CLT SDK 组合报错；按仓库文档加 `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache` 且带 `--disable-sandbox` 后可通过。
2. `SearchViewController.swift` 中 H2 注释声称新列表头“首次点击会反转为降序”，但真实实现仍是 AppKit 默认首次升序；当前不影响 H2 任务书要求，只是注释/预期描述不一致，H3 或后续顺手收口即可。
3. `recent:` / `frequent:` 入口、空查询推荐、history 开关/清空、usage benchmark 仍分别属于 H3-H5，不能混进 H2 已通过范围。

## 当前轨道阶段
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H3`
- 当前任务书：`docs/next_stage.md`
- 完整阶段计划：`docs/everything_usage_taskbook.md`
- 差距清单：`docs/everything_usage_gap.md`

## 历史归档轨道
- `v1-baseline`：P0-P6 / PROJECT COMPLETE 2026-04-23
- `everything-alignment`：E1-E5 / PROJECT COMPLETE 2026-04-24
- `everything-performance`：F1-F5 / PROJECT COMPLETE 2026-04-24
- `everything-footprint`：G1-G5 / PROJECT COMPLETE 2026-04-24

## 轨道切换说明
`everything-usage` 必须使用新的 Codex 验收 session。不得混用已归档 `everything-footprint` 的 session id。
