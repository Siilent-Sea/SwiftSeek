# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: PASS**
TRACK: everything-usage
STAGE: H3
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbe5f-9680-7872-9eac-cc41e5f0f40e

### Summary
`everything-usage / H3` 已通过。提交 `28ab4c9` 新增显式 usage mode：`recent:` / `frequent:`。`ParsedQuery` 现可区分 `.normal / .recent / .frequent`，`search()` 在显式 mode 下改走 `file_usage INNER JOIN files` 的 usageCandidates，并继续复用 root-gate、filter、plain-token name-contain 这套后处理链，因此 recent/frequent 能与现有 `ext:` / `path:` / `root:` / `hidden:` / `kind:` 以及 plain tokens 组合，同时普通 query 路径不被污染。

本轮实际验收确认：
- `UsageMode` / `ParsedQuery.usageMode` 已落地；bare `recent:` / `frequent:` 会切 mode，`recent:foo` 不会被误识别为 mode。
- `usageCandidates(mode:, limit:)` 已按合同使用 `file_usage INNER JOIN files`，并分别按 `last_opened_at DESC, open_count DESC` / `open_count DESC, last_opened_at DESC` 排序。
- usage-mode 查询会绕过普通 `rank()` / filter-only mtime 排序，保留 SQL usage 顺序，且继续复用 root-gate + rowMatches + plain-token name-contain 后处理。
- 普通 query 仍走原 gram/bigram/path-segment/LIKE 候选路径；recent/frequent 只在显式 mode 下生效。
- `swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 实际跑到 `156/156`，H3 新增 6 条 smoke 全绿。

### Blockers / Required fixes
- None

### Non-blocking notes
1. 当前环境默认 `swift build` / `swift run` 会因为模块缓存与 CLT SDK 组合报错；按仓库文档加 `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache` 且带 `--disable-sandbox` 后可通过。
2. `docs/known_issues.md` 里现在有两个 `### 5.` 标题，一个是 H3 recent/frequent，一个是 H4 history 管理缺口；这是文档编号重复，不影响 H3 放行。
3. history 开关/清空、usage 统计/DBStats、usage benchmark 仍分别属于 H4-H5，不能混进 H3 已通过范围。

## 当前轨道阶段
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H4`
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
