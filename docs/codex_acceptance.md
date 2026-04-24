# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
**VERDICT: PASS**
TRACK: everything-usage
STAGE: H1
ROUND: 1
DATE: 2026-04-24
SESSION_ID: pending-new-track-session

### Summary
`everything-usage / H1` 已通过。提交 `4e48f45` 将 schema 提升到 v6，并新增 `file_usage(file_id, open_count, last_opened_at, updated_at)`；`.open` 成功后才记录 SwiftSeek 内部打开次数，失败不计数；path 不在 DB 时会 `NSLog`，不会 silent fail；删除 `files` 行后 usage 记录随外键级联清理。

本轮实际验收确认：
- `Schema.currentVersion = 6`，`Migration(target: 6)` 创建 `file_usage`。
- `Database.recordOpen(path:)` / `recordOpen(fileId:)` 已落地，支持 lookup、upsert、读取 usage。
- `ResultActionRunner.perform(.open)` 返回 `Bool`，`SearchViewController.openSelected()` 仅在 open 成功后调用 `database.recordOpen(path:)`。
- `SearchResult` / `SearchEngine.sort` / 结果表列头未提前接入 usage。
- `swift build --disable-sandbox` 成功，`swift run --disable-sandbox SwiftSeekSmokeTest` 实际跑到 `144/144`，H1 六条 smoke 全绿。

### Blockers / Required fixes
- None

### Non-blocking notes
1. 当前环境默认 `swift build` / `swift run` 会因为模块缓存与 CLT SDK 组合报错；按仓库文档加 `HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache` 且带 `--disable-sandbox` 后可通过。
2. `docs/agent-state/codex-acceptance-session.json` 仍未写入正式 session id，后续 H2 开始前仍需创建并回填。
3. `reveal` / `copy path` 计数、usage tie-break、recent/frequent、隐私控制仍分别属于 H2-H4，不能混进 H1 已通过范围。

## 当前轨道阶段
- 当前活跃轨道：`everything-usage`
- 当前阶段：`H2`
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
