# Codex 验收记录

本文件只保留当前有效结论。

## 当前有效结论
VERDICT: REJECT (docs-only blockers; functional E2 accepted)
TRACK: everything-alignment
STAGE: E2
ROUND: 1
DATE: 2026-04-24
SESSION_ID: 019dbd4c-e0c9-7370-8a0c-1d4263a9f19b
COMMIT: 1a6f678

### Summary
- 功能面 E2 已全部落地：4 列高密度结果视图（名称 / 路径 / 修改时间 / 大小）、列头点击排序、排序逻辑下沉为 `SearchEngine.sort(_:by:)` pure function（稳定 tie-break + case-insensitive），selection 跨 re-sort 保留，QuickLook / 右键 / 拖拽 / 高亮 / 键盘流全部保留。
- Codex 实测 build + smoke + startup 全绿：`Build complete!` / `Smoke total: 68 pass: 68 fail: 0`（含 7 个新 E2 用例）/ `schema=3 + startup check PASS`。
- 本轮 REJECT 的原因不是功能，而是 3 处协议文档没同步到 E2：`codex_acceptance.md` 还停在 `E1 round 1 REJECT`；`known_issues.md` 还把 E2 目标写成未完成限制；`agent-state/codex-acceptance-session.json` 还停在 `stage=E1 / last_verdict=REJECT`。本次 round 2 已按要求刷新。

### Blockers (round 1)
1. `docs/codex_acceptance.md` 仍是 `E1 / ROUND 1 / REJECT`，未反映 E1 PASS 也未记录 E2。— 已在本次刷新修复。
2. `docs/known_issues.md` 仍写“单列视图 / 无排序切换（留给 E2）”，与当前实现冲突。— 已刷新。
3. `docs/agent-state/codex-acceptance-session.json` 仍是 `stage: E1, last_verdict: REJECT`。— 已刷新。

### Required fixes (round 1)
1. 将 `docs/codex_acceptance.md` 切到 E1 PASS + E2 round 1 真实状态。✓
2. 将 `docs/known_issues.md` 移除 E2 已解决的限制。✓
3. 将 `docs/agent-state/codex-acceptance-session.json` 同步到 E2 当前状态。✓

### Non-blocking notes
1. `docs/stage_status.md` 本次同步到位，问题只在其它 3 个文件。
2. 代码层面 E2 验收点齐全：4 列、排序、默认 score desc、selection 保留、行为不回退。
3. 判断是基于代码路径 + smoke 覆盖，未做桌面手动 GUI 截图。

### Evidence
- 检查文件：`docs/next_stage.md`、`docs/stage_status.md`、`docs/codex_acceptance.md`、`docs/known_issues.md`、`docs/agent-state/codex-acceptance-session.{txt,json}`、`Sources/SwiftSeekCore/SearchEngine.swift`、`Sources/SwiftSeek/UI/SearchViewController.swift`、`Sources/SwiftSeekSmokeTest/main.swift`。
- 运行命令：`swift build --disable-sandbox`、`swift run --disable-sandbox SwiftSeekSmokeTest`、`swift run --disable-sandbox SwiftSeekStartup --db /tmp/ss-e2.sqlite3`。
- 观察：Build complete!；Smoke total 68 pass 68 fail 0；schema=3 + startup check PASS。

## 轨道内已通过阶段
- `E1` — 搜索相关性与结果上限（2026-04-24 round 2 PASS）

## Next stage task book
- 见 `docs/next_stage.md`（当前写的是 E2 任务书；E2 PASS 后 Claude 负责刷新到 E3 任务书）
